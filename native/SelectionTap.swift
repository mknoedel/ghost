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

@inline(__always)
func log(_ msg: @autoclosure () -> String) {
    let ts = ISO8601DateFormatter().string(from: .init())
    fputs("[LiveSel] \(ts) \(msg())\n", stderr)
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
            log("AX access not granted – exiting"); exit(1)
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
        guard let elem = focusedElement() else { log("tick #\(tick): no focused element"); return }
        if lastElement == nil || !CFEqual(lastElement, elem) {
            log("tick #\(tick): focus changed – re‑hooking")
            lastElement = elem
            hookSelection(on: elem)
        }
    }

    // -------------------- resolve focus -----------------------------------
    private func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElm = AXUIElementCreateApplication(app.processIdentifier)

        // isolation (undocumented) – informational only
        var isoRef: CFTypeRef?
        let iso = AXUIElementCopyAttributeValue(appElm, "AXIsolatedTree" as CFString, &isoRef) == .success
        log("front app: \(app.localizedName ?? "unknown") pid=\(app.processIdentifier) isolated=\(iso)")
        
        // Emit isolation status for JS layer to know when fallback is needed
        if iso {
            emitStatus("isolated", "App \(app.localizedName ?? "unknown") has accessibility isolation", appName: app.localizedName)
        }

        // 1) straight shot
        var val: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(appElm, kAXFocusedUIElementAttribute as CFString, &val)
        if res == .success, let elem = val as! AXUIElement? { return elem }
        log("AXFocusedUIElement failed (err=\(res.rawValue)) – trying fallback walk")
        
        // Emit fallback status when we get accessibility failures like -25212
        if res.rawValue == -25212 || res.rawValue == -25213 {
            emitStatus("fallback_needed", "App \(app.localizedName ?? "unknown") has accessibility limitations (err=\(res.rawValue))", appName: app.localizedName)
        }

        // 2) fallback – walk focused window > children > depth‑first
        var winRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElm, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
           let winObj = winRef,
           let deep = deepSearch(in: (winObj as! AXUIElement), depth: 0) {
            log("deepSearch found candidate element")
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
            log("removed previous observer")
        }

        var pid: pid_t = 0; AXUIElementGetPid(element, &pid)
        var obsPtr: AXObserver?
        let crt = AXObserverCreate(pid, { _, elem, _, _ in
            if let txt = selectedText(from: elem) { 
                emit(text: txt, status: "success") 
            }
        }, &obsPtr)
        guard crt == .success, let obs = obsPtr else { log("AXObserverCreate failed (err=\(crt.rawValue))"); return }

        let add = AXObserverAddNotification(obs, element, kAXSelectedTextChangedNotification as CFString, nil)
        log("AXObserverAddNotification -> \(add.rawValue == 0 ? "success" : "err=\(add.rawValue)")")

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        selectionObserver = obs
        observedElement = element
    }
}

// MARK: – text extraction helpers -----------------------------------------

private func selectedText(from element: AXUIElement) -> String? {
    var v: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &v) == .success, let s = v as? String, !s.isEmpty {
        log("selectedText via kAXSelectedTextAttribute -> \(String(s.prefix(40)))…"); return s
    }
    if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &v) == .success, let s = v as? String, !s.isEmpty {
        log("selectedText via kAXValueAttribute -> \(String(s.prefix(40)))…"); return s
    }
    // parameterised (rare but included)
    if let len = textLength(element), len > 0 {
        var range = CFRange(location: 0, length: len)
        if let axRange = AXValueCreate(.cfRange, &range) {
            var out: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &out) == .success,
               let s = out as? String, !s.isEmpty {
                log("selectedText via StringForRange -> \(String(s.prefix(40)))…"); return s
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
log("SelectionTap launching…")
tap.run()
RunLoop.current.run()
