// SelectionTapRefactored.swift – Clean Activity Tracker
// -------------------------------------------------------------
// Streamlined activity tracking system using the message bus
// architecture for clean separation of concerns and events.
// -------------------------------------------------------------

import ApplicationServices
import Cocoa  
import Foundation
import Quartz

// MARK: – Logging

enum LogLevel: Int {
    case error = 0
    case warn = 1
    case info = 2
    case debug = 3
}

private let currentLogLevel: LogLevel = .debug

@inline(__always)
private func shouldLog(level: LogLevel) -> Bool {
    level.rawValue <= currentLogLevel.rawValue
}

@inline(__always)
func logError(_ msg: @autoclosure () -> String) {
    if shouldLog(level: .error) {
        let ts = ISO8601DateFormatter().string(from: .init())
        fputs("[ActivityTracker][ERROR] \(ts) \(msg())\n", stderr)
    }
}

@inline(__always)
func logWarn(_ msg: @autoclosure () -> String) {
    if shouldLog(level: .warn) {
        let ts = ISO8601DateFormatter().string(from: .init())
        fputs("[ActivityTracker][WARN] \(ts) \(msg())\n", stderr)
    }
}

@inline(__always)
func logInfo(_ msg: @autoclosure () -> String) {
    if shouldLog(level: .info) {
        let ts = ISO8601DateFormatter().string(from: .init())
        fputs("[ActivityTracker][INFO] \(ts) \(msg())\n", stderr)
    }
}

@inline(__always)
func logDebug(_ msg: @autoclosure () -> String) {
    if shouldLog(level: .debug) {
        let ts = ISO8601DateFormatter().string(from: .init())
        fputs("[ActivityTracker][DEBUG] \(ts) \(msg())\n", stderr)
    }
}

// MARK: – Configuration

public struct ActivityTrackerConfig {
    public let enableTextSelection: Bool
    public let enableFocusTracking: Bool  
    public let enableWindowTracking: Bool
    public let enableBrowserTracking: Bool
    public let enableSystemMetrics: Bool
    public let enableUserActivity: Bool
    public let pollInterval: TimeInterval
    public let textCheckInterval: TimeInterval
    
    public init(enableTextSelection: Bool = true, enableFocusTracking: Bool = true,
                enableWindowTracking: Bool = false, enableBrowserTracking: Bool = false,
                enableSystemMetrics: Bool = false, enableUserActivity: Bool = false,
                pollInterval: TimeInterval = 1.0, textCheckInterval: TimeInterval = 0.2) {
        self.enableTextSelection = enableTextSelection
        self.enableFocusTracking = enableFocusTracking
        self.enableWindowTracking = enableWindowTracking
        self.enableBrowserTracking = enableBrowserTracking
        self.enableSystemMetrics = enableSystemMetrics
        self.enableUserActivity = enableUserActivity
        self.pollInterval = pollInterval
        self.textCheckInterval = textCheckInterval
    }
    
    public static let `default` = ActivityTrackerConfig()
    public static let comprehensive = ActivityTrackerConfig(
        enableTextSelection: true, enableFocusTracking: true,
        enableWindowTracking: true, enableBrowserTracking: true,
        enableSystemMetrics: true, enableUserActivity: true
    )
}

// MARK: – Main Activity Tracker

public class ActivityTracker {
    private let config: ActivityTrackerConfig
    private let messageBus: MessageBus
    private var pollTimer: Timer?
    private var textTimer: Timer?
    
    // Event generators
    private let focusTracker: FocusTracker
    private let textTracker: TextTracker
    private let windowTracker: WindowTracker?
    private let browserTracker: BrowserTracker?
    private let systemTracker: SystemTracker?
    private let activityTracker: UserActivityTracker?
    
    public init(config: ActivityTrackerConfig = .default) {
        self.config = config
        self.messageBus = MessageBusFactory.createStandardBus()
        
        // Initialize event generators based on configuration
        self.focusTracker = FocusTracker()
        self.textTracker = TextTracker()
        self.windowTracker = config.enableWindowTracking ? WindowTracker() : nil
        self.browserTracker = config.enableBrowserTracking ? BrowserTracker() : nil
        self.systemTracker = config.enableSystemMetrics ? SystemTracker() : nil
        self.activityTracker = config.enableUserActivity ? UserActivityTracker() : nil
    }
    
