// SelectionTap.swift – v2 (July 2025)
// -------------------------------------------------------------
// Streams JSON with the current text selection – *when possible* –
// while gracefully degrading on apps that ship with Accessibility
// Isolation (e.g. Chrome 126+, Windsurf, some Electron shells).
// -------------------------------------------------------------

import ApplicationServices
import Cocoa
import Foundation
import Quartz
import IOKit.ps

// MARK: – Data Collection Configuration ----------------------------------------

public struct DataCollectorConfig {
    public let textSelection: Bool
    public let focusTracking: Bool
    public let windowContext: Bool
    public let browserData: Bool
    public let systemMetrics: Bool
    public let inputPatterns: Bool
    public let timeContext: Bool
    
    public init(textSelection: Bool, focusTracking: Bool, windowContext: Bool, browserData: Bool, systemMetrics: Bool, inputPatterns: Bool, timeContext: Bool) {
        self.textSelection = textSelection
        self.focusTracking = focusTracking
        self.windowContext = windowContext
        self.browserData = browserData
        self.systemMetrics = systemMetrics
        self.inputPatterns = inputPatterns
        self.timeContext = timeContext
    }
    
    public static let `default` = DataCollectorConfig(
        textSelection: true,
        focusTracking: true,
        windowContext: false,
        browserData: false,
        systemMetrics: false,
        inputPatterns: false,
        timeContext: false
    )
    
    public static let comprehensive = DataCollectorConfig(
        textSelection: true,
        focusTracking: true,
        windowContext: true,
        browserData: true,
        systemMetrics: true,
        inputPatterns: true,
        timeContext: true
    )
}

// MARK: – Data Collector Protocol ---------------------------------------------

protocol DataCollector {
    var isEnabled: Bool { get }
    var collectorName: String { get }
    func collect() -> [String: Any]
    func shouldCollect(for app: NSRunningApplication?) -> Bool
}

// MARK: – Data Collector Implementations -------------------------------------

class TextSelectionCollector: DataCollector {
    let isEnabled: Bool
    let collectorName = "textSelection"
    
    init(enabled: Bool) {
        self.isEnabled = enabled
    }
    
    func shouldCollect(for app: NSRunningApplication?) -> Bool {
        return isEnabled && app != nil
    }
    
    func collect() -> [String: Any] {
        guard let app = NSWorkspace.shared.frontmostApplication else { return [:] }
        
        let appElm = AXUIElementCreateApplication(app.processIdentifier)
        
        // Try multiple methods to find focused element and extract text
        if let text = extractTextFromApp(appElm) {
            return [
                "text": text,
                "source": "accessibility",
                "status": "success"
            ]
        }
        
        // Only check fallback cache after accessibility methods fail
        if AppFallbackCache.requiresFallback(app.bundleIdentifier) {
            return ["status": "fallback_required"]
        }
        
        return ["status": "no_text_available"]
    }
    
    private func extractTextFromApp(_ appElm: AXUIElement) -> String? {
        // Method 1: Try focused UI element
        if let focusedElem = getFocusedElement(from: appElm) {
            if let text = selectedText(from: focusedElem), !text.isEmpty {
                return text
            }
            if let text = getTextFieldContext(from: focusedElem), !text.isEmpty {
                return text
            }
        }
        
        // Method 2: Try focused window approach
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElm, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let windowObj = windowRef,
           CFGetTypeID(windowObj) == AXUIElementGetTypeID() {
            let window = windowObj as! AXUIElement
            
            if let focusedInWindow = getFocusedElement(from: window) {
                if let text = selectedText(from: focusedInWindow), !text.isEmpty {
                    return text
                }
                if let text = getTextFieldContext(from: focusedInWindow), !text.isEmpty {
                    return text
                }
            }
        }
        
        // Method 3: Try main window if focused window fails
        var mainWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElm, kAXMainWindowAttribute as CFString, &mainWindowRef) == .success,
           let mainWindowObj = mainWindowRef,
           CFGetTypeID(mainWindowObj) == AXUIElementGetTypeID() {
            let mainWindow = mainWindowObj as! AXUIElement
            
            if let focusedInMain = getFocusedElement(from: mainWindow) {
                if let text = selectedText(from: focusedInMain), !text.isEmpty {
                    return text
                }
                if let text = getTextFieldContext(from: focusedInMain), !text.isEmpty {
                    return text
                }
            }
        }
        
