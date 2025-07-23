// SelectionTap.swift – v2 (July 2025)
// -------------------------------------------------------------
// Streams JSON with the current text selection – *when possible* –
// while gracefully degrading on apps that ship with Accessibility
// Isolation (e.g. Chrome 126+, Windsurf, some Electron shells).
// -------------------------------------------------------------

import Foundation
import ApplicationServices
import Cocoa

// MARK: – util logging ------------------------------------------------------

enum LogLevel: Int {
    case error = 0
    case warn = 1
    case info = 2
    case debug = 3
}

// Set the current log level - only messages at this level or lower will be logged
// For production, set to .error to only log errors
private let currentLogLevel: LogLevel = .error

// Flag to completely disable debug and info logging for performance
private let disableNonErrorLogs = currentLogLevel == .error

@inline(__always)
private func shouldLog(level: LogLevel) -> Bool {
    return level.rawValue <= currentLogLevel.rawValue
}

@inline(__always)
func logError(_ msg: @autoclosure () -> String) {
    if shouldLog(level: .error) {
        let ts = ISO8601DateFormatter().string(from: .init())
        fputs("[LiveSel][ERROR] \(ts) \(msg())\n", stderr)
    }
}

@inline(__always)
func logWarn(_ msg: @autoclosure () -> String) {
    if shouldLog(level: .warn) && !disableNonErrorLogs {
        let ts = ISO8601DateFormatter().string(from: .init())
        fputs("[LiveSel][WARN] \(ts) \(msg())\n", stderr)
    }
}

@inline(__always)
func logInfo(_ msg: @autoclosure () -> String) {
    if shouldLog(level: .info) && !disableNonErrorLogs {
        let ts = ISO8601DateFormatter().string(from: .init())
        fputs("[LiveSel][INFO] \(ts) \(msg())\n", stderr)
    }
}

@inline(__always)
func logDebug(_ msg: @autoclosure () -> String) {
    if shouldLog(level: .debug) && !disableNonErrorLogs {
        let ts = ISO8601DateFormatter().string(from: .init())
        fputs("[LiveSel][DEBUG] \(ts) \(msg())\n", stderr)
    }
}

// Legacy function for backward compatibility
@inline(__always)
func log(_ msg: @autoclosure () -> String) {
    logInfo(msg())
}

// MARK: – App Fallback Cache -------------------------------------------------

// Cache to store app bundle identifiers that are known to require fallback
class AppFallbackCache {
    private static var knownFallbackApps = Set<String>()
    private static let cacheFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ghost_fallback_apps")
    
    // Load the cache from disk on first access
    private static let _loadOnce: Void = {
        do {
            if FileManager.default.fileExists(atPath: cacheFile.path) {
                let data = try Data(contentsOf: cacheFile)
                if let apps = try? JSONDecoder().decode(Set<String>.self, from: data) {
                    knownFallbackApps = apps
                    logError("Loaded \(apps.count) apps in fallback cache")
                }
            }
        } catch {
            logError("Failed to load fallback cache: \(error)")
        }
    }()
    
    // Check if an app is known to require fallback
    static func requiresFallback(_ bundleIdentifier: String?) -> Bool {
        _ = _loadOnce // Ensure cache is loaded
        guard let bundleId = bundleIdentifier else { return false }
        return knownFallbackApps.contains(bundleId)
    }
    
    // Add an app to the fallback cache
    static func addToFallbackCache(_ bundleIdentifier: String?) {
        _ = _loadOnce // Ensure cache is loaded
        guard let bundleId = bundleIdentifier, !bundleId.isEmpty else { return }
        
        // Only add if it's not already in the cache
        if !knownFallbackApps.contains(bundleId) {
            knownFallbackApps.insert(bundleId)
            logError("Added \(bundleId) to fallback cache")
            saveCacheToDisk()
        }
    }
    
    // Save the cache to disk
    private static func saveCacheToDisk() {
        do {
            let data = try JSONEncoder().encode(knownFallbackApps)
            try data.write(to: cacheFile)
        } catch {
            logError("Failed to save fallback cache: \(error)")
        }
    }
}

// MARK: – SelectionTap -------------------------------------------------------

final class SelectionTap {
    private var selectionObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var pollTimer: Timer?
    private var lastElement: AXUIElement?
    private var tick = 0

    // ---------------------- run -------------------------------------------
    func run() {
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary) else {
            logError("AX access not granted – exiting"); exit(1)
        }