    public func start() throws {
        // Check accessibility permissions
        let options: [String: Any] = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
        ]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            throw ActivityTrackerError.accessibilityNotGranted
        }
        
        logInfo("ActivityTracker starting with configuration: \(configDescription())")
        
        // Start main polling timer
        pollTimer = Timer.scheduledTimer(withTimeInterval: config.pollInterval, repeats: true) { [weak self] _ in
            self?.pollAndEmitEvents()
        }
        
        // Start text selection timer if enabled
        if config.enableTextSelection {
            textTimer = Timer.scheduledTimer(withTimeInterval: config.textCheckInterval, repeats: true) { [weak self] _ in
                self?.checkTextSelection()
            }
        }
        
        // Emit initial events
        pollAndEmitEvents()
    }
    
    public func stop() {
        pollTimer?.invalidate()
        textTimer?.invalidate()
        pollTimer = nil
        textTimer = nil
        logInfo("ActivityTracker stopped")
    }
    
    // MARK: - Event Collection
    
    private func pollAndEmitEvents() {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let mousePos = getMousePosition()
        
        // Check focus changes
        if config.enableFocusTracking {
            if let focusEvent = focusTracker.checkForEvents(timestamp: timestamp, mousePosition: mousePos) {
                messageBus.emit(focusEvent)
            }
        }
        
        // Check window updates
        if let windowTracker = windowTracker {
            if let windowEvent = windowTracker.checkForEvents(timestamp: timestamp, mousePosition: mousePos) {
                messageBus.emit(windowEvent)
            }
        }
        
        // Check browser navigation
        if let browserTracker = browserTracker {
            if let browserEvent = browserTracker.checkForEvents(timestamp: timestamp, mousePosition: mousePos) {
                messageBus.emit(browserEvent)
            }
        }
        
        // Collect system metrics
        if let systemTracker = systemTracker {
            if let systemEvent = systemTracker.checkForEvents(timestamp: timestamp, mousePosition: mousePos) {
                messageBus.emit(systemEvent)
            }
        }
        
        // Check user activity
        if let activityTracker = activityTracker {
            if let activityEvent = activityTracker.checkForEvents(timestamp: timestamp, mousePosition: mousePos) {
                messageBus.emit(activityEvent)
            }
        }
        
        // Emit heartbeat
        if let heartbeatEvent = focusTracker.createHeartbeat(timestamp: timestamp, mousePosition: mousePos) {
            messageBus.emit(heartbeatEvent)
        }
    }
    
    private func checkTextSelection() {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let mousePos = getMousePosition()
        
        if let textEvent = textTracker.checkForEvents(timestamp: timestamp, mousePosition: mousePos) {
            messageBus.emit(textEvent)
        }
    }
    
    private func configDescription() -> String {
        var features: [String] = []
        if config.enableTextSelection { features.append("text") }
        if config.enableFocusTracking { features.append("focus") }
        if config.enableWindowTracking { features.append("window") }
        if config.enableBrowserTracking { features.append("browser") }
        if config.enableSystemMetrics { features.append("system") }
        if config.enableUserActivity { features.append("activity") }
        return features.joined(separator: ", ")
    }
}

// MARK: – Event Tracker Protocols

protocol EventTracker {
    func checkForEvents(timestamp: Int64, mousePosition: (x: Int, y: Int)) -> ActivityEvent?
}

// MARK: – Focus Tracker

class FocusTracker: EventTracker {
    private var lastAppInfo: AppInfo?
    private var lastFocusChange: Date = Date()
    private var sessionStartTime: Date = Date()
    
    func checkForEvents(timestamp: Int64, mousePosition: (x: Int, y: Int)) -> ActivityEvent? {
        let currentAppInfo = getCurrentAppInfoStructured()
        
        // Check if focus changed
        if let lastApp = lastAppInfo {
            if !areAppsEqual(lastApp, currentAppInfo) {
                let focusDuration = Date().timeIntervalSince(lastFocusChange)
                lastFocusChange = Date()
                
                let event = FocusChangeEvent(
                    timestamp: timestamp,
                    mousePosition: mousePosition,
                    currentApp: currentAppInfo,
                    previousApp: lastApp,
                    focusDuration: focusDuration,
                    sessionId: generateSessionId()
                )
                
                lastAppInfo = currentAppInfo
                return event
            }
        } else {
            // First run
            lastAppInfo = currentAppInfo
            lastFocusChange = Date()
        }
        
        return nil
    }
    