        return nil
    }
    
    private func getFocusedElement(from appElement: AXUIElement) -> AXUIElement? {
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        
        if result == .success, let validVal = focusedRef {
            if CFGetTypeID(validVal) == AXUIElementGetTypeID() {
                return (validVal as! AXUIElement)
            }
        }
        
        return nil
    }
}

class FocusTrackingCollector: DataCollector {
    let isEnabled: Bool
    let collectorName = "focusTracking"
    
    private var lastAppInfo: [String: Any]?
    private var lastFocusChangeTime: Date = Date()
    
    init(enabled: Bool) {
        self.isEnabled = enabled
    }
    
    func shouldCollect(for app: NSRunningApplication?) -> Bool {
        return isEnabled
    }
    
    func collect() -> [String: Any] {
        let currentAppInfo = getCurrentAppInfo()
        let currentTime = Date()
        
        // Check if focus has changed
        let focusChanged = hasAppInfoChanged(current: currentAppInfo, previous: lastAppInfo)
        
        var focusData: [String: Any] = [
            "app": currentAppInfo,
            "focusChanged": focusChanged
        ]
        
        if focusChanged {
            let focusDuration = currentTime.timeIntervalSince(lastFocusChangeTime)
            focusData["focusDuration"] = focusDuration
            focusData["eventType"] = "focus_change"
            
            if let previousAppInfo = lastAppInfo {
                focusData["previousApp"] = previousAppInfo
            }
            
            lastAppInfo = currentAppInfo
            lastFocusChangeTime = currentTime
        } else {
            let timeSinceLastChange = currentTime.timeIntervalSince(lastFocusChangeTime)
            focusData["focusDuration"] = timeSinceLastChange
            focusData["eventType"] = "focus_heartbeat"
        }
        
        return focusData
    }
    
    private func hasAppInfoChanged(current: [String: Any], previous: [String: Any]?) -> Bool {
        guard let previous = previous else { return true }
        
        let currentBundle = current["bundleIdentifier"] as? String ?? ""
        let previousBundle = previous["bundleIdentifier"] as? String ?? ""
        let currentPID = current["processIdentifier"] as? Int ?? -1
        let previousPID = previous["processIdentifier"] as? Int ?? -1
        
        return currentBundle != previousBundle || currentPID != previousPID
    }
}

class WindowContextCollector: DataCollector {
    let isEnabled: Bool
    let collectorName = "windowContext"
    
    init(enabled: Bool) {
        self.isEnabled = enabled
    }
    
    func shouldCollect(for app: NSRunningApplication?) -> Bool {
        return isEnabled && app != nil
    }
    
    func collect() -> [String: Any] {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return ["error": "No frontmost application"]
        }
        
        var context: [String: Any] = [
            "appName": app.localizedName ?? "Unknown",
            "bundleId": app.bundleIdentifier ?? "unknown"
        ]
        
        let appElm = AXUIElementCreateApplication(app.processIdentifier)
        
        // Get focused window
        var windowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElm, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        if windowResult == .success,
           let windowObj = windowRef,
           CFGetTypeID(windowObj) == AXUIElementGetTypeID() {
            let window = windowObj as! AXUIElement
            
            // Window title
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String {
                context["windowTitle"] = title
            }
            
            // Window position
            var positionRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
               let position = positionRef {
                var point = CGPoint.zero
                if AXValueGetValue(position as! AXValue, .cgPoint, &point) {
                    context["windowPosition"] = ["x": point.x, "y": point.y]
                }
            }
            
            // Window size
            var sizeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let size = sizeRef {
                var cgSize = CGSize.zero
                if AXValueGetValue(size as! AXValue, .cgSize, &cgSize) {
                    context["windowSize"] = ["width": cgSize.width, "height": cgSize.height]
                }
            }
        } else {
            // Accessibility failed - still provide basic info
            context["accessibilityStatus"] = "failed"
            context["windowTitle"] = "Accessibility Required"
        }
        
        return context
    }
}

class BrowserDataCollector: DataCollector {
    let isEnabled: Bool
    let collectorName = "browserData"
    