        if let startElem = focusedElement() { hookSelection(on: startElem) }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.pollFocus()
        }
        RunLoop.current.add(pollTimer!, forMode: .default)
    }

    // ---------------------- polling ---------------------------------------
    private func pollFocus() {
        tick += 1
        guard let elem = focusedElement() else { logDebug("tick #\(tick): no focused element"); return }
        if lastElement == nil || !CFEqual(lastElement, elem) {
            logInfo("tick #\(tick): focus changed – re‑hooking")
            lastElement = elem
            hookSelection(on: elem)
        }
    }

    // -------------------- resolve focus -----------------------------------
    private func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElm = AXUIElementCreateApplication(app.processIdentifier)
        
        // Check if this app is known to require fallback
        if AppFallbackCache.requiresFallback(app.bundleIdentifier) {
            logInfo("Skipping accessibility check for known fallback app: \(app.localizedName ?? app.bundleIdentifier ?? "unknown")")
            emitStatus("fallback_needed", "App \(app.localizedName ?? "unknown") is known to require fallback", appName: app.localizedName)
            return nil
        }

        // isolation (undocumented) – informational only
        var isoRef: CFTypeRef?
        let iso = AXUIElementCopyAttributeValue(appElm, "AXIsolatedTree" as CFString, &isoRef) == .success
        logDebug("front app: \(app.localizedName ?? "unknown") pid=\(app.processIdentifier) isolated=\(iso)")
        
        // Emit isolation status for JS layer to know when fallback is needed
        if iso {
            emitStatus("isolated", "App \(app.localizedName ?? "unknown") has accessibility isolation", appName: app.localizedName)
            // Add to fallback cache since isolated apps always need fallback
            AppFallbackCache.addToFallbackCache(app.bundleIdentifier)
        }

        // 1) straight shot
        var val: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(appElm, kAXFocusedUIElementAttribute as CFString, &val)
        if res == .success, let elem = val as! AXUIElement? { return elem }
        logWarn("AXFocusedUIElement failed (err=\(res.rawValue)) – trying fallback walk")
        
        // Emit fallback status when we get accessibility failures like -25212
        if res.rawValue == -25212 || res.rawValue == -25213 {
            emitStatus("fallback_needed", "App \(app.localizedName ?? "unknown") has accessibility limitations (err=\(res.rawValue))", appName: app.localizedName)
            // Add to fallback cache since this app has accessibility limitations
            AppFallbackCache.addToFallbackCache(app.bundleIdentifier)
        }

        // 2) fallback – walk focused window > children > depth‑first
        var winRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElm, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
           let winObj = winRef,
           let deep = deepSearch(in: (winObj as! AXUIElement), depth: 0) {
            logDebug("deepSearch found candidate element")
            return deep
        }

        // 3) nothing – emit fallback needed status for JS layer
        emitStatus("fallback_needed", "Unable to get focused element - accessibility may be limited", appName: app.localizedName)
        return nil
    }

    // depth‑first search for selectable element ----------------------------
    private func deepSearch(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 8 else { return nil } // prevent runaway

        // if element already exposes selected text or value, we’re done
        var attrs: CFArray?
        if AXUIElementCopyAttributeNames(element, &attrs) == .success,
           let list = attrs as? [String] {
            if list.contains(kAXSelectedTextAttribute as String) || list.contains(kAXValueAttribute as String) {
                return element
            }
        }
        // recurse into children
        var kidsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &kidsRef) == .success,
           let kids = kidsRef as? [AXUIElement] {
            for child in kids {
                if let hit = deepSearch(in: child, depth: depth + 1) { return hit }
            }
        }
        return nil
    }

    // ------------------ observer plumbing ---------------------------------
    private func hookSelection(on element: AXUIElement) {
        if let obs = selectionObserver, let old = observedElement {
            AXObserverRemoveNotification(obs, old, kAXSelectedTextChangedNotification as CFString)
            logDebug("removed previous observer")
        }

        var pid: pid_t = 0; AXUIElementGetPid(element, &pid)
        var obsPtr: AXObserver?
        let crt = AXObserverCreate(pid, { _, elem, _, _ in
            if let txt = selectedText(from: elem) { 
                emit(text: txt, status: "success") 
            }
        }, &obsPtr)
        guard crt == .success, let obs = obsPtr else { logError("AXObserverCreate failed (err=\(crt.rawValue))"); return }

        let add = AXObserverAddNotification(obs, element, kAXSelectedTextChangedNotification as CFString, nil)
        if add.rawValue == 0 {
            logDebug("AXObserverAddNotification -> success")
        } else {
            logWarn("AXObserverAddNotification -> err=\(add.rawValue)")
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        selectionObserver = obs
        observedElement = element
    }
}

// MARK: – text extraction helpers -----------------------------------------

private func selectedText(from element: AXUIElement) -> String? {
    var v: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &v) == .success, let s = v as? String, !s.isEmpty {
        logDebug("selectedText via kAXSelectedTextAttribute -> \(String(s.prefix(40)))…"); return s
    }
    if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &v) == .success, let s = v as? String, !s.isEmpty {
        logDebug("selectedText via kAXValueAttribute -> \(String(s.prefix(40)))…"); return s
    }
    // parameterised (rare but included)
    if let len = textLength(element), len > 0 {
        var range = CFRange(location: 0, length: len)
        if let axRange = AXValueCreate(.cfRange, &range) {
            var out: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &out) == .success,
               let s = out as? String, !s.isEmpty {
                logDebug("selectedText via StringForRange -> \(String(s.prefix(40)))…"); return s
            }
        }
    }
    return nil
}

private func textLength(_ elem: AXUIElement) -> Int? {
    var v: CFTypeRef?
    if AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &v) == .success, let s = v as? String { return s.count }
    return nil
}

// MARK: – emit JSON --------------------------------------------------------

private func mousePoint() -> (Int, Int) {
    let p = NSEvent.mouseLocation; let h = NSScreen.main!.frame.height
    return (Int(p.x), Int(h - p.y))
}

private func emit(text: String, status: String = "success") {
    let (x, y) = mousePoint()
    let obj: [String: Any] = ["text": text, "x": x, "y": y, "ts": Int(Date().timeIntervalSince1970*1000), "status": status]
    if let data = try? JSONSerialization.data(withJSONObject: obj) {
        print(String(data: data, encoding: .utf8)!); fflush(stdout)
    }
}

private func emitStatus(_ status: String, _ message: String = "", appName: String? = nil) {
    let (x, y) = mousePoint()
    var obj: [String: Any] = ["status": status, "message": message, "x": x, "y": y, "ts": Int(Date().timeIntervalSince1970*1000)]
    if let appName = appName {
        obj["appName"] = appName
    }
    if let data = try? JSONSerialization.data(withJSONObject: obj) {
        print(String(data: data, encoding: .utf8)!); fflush(stdout)
    }
}

// MARK: – bootstrap --------------------------------------------------------

let tap = SelectionTap()
logInfo("SelectionTap launching…")
tap.run()
RunLoop.current.run()