    func createHeartbeat(timestamp: Int64, mousePosition: (x: Int, y: Int)) -> HeartbeatEvent? {
        guard let currentApp = lastAppInfo else { return nil }
        
        let sessionDuration = Date().timeIntervalSince(sessionStartTime)
        let focusDuration = Date().timeIntervalSince(lastFocusChange)
        
        // Only emit heartbeat every 30 seconds
        if Int(focusDuration) % 30 == 0 && Int(focusDuration) > 0 {
            return HeartbeatEvent(
                timestamp: timestamp,
                mousePosition: mousePosition,
                app: currentApp,
                sessionDuration: sessionDuration,
                activeSessions: [currentApp.bundleIdentifier: focusDuration],
                totalActiveTime: sessionDuration
            )
        }
        
        return nil
    }
    
    private func areAppsEqual(_ app1: AppInfo, _ app2: AppInfo) -> Bool {
        return app1.bundleIdentifier == app2.bundleIdentifier && 
               app1.processIdentifier == app2.processIdentifier
    }
    
    private func generateSessionId() -> String {
        return UUID().uuidString.prefix(8).lowercased()
    }
}

// MARK: – Text Tracker

class TextTracker: EventTracker {
    private var lastText: String = ""
    private var lastApp: String = ""
    
    func checkForEvents(timestamp: Int64, mousePosition: (x: Int, y: Int)) -> ActivityEvent? {
        let currentApp = getCurrentAppInfoStructured()
        
        // Skip if app requires fallback
        if currentApp.requiresFallback {
            return nil
        }
        
        // Get current text selection
        if let text = extractCurrentText(from: currentApp) {
            // Check if text or app changed
            if text != lastText || currentApp.bundleIdentifier != lastApp {
                lastText = text
                lastApp = currentApp.bundleIdentifier
                
                return TextSelectionEvent(
                    timestamp: timestamp,
                    mousePosition: mousePosition,
                    app: currentApp,
                    text: text,
                    selectionLength: text.count,
                    source: "accessibility",
                    context: nil
                )
            }
        } else {
            // Clear if no text
            lastText = ""
        }
        
        return nil
    }
    
    private func extractCurrentText(from app: AppInfo) -> String? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // Try to get focused element and extract text
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focusedElement = focusedRef,
           CFGetTypeID(focusedElement) == AXUIElementGetTypeID() {
            let axElement = focusedElement as! AXUIElement
            
            // Try selected text first
            var selectedTextRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
               let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
                return selectedText
            }
            
            // Try value attribute
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef) == .success,
               let value = valueRef as? String, !value.isEmpty {
                return value.count > 200 ? String(value.prefix(200)) : value
            }
        }
        
        return nil
    }
}

// MARK: – Window Tracker

class WindowTracker: EventTracker {
    private var lastWindowTitle: String = ""
    private var lastWindowPosition: (x: Double, y: Double) = (0, 0)
    
    func checkForEvents(timestamp: Int64, mousePosition: (x: Int, y: Int)) -> ActivityEvent? {
        let currentApp = getCurrentAppInfoStructured()
        let appElement = AXUIElementCreateApplication(currentApp.processIdentifier)
        
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let window = windowRef,
           CFGetTypeID(window) == AXUIElementGetTypeID() {
            let axWindow = window as! AXUIElement
            
            // Get window title
            var titleRef: CFTypeRef?
            let windowTitle = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success ?
                (titleRef as? String ?? "Untitled") : "Untitled"
            
            // Get window position
            var positionRef: CFTypeRef?
            var windowPosition: (x: Double, y: Double) = (0, 0)
            if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
               let position = positionRef {
                var point = CGPoint.zero
                if AXValueGetValue(position as! AXValue, .cgPoint, &point) {
                    windowPosition = (point.x, point.y)
                }
            }
            
            // Check if window changed
            if windowTitle != lastWindowTitle || 
               abs(windowPosition.x - lastWindowPosition.x) > 10 ||
               abs(windowPosition.y - lastWindowPosition.y) > 10 {
                
                lastWindowTitle = windowTitle
                lastWindowPosition = windowPosition
                
                // Get window size
                var sizeRef: CFTypeRef?
                var windowSize: (width: Double, height: Double) = (0, 0)
                if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
                   let size = sizeRef {
                    var cgSize = CGSize.zero
                    if AXValueGetValue(size as! AXValue, .cgSize, &cgSize) {
                        windowSize = (cgSize.width, cgSize.height)
                    }
                }
                
                return WindowUpdateEvent(
                    timestamp: timestamp,
                    mousePosition: mousePosition,
                    app: currentApp,
                    windowTitle: windowTitle,
                    windowPosition: windowPosition,
                    windowSize: windowSize,
                    isMainWindow: true
                )
            }
        }
        
        return nil
    }
}