    init(enabled: Bool) {
        self.isEnabled = enabled
    }
    
    func shouldCollect(for app: NSRunningApplication?) -> Bool {
        guard isEnabled, let app = app, let bundleId = app.bundleIdentifier else { return false }
        return bundleId.contains("chrome") || bundleId.contains("safari") || bundleId.contains("firefox") || bundleId.contains("edge")
    }
    
    func collect() -> [String: Any] {
        guard let app = NSWorkspace.shared.frontmostApplication else { return [:] }
        
        let appElm = AXUIElementCreateApplication(app.processIdentifier)
        var browserContext: [String: Any] = [:]
        
        // Get focused window
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElm, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let windowObj = windowRef,
           CFGetTypeID(windowObj) == AXUIElementGetTypeID() {
            let window = windowObj as! AXUIElement
            
            // Try to get URL from address bar
            var urlRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, "AXURL" as CFString, &urlRef) == .success,
               let url = urlRef as? String {
                browserContext["currentURL"] = url
                browserContext["domain"] = extractDomain(from: url)
            }
            
            // Try to get tab information
            var tabsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, "AXTabs" as CFString, &tabsRef) == .success,
               let tabs = tabsRef as? [AXUIElement] {
                browserContext["tabCount"] = tabs.count
            }
        }
        
        return browserContext
    }
    
    private func extractDomain(from url: String) -> String {
        guard let urlObj = URL(string: url) else { return "unknown" }
        return urlObj.host ?? "unknown"
    }
}

class SystemMetricsCollector: DataCollector {
    let isEnabled: Bool
    let collectorName = "systemMetrics"
    
    init(enabled: Bool) {
        self.isEnabled = enabled
    }
    
    func shouldCollect(for app: NSRunningApplication?) -> Bool {
        return isEnabled
    }
    
    func collect() -> [String: Any] {
        var metrics: [String: Any] = [:]
        
        // Screen information
        if let screen = NSScreen.main {
            metrics["screenSize"] = [
                "width": screen.frame.width,
                "height": screen.frame.height
            ]
            metrics["screenScale"] = screen.backingScaleFactor
        }
        
        // Battery information (simplified for now)
        // TODO: Re-implement battery monitoring with proper IOKit integration
        metrics["batteryLevel"] = "unavailable"
        metrics["isCharging"] = "unavailable"
        
        return metrics
    }
}

class TimeContextCollector: DataCollector {
    let isEnabled: Bool
    let collectorName = "timeContext"
    
    init(enabled: Bool) {
        self.isEnabled = enabled
    }
    
    func shouldCollect(for app: NSRunningApplication?) -> Bool {
        return isEnabled
    }
    
    func collect() -> [String: Any] {
        let now = Date()
        let calendar = Calendar.current
        
        return [
            "hour": calendar.component(.hour, from: now),
            "dayOfWeek": calendar.component(.weekday, from: now),
            "isWeekend": calendar.isDateInWeekend(now),
            "timeOfDay": getTimeOfDay(hour: calendar.component(.hour, from: now))
        ]
    }
    
    private func getTimeOfDay(hour: Int) -> String {
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }
}

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
    level.rawValue <= currentLogLevel.rawValue
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
    if shouldLog(level: .warn), !disableNonErrorLogs {
        let ts = ISO8601DateFormatter().string(from: .init())
        fputs("[LiveSel][WARN] \(ts) \(msg())\n", stderr)
    }
}

@inline(__always)
func logInfo(_ msg: @autoclosure () -> String) {
    if shouldLog(level: .info), !disableNonErrorLogs {
        let ts = ISO8601DateFormatter().string(from: .init())
        fputs("[LiveSel][INFO] \(ts) \(msg())\n", stderr)
    }
}