// MARK: – Browser Tracker

class BrowserTracker: EventTracker {
    private var lastURL: String = ""
    private var lastPageTitle: String = ""
    private var lastAppBundleId: String = ""
    private var browserCapabilityCache: [String: BrowserCapabilities] = [:]
    
    private struct BrowserCapabilities {
        let hasURLSupport: Bool
        let hasTitleSupport: Bool
        let hasTabSupport: Bool
        let urlAttribute: String?
        let titleAttribute: String?
        let tabsAttribute: String?
        let lastChecked: Date
        
        var isExpired: Bool {
            Date().timeIntervalSince(lastChecked) > 300 // 5 minutes
        }
    }
    
    func checkForEvents(timestamp: Int64,
                        mousePosition: (x: Int, y: Int)) -> ActivityEvent? {

        let currentApp = getCurrentAppInfoStructured()
        let capabilities = getBrowserCapabilities(for: currentApp)
        guard capabilities.hasURLSupport || capabilities.hasTitleSupport else { return nil }

        // Focused window
        let appElement = AXUIElementCreateApplication(currentApp.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement,
                                            kAXFocusedWindowAttribute as CFString,
                                            &windowRef) == .success,
            let window = windowRef,
            CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        let axWindow = window as! AXUIElement

        var hasChanges   = false
        var currentURL   = ""
        var currentTitle = ""
        var tabCount: Int?

        // 1) URL/TITLE from AXWebArea (works for Chrome, Safari, Arc …)
        if let webArea = firstDescendant(element: axWindow, role: "AXWebArea") {

            for attr in [kAXURLAttribute, kAXDocumentAttribute] {
                var ref: CFTypeRef?
                if AXUIElementCopyAttributeValue(webArea, attr as CFString, &ref) == .success {
                    
                    // String case
                    if let s = ref as? String, !s.isEmpty { currentURL = s; break }
                    
                    // CFURL case
                    if CFGetTypeID(ref) == CFURLGetTypeID() {
                        let cfURL = ref as! CFURL
                        let s = CFURLGetString(cfURL) as String
                        if !s.isEmpty { currentURL = s; break }
                    }
                }
            }

            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(webArea,
                                            kAXTitleAttribute as CFString,
                                            &titleRef) == .success,
            let t = titleRef as? String, !t.isEmpty {
                currentTitle = t
            }
        }

        // 2) Chrome-only tab fallback (only if URL still empty)
        if currentURL.isEmpty,
        let tabsAttr = capabilities.tabsAttribute {
            var tabsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow,
                                            tabsAttr as CFString,
                                            &tabsRef) == .success,
            let tabs = tabsRef as? [AXUIElement], !tabs.isEmpty {

                tabCount = tabs.count
                currentURL = extractChromeURL(from: tabs[0], appName: currentApp.name)

                if currentTitle.isEmpty {
                    var ref: CFTypeRef?
                    if AXUIElementCopyAttributeValue(tabs[0],
                                                    kAXTitleAttribute as CFString,
                                                    &ref) == .success,
                    let t = ref as? String, !t.isEmpty {
                        currentTitle = t
                    }
                }
            }
        }

        // 3) Change detection
        let focusChanged = currentApp.bundleIdentifier != lastAppBundleId
        if focusChanged || currentURL != lastURL || currentTitle != lastPageTitle {
            hasChanges = true
        }
        guard hasChanges else { return nil }

        // Persist state
        lastURL         = currentURL
        lastPageTitle   = currentTitle
        lastAppBundleId = currentApp.bundleIdentifier

        let domain = URL(string: currentURL)?.host ?? "unknown"

        return BrowserNavigationEvent(
            timestamp:   timestamp,
            mousePosition: mousePosition,
            app:         currentApp,
            currentURL:  currentURL,
            domain:      domain,
            tabCount:    tabCount,
            pageTitle:   currentTitle.isEmpty ? nil : currentTitle
        )
    }

    // Helper: depth-first search for the first element of a given AXRole
    private func firstDescendant(element: AXUIElement,
                                role wanted: String,
                                depth: Int = 0,
                                maxDepth: Int = 6) -> AXUIElement? {
        guard depth < maxDepth else { return nil }
        
        var kidsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element,
                                        kAXChildrenAttribute as CFString,
                                        &kidsRef) == .success,
        let kids = kidsRef as? [AXUIElement] {
            for kid in kids {
                var roleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(kid,
                                                kAXRoleAttribute as CFString,
                                                &roleRef) == .success,
                let role = roleRef as? String, role == wanted {
                    return kid
                }
                if let found = firstDescendant(element: kid,
                                            role: wanted,
                                            depth: depth + 1,
                                            maxDepth: maxDepth) {
                    return found
                }
            }
        }
        return nil
    }
    
    // Chrome URL extraction: AXURL is stored directly on the first tab element
    private func extractChromeURL(from firstTab: AXUIElement, appName: String) -> String {
        let urlAttributes = ["AXURL", "AXDescription", "AXHelp", "AXValue"]
        
        for urlAttr in urlAttributes {
            var tabURLRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(firstTab, urlAttr as CFString, &tabURLRef)
            if result == .success {
                if let tabURL = tabURLRef as? String {
                    if !tabURL.isEmpty && (tabURL.hasPrefix("http://") || tabURL.hasPrefix("https://") || tabURL.contains("://")) {
                        logDebug("Chrome URL from \(urlAttr): '\(tabURL.prefix(50))'")
                        return tabURL
                    }
                } else if let nsurl = tabURLRef as? NSURL, let urlString = nsurl.absoluteString {
                    if !urlString.isEmpty && (urlString.hasPrefix("http://") || urlString.hasPrefix("https://") || urlString.contains("://")) {
                        logDebug("Chrome URL from \(urlAttr) (NSURL): '\(urlString.prefix(50))'")
                        return urlString
                    }
                } else if CFGetTypeID(tabURLRef) == CFURLGetTypeID() {
                    let cfurl = tabURLRef as! CFURL
                    if let urlString = CFURLGetString(cfurl) as String? {
                        if !urlString.isEmpty && (urlString.hasPrefix("http://") || urlString.hasPrefix("https://") || urlString.contains("://")) {
                            logDebug("Chrome URL from \(urlAttr) (CFURL): '\(urlString.prefix(50))'")
                            return urlString
                        }
                    }
                }
            }
        }
        return ""
    }
    
    // Safari URL extraction: AXURL is stored on AXWebArea or AXDocument elements within the window
    private func extractSafariURL(from window: AXUIElement, appName: String) -> String {
        // Try AXWebArea first (most common in Safari)
        if let webArea = firstDescendant(element: window, role: "AXWebArea") {
            if let url = extractURLFromElement(webArea, elementType: "AXWebArea", appName: appName) {
                return url
            }
        }
        
        // Try AXDocument as fallback (some Safari builds)
        if let document = firstDescendant(element: window, role: "AXDocument") {
            if let url = extractURLFromElement(document, elementType: "AXDocument", appName: appName) {
                return url
            }
        }
        
        logDebug("No Safari URL found in AXWebArea or AXDocument for \(appName)")
        return ""
    }
    
    // Extract URL from a specific accessibility element
    private func extractURLFromElement(_ element: AXUIElement, elementType: String, appName: String) -> String? {
        let urlAttributes = ["AXURL", "AXDescription", "AXHelp", "AXValue"]
        
        for urlAttr in urlAttributes {
            var urlRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, urlAttr as CFString, &urlRef)
            if result == .success {
                if let urlString = urlRef as? String {
                    if !urlString.isEmpty && (urlString.hasPrefix("http://") || urlString.hasPrefix("https://") || urlString.contains("://")) {
                        logDebug("Safari URL from \(elementType).\(urlAttr): '\(urlString.prefix(50))'")
                        return urlString
                    }
                } else if let nsurl = urlRef as? NSURL, let urlString = nsurl.absoluteString {
                    if !urlString.isEmpty && (urlString.hasPrefix("http://") || urlString.hasPrefix("https://") || urlString.contains("://")) {
                        logDebug("Safari URL from \(elementType).\(urlAttr) (NSURL): '\(urlString.prefix(50))'")
                        return urlString
                    }
                } else if CFGetTypeID(urlRef) == CFURLGetTypeID() {
                    let cfurl = urlRef as! CFURL
                    if let urlString = CFURLGetString(cfurl) as String? {
                        if !urlString.isEmpty && (urlString.hasPrefix("http://") || urlString.hasPrefix("https://") || urlString.contains("://")) {
                            logDebug("Safari URL from \(elementType).\(urlAttr) (CFURL): '\(urlString.prefix(50))'")
                            return urlString
                        }
                    }
                }
            }
        }
        return nil
    }
    
    private func getBrowserCapabilities(for app: AppInfo) -> BrowserCapabilities {
        let bundleId = app.bundleIdentifier
        
        // Return cached capabilities if fresh
        if let cached = browserCapabilityCache[bundleId], !cached.isExpired {
            return cached
        }
        
        // Detect browser capabilities dynamically
        let capabilities = detectBrowserCapabilities(for: app)
        browserCapabilityCache[bundleId] = capabilities
        
        return capabilities
    }
    
    private func detectBrowserCapabilities(for app: AppInfo) -> BrowserCapabilities {
        logDebug("Detecting browser capabilities for: \(app.name) (\(app.bundleIdentifier))")
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // Get focused window for testing
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef,
              CFGetTypeID(window) == AXUIElementGetTypeID() else {
            logDebug("No focused window found for \(app.name), skipping browser detection")
            return BrowserCapabilities(
                hasURLSupport: false, hasTitleSupport: false, hasTabSupport: false,
                urlAttribute: nil, titleAttribute: nil, tabsAttribute: nil,
                lastChecked: Date()
            )
        }
        
        let axWindow = window as! AXUIElement
        
        // Test different URL attributes browsers might use
        let urlAttributes = ["AXURL", "AXDescription", "AXHelp", "AXValue", "AXTitle"]
        var urlAttribute: String? = nil
        
        for attr in urlAttributes {
            var testRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, attr as CFString, &testRef) == .success,
               let value = testRef as? String,
               !value.isEmpty {
                logDebug("Testing \(attr) for \(app.name): '\(value.prefix(100))'")
                if (value.hasPrefix("http://") || value.hasPrefix("https://") || value.contains("://")) {
                    urlAttribute = attr
                    logDebug("Found URL attribute \(attr) for \(app.name)")
                    break
                }
            }
        }
        
        // If no URL found in window, try to find address bar in children
        if urlAttribute == nil {
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                logDebug("Searching \(children.count) child elements for URL info in \(app.name)")
                
                for child in children.prefix(8) { // Limit search to first 8 children
                    for attr in ["AXURL", "AXValue", "AXDescription"] {
                        var testRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(child, attr as CFString, &testRef) == .success,
                           let value = testRef as? String,
                           !value.isEmpty,
                           (value.hasPrefix("http://") || value.hasPrefix("https://") || value.contains("://")) {
                            urlAttribute = attr
                            logDebug("Found URL in child element using \(attr): '\(value.prefix(50))'")
                            break
                        }
                    }
                    if urlAttribute != nil { break }
                }
            }
        }
        
        // Test title attributes - use window title as fallback
        let titleAttributes = ["AXTitle", "AXDescription"]
        var titleAttribute: String? = nil
        
        for attr in titleAttributes {
            var testRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, attr as CFString, &testRef) == .success,
               let value = testRef as? String,
               !value.isEmpty {
                titleAttribute = attr
                break
            }
        }
        
        // Test for tab support
        let tabAttributes = ["AXTabs", "AXChildren"]
        var tabsAttribute: String? = nil
        
        for attr in tabAttributes {
            var testRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, attr as CFString, &testRef) == .success,
               let tabs = testRef as? [Any],
               tabs.count > 0 {
                tabsAttribute = attr
                break
            }
        }
        
        // Chrome hack: Even if window doesn't have URL, tabs might have AXURL
        let effectiveURLSupport = urlAttribute != nil || tabsAttribute != nil
        
        logDebug("Browser capabilities for \(app.name): URL=\(urlAttribute ?? "none"), Title=\(titleAttribute ?? "none"), Tabs=\(tabsAttribute ?? "none"), EffectiveURL=\(effectiveURLSupport)")
        
        return BrowserCapabilities(
            hasURLSupport: effectiveURLSupport,
            hasTitleSupport: titleAttribute != nil,
            hasTabSupport: tabsAttribute != nil,
            urlAttribute: urlAttribute,
            titleAttribute: titleAttribute,
            tabsAttribute: tabsAttribute,
            lastChecked: Date()
        )
    }
}