@inline(__always)
func logDebug(_ msg: @autoclosure () -> String) {
    if shouldLog(level: .debug), !disableNonErrorLogs {
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
    // Manual flag to enable/disable cache usage for testing
    static var isCacheEnabled = true
    private static var knownFallbackApps = Set<String>()
    private static let cacheFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ghost_fallback_apps")

    // Load the cache from disk on first access
    private static let _loadOnce: Void = {
        do {
            if FileManager.default.fileExists(atPath: cacheFile.path) {
                let data = try Data(contentsOf: cacheFile)
                if let apps = try? JSONDecoder().decode(Set<String>.self, from: data) {
                    knownFallbackApps = apps
                    logInfo("Loaded \(apps.count) apps in fallback cache")
                }
            }
        }
        catch {
            logError("Failed to load fallback cache: \(error)")
        }
    }()

    // Check if an app is known to require fallback
    static func requiresFallback(_ bundleIdentifier: String?) -> Bool {
        _ = _loadOnce // Ensure cache is loaded
        guard let bundleId = bundleIdentifier else { return false }
        // Only check the cache if it's enabled
        return isCacheEnabled && knownFallbackApps.contains(bundleId)
    }

    // Add an app to the fallback cache
    static func addToFallbackCache(_ bundleIdentifier: String?) {
        _ = _loadOnce // Ensure cache is loaded
        guard let bundleId = bundleIdentifier, !bundleId.isEmpty else { return }

        // Only proceed if cache is enabled
        if isCacheEnabled {
            // Only add if it's not already in the cache
            if !knownFallbackApps.contains(bundleId) {
                knownFallbackApps.insert(bundleId)
                logError("Added \(bundleId) to fallback cache")
                saveCacheToDisk()
            }
        }
        else {
            logDebug("Cache disabled: skipped adding \(bundleId) to fallback cache")
        }
    }

    // Save the cache to disk
    private static func saveCacheToDisk() {
        do {
            let data = try JSONEncoder().encode(knownFallbackApps)
            try data.write(to: cacheFile)
        }
        catch {
            logError("Failed to save fallback cache: \(error)")
        }
    }
}

public final class SelectionTap {
    private var selectionObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var pollTimer: Timer?
    private var textSelectionTimer: Timer?
    private var tick = 0
    private var lastLoggedApp: String?
    
    // Enhanced focus tracking
    private var lastAppInfo: [String: Any]?
    private var lastFocusChangeTime: Date = Date()
    private var focusTrackingTimer: Timer?
    
    // Text selection change tracking
    private var lastTextSelection: String = ""
    private var lastTextApp: String = ""
    
    // Modular data collection system
    private let config: DataCollectorConfig
    private let dataCollectors: [DataCollector]
    
    // MARK: - Initialization
    init(config: DataCollectorConfig = .default) {
        self.config = config
        self.dataCollectors = [
            TextSelectionCollector(enabled: config.textSelection),
            FocusTrackingCollector(enabled: config.focusTracking),
            WindowContextCollector(enabled: config.windowContext),
            BrowserDataCollector(enabled: config.browserData),
            SystemMetricsCollector(enabled: config.systemMetrics),
            TimeContextCollector(enabled: config.timeContext)
        ]
    }

    // ---------------------- run -------------------------------------------
    public func run() {
        let options: [String: Any] = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
        ]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            logError("AX access not granted – exiting")
            exit(1)
        }

        // Unified data collection timer
        pollTimer = Timer
            .scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.collectAndEmitData()
            }
        if let timer = pollTimer {
            RunLoop.current.add(timer, forMode: .default)
        }
        
        // Separate faster timer for text selection changes
        textSelectionTimer = Timer
            .scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.checkTextSelectionChanges()
            }
        if let textTimer = textSelectionTimer {
            RunLoop.current.add(textTimer, forMode: .default)
        }
        
        // Emit initial data
        collectAndEmitData()
    }

    // -------------------- text selection change detection ------------------
    private func checkTextSelectionChanges() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        
        // Only check text selection for accessible apps
        if AppFallbackCache.requiresFallback(app.bundleIdentifier) {
            return
        }
        
        let currentAppId = app.bundleIdentifier ?? "unknown"
        
        // Use the TextSelectionCollector to get current text
        if let textCollector = dataCollectors.first(where: { $0.collectorName == "textSelection" }) as? TextSelectionCollector {
            let textData = textCollector.collect()
            
            if let currentText = textData["text"] as? String, !currentText.isEmpty {
                // Check if text or app has changed
                if currentText != lastTextSelection || currentAppId != lastTextApp {
                    lastTextSelection = currentText
                    lastTextApp = currentAppId
                    
                    // Emit text selection event immediately
                    var textEvent = textData
                    textEvent["app"] = getCurrentAppInfo()
                    textEvent["ts"] = Int(Date().timeIntervalSince1970 * 1000)
                    textEvent["x"] = mousePoint().0
                    textEvent["y"] = mousePoint().1
                    
                    emitJSON(textEvent)
                }
            } else {
                // Clear last selection if no text is available
                if !lastTextSelection.isEmpty {
                    lastTextSelection = ""
                    lastTextApp = currentAppId
                }
            }
        }
    }

    // -------------------- unified data collection -------------------------
    private func collectAndEmitData() {
        tick += 1
        let currentApp = NSWorkspace.shared.frontmostApplication
        
        // Collect data from all enabled collectors
        var collectedData: [String: Any] = [
            "ts": Int(Date().timeIntervalSince1970 * 1000),
            "tick": tick
        ]
        
        // Add mouse position (always collected)
        let (x, y) = mousePoint()
        collectedData["x"] = x
        collectedData["y"] = y
        
        // Run all collectors
        for collector in dataCollectors {
            if collector.shouldCollect(for: currentApp) {
                let data = collector.collect()
                if !data.isEmpty {
                    collectedData[collector.collectorName] = data
                }
            }
        }
        
        // Emit the collected data
        emitCollectedData(collectedData)
    }
    
    private func emitCollectedData(_ data: [String: Any]) {
        // Determine the type of emission based on collected data
        if let focusData = data["focusTracking"] as? [String: Any],
           let eventType = focusData["eventType"] as? String {
            
            // This is a focus tracking event
            var focusEvent = data
            focusEvent["eventType"] = eventType
            
            // Move focus-specific data to top level for backward compatibility
            if let app = focusData["app"] {
                focusEvent["app"] = app
            }
            if let focusDuration = focusData["focusDuration"] {
                focusEvent["focusDuration"] = focusDuration
            }
            if let previousApp = focusData["previousApp"] {
                focusEvent["previousApp"] = previousApp
            }
            if let focusChanged = focusData["focusChanged"] as? Bool, focusChanged {
                // Only emit focus change events, not heartbeats unless it's a significant interval
                if eventType == "focus_change" || 
                   (eventType == "focus_heartbeat" && shouldEmitHeartbeat(focusData)) {
                    emitJSON(focusEvent)
                }
            }
        } else if let textData = data["textSelection"] as? [String: Any],
                  let text = textData["text"] as? String, !text.isEmpty {
            
            // This is a text selection event
            var textEvent = data
            textEvent["text"] = text
            textEvent["status"] = textData["status"] ?? "success"
            textEvent["source"] = textData["source"] ?? "unknown"
            
            emitJSON(textEvent)
        } else {
            // Check if we have any modular collector data to emit
            let modularCollectors = ["windowContext", "browserData", "systemMetrics", "timeContext"]
            let hasModularData = modularCollectors.contains { collectorName in
                if let collectorData = data[collectorName] as? [String: Any] {
                    return !collectorData.isEmpty
                }
                return false
            }
            
            // Emit comprehensive data if we have any modular collector data
            if hasModularData {
                var comprehensiveEvent = data
                comprehensiveEvent["eventType"] = "comprehensive_data"
                emitJSON(comprehensiveEvent)
            }
        }
    }
    
    private func shouldEmitHeartbeat(_ focusData: [String: Any]) -> Bool {
        guard let duration = focusData["focusDuration"] as? TimeInterval else { return false }
        // Emit heartbeat every 10 seconds
        return duration.truncatingRemainder(dividingBy: 10.0) < 1.0
    }
    
    private func emitJSON(_ data: [String: Any]) {
        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            fputs(jsonString + "\n", stdout)
            fflush(stdout)
        }
    }

    // ---------------------- legacy methods (deprecated) ------------------
    // These methods are kept for backward compatibility but are no longer used
    // in the modular architecture. They may be removed in future versions.

    // -------------------- resolve focus -----------------------------------
    private func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElm = AXUIElementCreateApplication(app.processIdentifier)

        // Log focused app changes for debugging
        let currentAppId = app.bundleIdentifier ?? "unknown"
        if lastLoggedApp != currentAppId {
            lastLoggedApp = currentAppId
            let appName = app.localizedName ?? currentAppId
            logInfo("Focused app: \(appName) (\(currentAppId))")
        }

        // Check if this app is known to require fallback
        if AppFallbackCache.requiresFallback(app.bundleIdentifier) {
            let appName = app.localizedName ?? app.bundleIdentifier ?? "unknown"
            logInfo("Skipping accessibility check for known fallback app: \(appName)")
            emitStatus(
                "fallback_needed",
                "App \(app.localizedName ?? "unknown") is known to require fallback",
                appName: app.localizedName
            )
            return nil
        }

        // isolation (undocumented) – informational only
        var isoRef: CFTypeRef?
        // swiftlint:disable:next ax_error_handling
        let iso = AXUIElementCopyAttributeValue(
            appElm,
            "AXIsolatedTree" as CFString,
            &isoRef
        ) ==
            .success
        let appName = app.localizedName ?? "unknown"
        logDebug("front app: \(appName) pid=\(app.processIdentifier) isolated=\(iso)")

        // Emit isolation status for JS layer to know when fallback is needed
        if iso {
            emitStatus(
                "isolated",
                "App \(app.localizedName ?? "unknown") has accessibility isolation",
                appName: app.localizedName
            )
            // Add to fallback cache since isolated apps always need fallback
            AppFallbackCache.addToFallbackCache(app.bundleIdentifier)
        }

        // 1) straight shot
        var val: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(
            appElm,
            kAXFocusedUIElementAttribute as CFString,
            &val
        )
        if res == .success, let validVal = val {
            if CFGetTypeID(validVal) == AXUIElementGetTypeID() {
                let elem = validVal as! AXUIElement
                return elem
            }
        }
        logWarn("AXFocusedUIElement failed (err=\(res.rawValue)) – trying fallback walk")

        // Emit fallback status when we get accessibility failures like -25212
        if res.rawValue == -25212 || res.rawValue == -25213 {
            let appName = app.localizedName ?? "unknown"
            let message = "App \(appName) has accessibility limitations (err=\(res.rawValue))"
            emitStatus("fallback_needed", message, appName: app.localizedName)
            // Add to fallback cache since this app has accessibility limitations
            AppFallbackCache.addToFallbackCache(app.bundleIdentifier)
        }

        // 2) fallback – walk focused window > children > depth‑first
        var winRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                appElm,
                kAXFocusedWindowAttribute as CFString,
                &winRef
            ) ==
            .success,
            let winObj = winRef,
            let deep = deepSearch(in: (winObj as! AXUIElement), depth: 0) {
            logDebug("deepSearch found candidate element")
            return deep
        }

        // 3) nothing – emit fallback needed status for JS layer
        emitStatus(
            "fallback_needed",
            "Unable to get focused element - accessibility may be limited",
            appName: app.localizedName
        )
        return nil
    }

    // depth‑first search for selectable element ----------------------------
    private func deepSearch(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 8 else { return nil } // prevent runaway

        // if element already exposes selected text or value, we’re done
        var attrs: CFArray?
        if
            AXUIElementCopyAttributeNames(element, &attrs) == .success,
            let list = attrs as? [String] {
            if
                list.contains(kAXSelectedTextAttribute as String) || list
                    .contains(kAXValueAttribute as String) {
                return element
            }
        }
        // recurse into children
        var kidsRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &kidsRef
            ) ==
            .success,
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
            AXObserverRemoveNotification(
                obs,
                old,
                kAXSelectedTextChangedNotification as CFString
            )
            logDebug("removed previous observer")
        }

        var pid: pid_t = 0; AXUIElementGetPid(element, &pid)
        var obsPtr: AXObserver?
        let crt = AXObserverCreate(pid, { _, elem, _, _ in
            if let txt = selectedText(from: elem) {
                emit(text: txt, status: "success")
            }
        }, &obsPtr)
        guard
            crt == .success,
            let obs = obsPtr
        else { logError("AXObserverCreate failed (err=\(crt.rawValue))"); return }

        let add = AXObserverAddNotification(
            obs,
            element,
            kAXSelectedTextChangedNotification as CFString,
            nil
        )
        if add.rawValue == 0 {
            logDebug("AXObserverAddNotification -> success")
        }
        else {
            logWarn("AXObserverAddNotification -> err=\(add.rawValue)")
        }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )
        selectionObserver = obs
        observedElement = element
    }

    // -------------------- legacy focus tracking (deprecated) --------------
    // This functionality has been moved to FocusTrackingCollector
    // These methods are kept for reference but are no longer used
}

// MARK: – Enhanced text extraction helpers ------------------------------------

private func selectedText(from element: AXUIElement) -> String? {
    // First try the enhanced selection gathering
    if let enhanced = enhancedSelectedText(from: element) {
        return enhanced
    }

    // Fall back to original implementation
    var v: CFTypeRef?
    if
        AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &v
        ) ==
        .success,
        let s = v as? String, !s.isEmpty {
        logDebug("selectedText via kAXSelectedTextAttribute -> \(String(s.prefix(40)))…"
        ); return s
    }
    if
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &v) ==
        .success,
        let s = v as? String, !s.isEmpty {
        logDebug("selectedText via kAXValueAttribute -> \(String(s.prefix(40)))…"
        ); return s
    }
    // parameterised (rare but included)
    if let len = textLength(element), len > 0 {
        var range = CFRange(location: 0, length: len)
        if let axRange = AXValueCreate(.cfRange, &range) {
            var out: CFTypeRef?
            if
                AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXStringForRangeParameterizedAttribute as CFString,
                    axRange,
                    &out
                ) == .success,
                let s = out as? String, !s.isEmpty {
                logDebug("selectedText via StringForRange -> \(String(s.prefix(40)))…"
                ); return s
            }
        }
    }
    return nil
}

private func enhancedSelectedText(from element: AXUIElement) -> String? {
    // Stage 1: Try to get current selection via accessibility APIs
    if let selection = getCurrentSelection(from: element) {
        logDebug("Enhanced: Got current selection via accessibility")
        return selection
    }

    // Stage 2: Try to get broader context from the text field (for accessible apps only)
    if let context = getTextFieldContext(from: element) {
        logDebug("Enhanced: Got text field context")
        return context
    }

    return nil
}