// MARK: – System Tracker

class SystemTracker: EventTracker {
    private var lastEmission: Date = Date.distantPast
    
    func checkForEvents(timestamp: Int64, mousePosition: (x: Int, y: Int)) -> ActivityEvent? {
        // Only emit system metrics every 30 seconds
        let now = Date()
        if now.timeIntervalSince(lastEmission) < 30 {
            return nil
        }
        
        lastEmission = now
        
        var screenSize: (width: Double, height: Double) = (1920, 1080)
        var screenScale: Double = 1.0
        
        if let screen = NSScreen.main {
            screenSize = (screen.frame.width, screen.frame.height)
            screenScale = screen.backingScaleFactor
        }
        
        return SystemMetricsEvent(
            timestamp: timestamp,
            mousePosition: mousePosition,
            batteryLevel: nil, // TODO: Implement battery monitoring
            isCharging: nil,
            screenSize: screenSize,
            screenScale: screenScale,
            memoryPressure: nil
        )
    }
}

// MARK: – User Activity Tracker

class UserActivityTracker: EventTracker {
    private var lastActivity: Date = Date()
    
    func checkForEvents(timestamp: Int64, mousePosition: (x: Int, y: Int)) -> ActivityEvent? {
        let now = Date()
        let timeSinceLastActivity = now.timeIntervalSince(lastActivity)
        
        // Only emit activity events periodically
        if timeSinceLastActivity < 10 {
            return nil
        }
        
        lastActivity = now
        
        let currentApp = getCurrentAppInfoStructured()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        
        let timeOfDay: String
        switch hour {
        case 5..<12: timeOfDay = "morning"
        case 12..<17: timeOfDay = "afternoon"  
        case 17..<21: timeOfDay = "evening"
        default: timeOfDay = "night"
        }
        
        return UserActivityEvent(
            timestamp: timestamp,
            mousePosition: mousePosition,
            app: currentApp,
            activityType: "general",
            intensity: 0.5,
            duration: timeSinceLastActivity,
            timeOfDay: timeOfDay,
            isWeekend: calendar.isDateInWeekend(now)
        )
    }
}