private func getCurrentSelection(from element: AXUIElement) -> String? {
    // Method 1: Direct selected text attribute (most reliable for accessible apps)
    var selectedTextRef: CFTypeRef?
    if
        AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        ) == .success,
        let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
        return selectedText
    }

    // Method 2: Try selected text range (more detailed but sometimes unreliable)
    var selectedRangeRef: CFTypeRef?
    if
        AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeRef
        ) == .success,
        let axValue = selectedRangeRef,
        CFGetTypeID(axValue) == AXValueGetTypeID() {
        var range = CFRange()
        if AXValueGetValue(axValue as! AXValue, .cfRange, &range), range.length > 0 {
            // Get the selected text using the range
            var textRef: CFTypeRef?
            if
                let axRange = AXValueCreate(.cfRange, &range),
                AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXStringForRangeParameterizedAttribute as CFString,
                    axRange,
                    &textRef
                ) == .success,
                let text = textRef as? String, !text.isEmpty {
                return text
            }
        }
    }

    return nil
}

private func getTextFieldContext(from element: AXUIElement) -> String? {
    // For accessible apps, try to get the current content of text fields
    // This works well for Terminal, TextEdit, native macOS apps, etc.
    var valueRef: CFTypeRef?
    if
        AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        ) ==
        .success,
        let fullText = valueRef as? String, !fullText.isEmpty {
        // For short text (< 100 chars), return the full content
        if fullText.count <= 100 {
            return fullText
        }

        // For longer text, try to find a reasonable context around cursor position
        var insertionPointRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                element,
                kAXInsertionPointLineNumberAttribute as CFString,
                &insertionPointRef
            ) == .success,
            let insertionPoint = insertionPointRef as? Int {
            // Get some context around the cursor position
            let lines = fullText.components(separatedBy: .newlines)
            if insertionPoint < lines.count {
                let contextLines = max(0, insertionPoint - 2) ... min(
                    lines.count - 1,
                    insertionPoint + 2
                )
                let contextText = Array(lines[contextLines]).joined(separator: "\n")
                return contextText.isEmpty ? fullText : contextText
            }
        }

        // Fallback: return first 200 characters for long text
        return String(fullText.prefix(200))
    }

    return nil
}

@inline(__always)
private func textLength(_ elem: AXUIElement) -> Int? {
    var v: CFTypeRef?
    if
        AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &v) ==
        .success,
        let s = v as? String { return s.count }
    return nil
}

// MARK: – emit JSON --------------------------------------------------------

@inline(__always)
public func getCurrentAppInfo() -> [String: Any] {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        return [
            "name": "Unknown",
            "bundleIdentifier": "unknown",
            "processIdentifier": -1,
            "isAccessible": false,
            "isIsolated": false,
            "requiresFallback": true,
            "focusState": "unfocused",
            "executableURL": "",
            "launchDate": 0
        ]
    }

    let appElm = AXUIElementCreateApplication(app.processIdentifier)

    // Check if app has accessibility isolation
    var isoRef: CFTypeRef?
    let isIsolated = AXUIElementCopyAttributeValue(
        appElm,
        "AXIsolatedTree" as CFString,
        &isoRef
    ) == .success

    // Check if we can get focused element (indicates accessibility)
    var focusedRef: CFTypeRef?
    let isAccessible = AXUIElementCopyAttributeValue(
        appElm,
        kAXFocusedUIElementAttribute as CFString,
        &focusedRef
    ) == .success

    return [
        "name": app.localizedName ?? app.bundleIdentifier ?? "Unknown",
        "bundleIdentifier": app.bundleIdentifier ?? "unknown",
        "processIdentifier": app.processIdentifier,
        "isAccessible": isAccessible,
        "isIsolated": isIsolated,
        "requiresFallback": isIsolated || !isAccessible,
        "focusState": "focused",
        "executableURL": app.executableURL?.path ?? "",
        "launchDate": app.launchDate?.timeIntervalSince1970 ?? 0
    ]
}