// MARK: – Utilities

private func getMousePosition() -> (x: Int, y: Int) {
    let point = NSEvent.mouseLocation
    let height = NSScreen.main?.frame.height ?? 1080
    return (Int(point.x), Int(height - point.y))
}

private func getCurrentAppInfoStructured() -> AppInfo {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        return AppInfo(
            name: "Unknown", bundleIdentifier: "unknown", processIdentifier: -1,
            isAccessible: false, requiresFallback: true,
            focusState: "unfocused", executableURL: "", launchDate: 0
        )
    }
    
    // Grab the app element
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    
    // Try fetching windows
    var windowsRef: CFTypeRef?
    let windowsOK = AXUIElementCopyAttributeValue(
        appElement,
        kAXWindowsAttribute as CFString,
        &windowsRef
    ) == .success
    
    let windows = (windowsRef as? [Any]) ?? []
    let hasTree = windowsOK && !windows.isEmpty
    
    // If it has a tree, test focus access
    let canAccessFocus: Bool = {
        guard hasTree else { return false }
        var focusedRef: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success
    }()
    
    let requiresFallback = !hasTree || !canAccessFocus
    
    return AppInfo(
        name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
        bundleIdentifier: app.bundleIdentifier ?? "unknown",
        processIdentifier: app.processIdentifier,
        isAccessible: hasTree && canAccessFocus,
        requiresFallback: requiresFallback,
        focusState: "focused",
        executableURL: app.executableURL?.path ?? "",
        launchDate: app.launchDate?.timeIntervalSince1970 ?? 0
    )
}

// MARK: – Errors

public enum ActivityTrackerError: Error {
    case accessibilityNotGranted
}

// MARK: – Public API

public func runActivityTracker(config: ActivityTrackerConfig = .default) {
    let tracker = ActivityTracker(config: config)
    
    do {
        try tracker.start()
        logInfo("ActivityTracker started successfully")
        RunLoop.current.run()
    } catch {
        logError("Failed to start ActivityTracker: \(error)")
        exit(1)
    }
}

public func runActivityTrackerComprehensive() {
    runActivityTracker(config: .comprehensive)
}