@inline(__always)
public func mousePoint() -> (Int, Int) {
    let p = NSEvent.mouseLocation
    let h = NSScreen.main?.frame.height ?? 1080 // Default height fallback
    return (Int(p.x), Int(h - p.y))
}

@inline(__always)
public func emit(text: String, status: String = "success") {
    let (x, y) = mousePoint()
    let appInfo = getCurrentAppInfo()
    var obj: [String: Any] = [
        "text": text,
        "x": x,
        "y": y,
        "ts": Int(Date().timeIntervalSince1970 * 1000),
        "status": status
    ]

    // Always include app information for focus tracking
    obj["app"] = appInfo

    if
        let data = try? JSONSerialization.data(withJSONObject: obj),
        let jsonString = String(data: data, encoding: .utf8) {
        fputs(jsonString, stdout); fflush(stdout)
    }
}

@inline(__always)
public func emitStatus(
    _ status: String,
    _ message: String = "",
    appName: String? = nil
) {
    let (x, y) = mousePoint()
    let appInfo = getCurrentAppInfo()
    var obj: [String: Any] = [
        "status": status,
        "message": message,
        "x": x,
        "y": y,
        "ts": Int(Date().timeIntervalSince1970 * 1000)
    ]

    // Always include comprehensive app information
    obj["app"] = appInfo

    // Keep legacy appName for backward compatibility
    if let appName {
        obj["appName"] = appName
    }

    if
        let data = try? JSONSerialization.data(withJSONObject: obj),
        let jsonString = String(data: data, encoding: .utf8) {
        fputs(jsonString, stdout); fflush(stdout)
    }
}

// MARK: – Public API --------------------------------------------------------

public func runSelectionTap(config: DataCollectorConfig = .default) {
    let tap = SelectionTap(config: config)
    logInfo("SelectionTap launching with config: \(getConfigDescription(config))")
    tap.run()
    RunLoop.current.run()
}

public func runSelectionTapComprehensive() {
    runSelectionTap(config: .comprehensive)
}

private func getConfigDescription(_ config: DataCollectorConfig) -> String {
    var enabled: [String] = []
    if config.textSelection { enabled.append("text") }
    if config.focusTracking { enabled.append("focus") }
    if config.windowContext { enabled.append("window") }
    if config.browserData { enabled.append("browser") }
    if config.systemMetrics { enabled.append("system") }
    if config.inputPatterns { enabled.append("input") }
    if config.timeContext { enabled.append("time") }
    return enabled.joined(separator: ", ")
}
