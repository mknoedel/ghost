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

private let currentLogLevel: LogLevel = .info

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
    public let enableBrowserTracking: Bool
    public let textCheckInterval: TimeInterval

    public init(
        enableTextSelection: Bool = true,
        enableFocusTracking: Bool = true,
        enableBrowserTracking: Bool = true,
        textCheckInterval: TimeInterval = 0.2
    ) {
        self.enableTextSelection = enableTextSelection
        self.enableFocusTracking = enableFocusTracking
        self.enableBrowserTracking = enableBrowserTracking
        self.textCheckInterval = textCheckInterval
    }

    public static let `default` = ActivityTrackerConfig()
    public static let comprehensive = ActivityTrackerConfig(
        enableTextSelection: true,
        enableFocusTracking: true,
        enableBrowserTracking: true
    )
}

// MARK: – Main Activity Tracker

public class ActivityTracker {
    private let config: ActivityTrackerConfig
    private let messageBus: MessageBus

    // Event generators (core only)
    private let focusTracker: FocusTracker
    private let textTracker: TextTracker
    private let browserTracker: BrowserTracker?

    public init(config: ActivityTrackerConfig = .default) {
        self.config = config
        messageBus = MessageBusFactory.createStandardBus()

        // Initialize core event generators
        focusTracker = FocusTracker()
        textTracker = TextTracker()
        browserTracker = config.enableBrowserTracking ? BrowserTracker() : nil

        
        // Wire up tracker event handlers for AXObserver notifications
        textTracker.eventHandler = { [weak self] event in
            self?.messageBus.emit(event)
        }
        
        browserTracker?.eventHandler = { [weak self] event in
            self?.messageBus.emit(event)
        }
    }

    public func start() throws {
        // Check accessibility permissions
        let options: [String: Any] = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
        ]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            throw ActivityTrackerError.accessibilityNotGranted
        }

        logInfo("ActivityTracker starting with event-driven architecture using AXObserver")

        // Start AXObserver-based tracking (primary drivers)
        if config.enableTextSelection {
            textTracker.startObserving()
        }
        
        if config.enableBrowserTracking {
            browserTracker?.startObserving()
        }

        // Start focus monitoring (secondary driver)
        startFocusMonitoring()

        // Emit initial events
        checkInitialState()
    }

    public func stop() {
        textTracker.stopObserving()
        browserTracker?.stopObserving()
        stopFocusMonitoring()
        logInfo("ActivityTracker stopped")
    }

    // MARK: - Event-Driven Architecture

    private func startFocusMonitoring() {
        // Monitor focus changes using NSWorkspace notifications for efficiency
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    private func stopFocusMonitoring() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc
    private func handleFocusChange(_ notification: Notification) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let mousePos = getMousePosition()

        // Check focus changes immediately when app switches
        if config.enableFocusTracking {
            if
                let focusEvent = focusTracker.checkForEvents(
                    timestamp: timestamp,
                    mousePosition: mousePos
                ) {
                messageBus.emit(focusEvent)

                // Update trackers for new app (will recreate AXObservers if needed)
                if let focusChangeEvent = focusEvent as? FocusChangeEvent {
                    textTracker.updateForAppChange(focusChangeEvent.currentApp)
                    browserTracker?.updateForAppChange(focusChangeEvent.currentApp)
                }
            }
        }
    }


    private func configDescription() -> String {
        var features: [String] = []
        if config.enableTextSelection { features.append("text") }
        if config.enableFocusTracking { features.append("focus") }
        if config.enableBrowserTracking { features.append("browser") }
        return features.joined(separator: ", ")
    }

    // MARK: - Helper Methods

    private func checkInitialState() {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let mousePos = getMousePosition()

        // Check initial focus state
        if config.enableFocusTracking {
            if
                let focusEvent = focusTracker.checkForEvents(
                    timestamp: timestamp,
                    mousePosition: mousePos
                ) {
                messageBus.emit(focusEvent)
            }
        }

        // Emit initial heartbeat
        if
            let heartbeatEvent = focusTracker.createHeartbeat(
                timestamp: timestamp,
                mousePosition: mousePos
            ) {
            messageBus.emit(heartbeatEvent)
        }
    }

    private func isBrowserApp(_ app: AppInfo) -> Bool {
        // Use the BrowserTracker's dynamic detection instead of hardcoded list
        guard let browserTracker else { return false }
        return browserTracker.hasBrowserCapabilities(app: app)
    }

    private func getCurrentApp() -> AppInfo? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        return AppInfo(
            name: frontmostApp.localizedName ?? "Unknown",
            bundleIdentifier: frontmostApp.bundleIdentifier ?? "unknown",
            processIdentifier: frontmostApp.processIdentifier,
            isAccessible: true,
            requiresFallback: false,
            focusState: "active",
            executableURL: frontmostApp.executableURL?.path ?? "",
            launchDate: 0,
            windowTitle: nil,  // Use getCurrentAppInfoStructured() for full context
            focusedElementInfo: nil
        )
    }
}

// MARK: – Event Tracker Protocols

protocol EventTracker {
    func checkForEvents(timestamp: Int64, mousePosition: (x: Int, y: Int))
        -> ActivityEvent?
}

// MARK: – Focus Tracker

class FocusTracker: EventTracker {
    private var lastAppInfo: AppInfo?
    private var lastFocusChange: Date = .init()
    private var sessionStartTime: Date = .init()

    func checkForEvents(
        timestamp: Int64,
        mousePosition: (x: Int, y: Int)
    )
        -> ActivityEvent? {
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
        }
        else {
            // First run
            lastAppInfo = currentAppInfo
            lastFocusChange = Date()
        }

        return nil
    }

    func createHeartbeat(
        timestamp: Int64,
        mousePosition: (x: Int, y: Int)
    )
        -> HeartbeatEvent? {
        guard let currentApp = lastAppInfo else { return nil }

        let sessionDuration = Date().timeIntervalSince(sessionStartTime)
        let focusDuration = Date().timeIntervalSince(lastFocusChange)

        // Only emit heartbeat every 30 seconds
        if Int(focusDuration) % 30 == 0, Int(focusDuration) > 0 {
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
        app1.bundleIdentifier == app2.bundleIdentifier &&
            app1.processIdentifier == app2.processIdentifier
    }

    private func generateSessionId() -> String {
        UUID().uuidString.prefix(8).lowercased()
    }
}

// MARK: – Text Tracker

class TextTracker: EventTracker {
    private var lastText: String = ""
    private var lastApp: String = ""
    private var axObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var observedApp: pid_t = -1
    
    var eventHandler: ((ActivityEvent) -> Void)?
    
    deinit {
        stopObserving()
    }
    
    func startObserving() {
        stopObserving() // Clean up any existing observer
        
        let currentApp = getCurrentAppInfoStructured()
        guard currentApp.processIdentifier != -1 else { return }
        
        setupObserverForApp(currentApp)
    }
    
    func stopObserving() {
        guard let observer = axObserver else { return }
        
        if let element = observedElement {
            // Remove all notifications we might have added
            AXObserverRemoveNotification(observer, element, kAXSelectedTextChangedNotification as CFString)
            AXObserverRemoveNotification(observer, element, kAXFocusedUIElementChangedNotification as CFString)
            AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
        }
        
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = nil
        observedElement = nil
        observedApp = -1
    }
    
    private func setupObserverForApp(_ app: AppInfo) {
        let pid = app.processIdentifier
        
        // Create observer
        var observer: AXObserver?
        let result = AXObserverCreate(pid, { (observer, element, notification, userData) in
            guard let userData = userData else { return }
            let textTracker = Unmanaged<TextTracker>.fromOpaque(userData).takeUnretainedValue()
            textTracker.handleAccessibilityNotification(element: element, notification: notification)
        }, &observer)
        
        guard result == .success, let observer = observer else {
            logDebug("Failed to create AXObserver for \(app.name): \(result)")
            return
        }
        
        self.axObserver = observer
        self.observedApp = pid
        
        // Get the application element
        let appElement = AXUIElementCreateApplication(pid)
        self.observedElement = appElement
        
        let userData = Unmanaged.passUnretained(self).toOpaque()
        
        // Strategy 1: Observe application-wide notifications
        let appNotifications = [
            kAXSelectedTextChangedNotification,
            kAXFocusedUIElementChangedNotification,
            kAXValueChangedNotification,
            kAXTitleChangedNotification  // Window title changes
        ]
        
        for notification in appNotifications {
            let addResult = AXObserverAddNotification(
                observer,
                appElement,
                notification as CFString,
                userData
            )
            if addResult == .success {
                logDebug("Added app-level \(notification) observer for \(app.name)")
            }
        }
        
        // Strategy 2: Observe focused window specifically for better context
        if let focusedWindow = getFocusedWindow(appElement: appElement) {
            let windowNotifications = [
                kAXTitleChangedNotification,
                kAXValueChangedNotification,
                kAXFocusedUIElementChangedNotification
            ]
            
            for notification in windowNotifications {
                let addResult = AXObserverAddNotification(
                    observer,
                    focusedWindow,
                    notification as CFString,
                    userData
                )
                if addResult == .success {
                    logDebug("Added window-level \(notification) observer for \(app.name)")
                }
            }
        }
        
        // Strategy 3: Observe currently focused element for granular updates
        if let focusedElement = getFocusedElement(appElement: appElement) {
            setupFocusedElementObserver(observer: observer, element: focusedElement, userData: userData, appName: app.name)
        }
        
        // Add observer to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        
        logInfo("Enhanced AXObserver setup complete for \(app.name)")
    }
    
    private func getFocusedWindow(appElement: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success,
              let window = windowRef,
              CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return nil
        }
        return (window as! AXUIElement)
    }
    
    private func getFocusedElement(appElement: AXUIElement) -> AXUIElement? {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
              let focused = focusedRef,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        return (focused as! AXUIElement)
    }
    
    private func setupFocusedElementObserver(observer: AXObserver, element: AXUIElement, userData: UnsafeMutableRawPointer, appName: String) {
        // Get element role to determine relevant notifications
        var roleRef: CFTypeRef?
        var elementRole = "unknown"
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            elementRole = role
        }
        
        // Determine notifications based on element type
        var elementNotifications: [String] = []
        
        switch elementRole {
        case "AXTextField", "AXTextArea", "AXSecureTextField":
            elementNotifications = [
                kAXValueChangedNotification,
                kAXSelectedTextChangedNotification,
                "AXTextSelectionChangedNotification"
            ]
        case "AXWebArea":
            elementNotifications = [
                kAXValueChangedNotification,
                kAXSelectedTextChangedNotification,
                kAXTitleChangedNotification,
                "AXLoadCompleteNotification"
            ]
        case "AXComboBox", "AXPopUpButton":
            elementNotifications = [
                kAXValueChangedNotification,
                "AXMenuItemSelectedNotification"
            ]
        case "AXButton", "AXCheckBox", "AXRadioButton":
            elementNotifications = [
                kAXValueChangedNotification,
                "AXPressedNotification"
            ]
        default:
            elementNotifications = [
                kAXValueChangedNotification,
                kAXSelectedTextChangedNotification
            ]
        }
        
        // Add element-specific notifications
        for notification in elementNotifications {
            let addResult = AXObserverAddNotification(
                observer,
                element,
                notification as CFString,
                userData
            )
            if addResult == .success {
                logDebug("Added element-level \(notification) for \(elementRole) in \(appName)")
            }
        }
    }
    
    private func handleAccessibilityNotification(element: AXUIElement, notification: CFString) {
        let notificationName = notification as String
        
        // Get additional context from the element that triggered the notification
        let elementContext = extractFocusedElementContext(element) ?? "unknown"
        logDebug("Received \(notificationName) from element: \(elementContext)")
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let mousePos = getMousePosition()
        
        // For focused element changes, dynamically update observer targeting
        if notificationName == kAXFocusedUIElementChangedNotification {
            updateObserverTargeting(newFocusedElement: element)
        }
        
        // Check for text changes with enhanced context
        if let event = checkForEvents(timestamp: timestamp, mousePosition: mousePos) {
            eventHandler?(event)
        }
    }
    
    private func updateObserverTargeting(newFocusedElement: AXUIElement) {
        guard let observer = axObserver else { return }
        
        // Add targeted observations for the newly focused element
        let userData = Unmanaged.passUnretained(self).toOpaque()
        setupFocusedElementObserver(observer: observer, element: newFocusedElement, userData: userData, appName: "current")
        
        logDebug("Updated observer targeting for newly focused element")
    }
    
    func updateForAppChange(_ newApp: AppInfo) {
        // Only recreate observer if we're switching to a different app
        if newApp.processIdentifier != observedApp {
            setupObserverForApp(newApp)
        }
    }

    func checkForEvents(
        timestamp: Int64,
        mousePosition: (x: Int, y: Int)
    )
        -> ActivityEvent? {
        let currentApp = getCurrentAppInfoStructured()

        // Try aggressive text extraction (even for apps that normally require fallback)
        if let text = extractCurrentText(from: currentApp) {
            // Check if text or app changed
            if text != lastText || currentApp.bundleIdentifier != lastApp {
                lastText = text
                lastApp = currentApp.bundleIdentifier

                // Determine source based on whether app requires fallback
                let source = currentApp.requiresFallback ? "observer" : "accessibility-observer"

                return TextSelectionEvent(
                    timestamp: timestamp,
                    mousePosition: mousePosition,
                    app: currentApp,
                    text: text,
                    selectionLength: text.count,
                    source: source,
                    context: nil
                )
            }
        }
        else {
            // Clear if no text
            lastText = ""
        }

        return nil
    }

    private func extractCurrentText(from app: AppInfo) -> String? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Strategy 1: Try focused element first (fast path)
        if let text = extractFromFocusedElement(appElement: appElement) {
            return text
        }

        // Strategy 2: Search window tree for text fields (more aggressive)
        if let text = extractFromWindowTree(appElement: appElement) {
            return text
        }

        // Strategy 3: For web apps, search web areas specifically
        if isWebApp(app: app) {
            if let text = extractFromWebAreas(appElement: appElement) {
                return text
            }
        }

        return nil
    }

    // MARK: - Text Extraction Strategies

    private func extractFromFocusedElement(appElement: AXUIElement) -> String? {
        var focusedRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &focusedRef
            ) == .success,
            let focusedElement = focusedRef,
            CFGetTypeID(focusedElement) == AXUIElementGetTypeID()
        else { return nil }

        let axElement = focusedElement as! AXUIElement
        return extractTextFromElement(axElement)
    }

    private func extractFromWindowTree(appElement: AXUIElement) -> String? {
        // Get focused window
        var windowRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &windowRef
            ) == .success,
            let window = windowRef,
            CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }

        let axWindow = window as! AXUIElement

        // Search for text fields in the window tree
        return findTextInElementTree(element: axWindow, depth: 0, maxDepth: 8)
    }

    private func extractFromWebAreas(appElement: AXUIElement) -> String? {
        // Get focused window first
        var windowRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &windowRef
            ) == .success,
            let window = windowRef,
            CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }

        let axWindow = window as! AXUIElement

        // Find web areas (for browser-based apps)
        return findTextInWebAreas(element: axWindow, depth: 0, maxDepth: 10)
    }

    private func extractTextFromElement(_ element: AXUIElement) -> String? {
        // Try different text attributes in order of preference
        let textAttributes = [
            kAXSelectedTextAttribute,
            kAXValueAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            "AXPlaceholderValue" // For placeholder text in inputs
        ]

        for attribute in textAttributes {
            var textRef: CFTypeRef?
            if
                AXUIElementCopyAttributeValue(element, attribute as CFString, &textRef) ==
                .success,
                let text = textRef as? String, !text.isEmpty {
                // Limit text length to prevent huge captures
                return text.count > 500 ? String(text.prefix(500)) : text
            }
        }

        return nil
    }

    private func findTextInElementTree(
        element: AXUIElement,
        depth: Int,
        maxDepth: Int
    )
        -> String? {
        guard depth < maxDepth else { return nil }

        // Check if current element has text
        if let text = extractTextFromElement(element) {
            return text
        }

        // Check role - prioritize text-related elements
        var roleRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                element,
                kAXRoleAttribute as CFString,
                &roleRef
            ) == .success,
            let role = roleRef as? String {

            // Prioritize text input elements
            let textRoles = [
                "AXTextField", "AXTextArea", "AXComboBox", "AXStaticText",
                "AXGroup",
                "AXScrollArea" // Groups and scroll areas might contain text fields
            ]

            if textRoles.contains(role) {
                if let text = extractTextFromElement(element) {
                    return text
                }
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenRef
            ) == .success,
            let children = childrenRef as? [AXUIElement] {

            // Search children, but prioritize likely text containers
            for child in children {
                if
                    let text = findTextInElementTree(
                        element: child,
                        depth: depth + 1,
                        maxDepth: maxDepth
                    ) {
                    return text
                }
            }
        }

        return nil
    }

    private func findTextInWebAreas(
        element: AXUIElement,
        depth: Int,
        maxDepth: Int
    )
        -> String? {
        guard depth < maxDepth else { return nil }

        // Check if this is a web area
        var roleRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                element,
                kAXRoleAttribute as CFString,
                &roleRef
            ) == .success,
            let role = roleRef as? String, role == "AXWebArea" {

            // Search for text inputs within web area
            if let text = findWebTextInputs(webArea: element, depth: 0, maxDepth: 6) {
                return text
            }
        }

        // Recurse into children to find web areas
        var childrenRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenRef
            ) == .success,
            let children = childrenRef as? [AXUIElement] {
            for child in children {
                if
                    let text = findTextInWebAreas(
                        element: child,
                        depth: depth + 1,
                        maxDepth: maxDepth
                    ) {
                    return text
                }
            }
        }

        return nil
    }

    private func findWebTextInputs(
        webArea: AXUIElement,
        depth: Int,
        maxDepth: Int
    )
        -> String? {
        guard depth < maxDepth else { return nil }

        // Check current element for text
        if let text = extractTextFromElement(webArea) {
            return text
        }

        // Look for web-specific text input roles
        var roleRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                webArea,
                kAXRoleAttribute as CFString,
                &roleRef
            ) == .success,
            let role = roleRef as? String {

            let webTextRoles = [
                "AXTextField", "AXTextArea", "AXComboBox", "AXGroup",
                "AXGenericContainer", "AXList", "AXListItem" // Common in web apps
            ]

            if webTextRoles.contains(role) {
                if let text = extractTextFromElement(webArea) {
                    return text
                }
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                webArea,
                kAXChildrenAttribute as CFString,
                &childrenRef
            ) == .success,
            let children = childrenRef as? [AXUIElement] {
            for child in children {
                if
                    let text = findWebTextInputs(
                        webArea: child,
                        depth: depth + 1,
                        maxDepth: maxDepth
                    ) {
                    return text
                }
            }
        }

        return nil
    }

    private func isWebApp(app: AppInfo) -> Bool {
        // Check if this is a browser or web-based application
        let webBrowsers = ["Chrome", "Safari", "Firefox", "Edge", "Arc", "Brave"]
        return webBrowsers.contains { app.bundleIdentifier.contains($0) }
    }
}

// MARK: – Browser Tracker

class BrowserTracker: EventTracker {
    private var lastURL: String = ""
    private var lastPageTitle: String = ""
    private var lastAppBundleId: String = ""
    private var browserCapabilityCache: [String: BrowserCapabilities] = [:]
    private var axObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var observedApp: pid_t = -1
    
    var eventHandler: ((ActivityEvent) -> Void)?
    
    deinit {
        stopObserving()
    }
    
    func startObserving() {
        stopObserving() // Clean up any existing observer
        
        let currentApp = getCurrentAppInfoStructured()
        guard currentApp.processIdentifier != -1, hasBrowserCapabilities(app: currentApp) else { return }
        
        setupObserverForApp(currentApp)
    }
    
    func stopObserving() {
        guard let observer = axObserver else { return }
        
        if let element = observedElement {
            // Remove browser-specific notifications
            AXObserverRemoveNotification(observer, element, kAXTitleChangedNotification as CFString)
            AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
            AXObserverRemoveNotification(observer, element, kAXFocusedUIElementChangedNotification as CFString)
        }
        
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = nil
        observedElement = nil
        observedApp = -1
    }
    
    private func setupObserverForApp(_ app: AppInfo) {
        let pid = app.processIdentifier
        
        // Create observer
        var observer: AXObserver?
        let result = AXObserverCreate(pid, { (observer, element, notification, userData) in
            guard let userData = userData else { return }
            let browserTracker = Unmanaged<BrowserTracker>.fromOpaque(userData).takeUnretainedValue()
            browserTracker.handleAccessibilityNotification(element: element, notification: notification)
        }, &observer)
        
        guard result == .success, let observer = observer else {
            logDebug("Failed to create AXObserver for browser \(app.name): \(result)")
            return
        }
        
        self.axObserver = observer
        self.observedApp = pid
        
        // Get the application element
        let appElement = AXUIElementCreateApplication(pid)
        self.observedElement = appElement
        
        // Add browser-specific notifications
        let userData = Unmanaged.passUnretained(self).toOpaque()
        
        let notifications = [
            kAXTitleChangedNotification,       // Page title changes
            kAXValueChangedNotification,       // Address bar changes
            kAXFocusedUIElementChangedNotification // Tab switches
        ]
        
        for notification in notifications {
            let addResult = AXObserverAddNotification(
                observer,
                appElement,
                notification as CFString,
                userData
            )
            if addResult == .success {
                logDebug("Successfully added \(notification) observer for browser \(app.name)")
            } else {
                logDebug("Failed to add \(notification) observer for browser \(app.name): \(addResult)")
            }
        }
        
        // Add observer to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        
        logInfo("Browser AXObserver setup complete for \(app.name)")
    }
    
    private func handleAccessibilityNotification(element: AXUIElement, notification: CFString) {
        let notificationName = notification as String
        logDebug("Received browser accessibility notification: \(notificationName)")
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let mousePos = getMousePosition()
        
        // Check for browser navigation changes
        if let event = checkForEvents(timestamp: timestamp, mousePosition: mousePos) {
            eventHandler?(event)
        }
    }
    
    func updateForAppChange(_ newApp: AppInfo) {
        // Only recreate observer if we're switching to a different browser app
        if newApp.processIdentifier != observedApp, hasBrowserCapabilities(app: newApp) {
            setupObserverForApp(newApp)
        } else if !hasBrowserCapabilities(app: newApp) {
            stopObserving()
        }
    }

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

    func checkForEvents(
        timestamp: Int64,
        mousePosition: (x: Int, y: Int)
    )
        -> ActivityEvent? {

        let currentApp = getCurrentAppInfoStructured()
        let capabilities = getBrowserCapabilities(for: currentApp)
        guard capabilities.hasURLSupport || capabilities.hasTitleSupport
        else { return nil }

        // Focused window
        let appElement = AXUIElementCreateApplication(currentApp.processIdentifier)
        var windowRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &windowRef
            ) == .success,
            let window = windowRef,
            CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        let axWindow = window as! AXUIElement

        var hasChanges = false
        var currentURL = ""
        var currentTitle = ""
        var tabCount: Int?

        // Debug logging can be enabled here if needed for troubleshooting browser issues
        // if currentApp.bundleIdentifier.contains("Chrome") {
        //     logDebug("=== CHROME ACCESSIBILITY TREE ===")
        //     dumpAXTree(axWindow, maxDepth: 4)
        //     logDebug("=== END CHROME TREE ===")
        // }

        // 1) URL/TITLE extraction - different strategies for different browsers
        if currentApp.bundleIdentifier.contains("Chrome") {
            // Chrome-specific URL extraction
            // LIMITATION: Chrome's accessibility API doesn't reliably expose active tab URLs.
            // The window-level AXDocument often reflects a "base" URL rather than the
            // active tab's URL.
            // However, window titles do correctly reflect the active tab content.
            logDebug("🔍 Extracting URL from Chrome accessibility tree")

            // Get title from window (reliable - reflects active tab)
            var titleRef: CFTypeRef?
            if
                AXUIElementCopyAttributeValue(
                    axWindow,
                    kAXTitleAttribute as CFString,
                    &titleRef
                ) == .success,
                let title = titleRef as? String, !title.isEmpty {
                currentTitle = title
                logDebug("Got title from Chrome window: '\(title.prefix(50))'")
            }

            // Get URL from window AXDocument (may be stale but provides domain info)
            var docRef: CFTypeRef?
            if
                AXUIElementCopyAttributeValue(
                    axWindow,
                    kAXDocumentAttribute as CFString,
                    &docRef
                ) == .success,
                let docURL = docRef as? String, !docURL.isEmpty {
                currentURL = docURL
                logDebug("Got URL from Chrome window.AXDocument: '\(docURL.prefix(50))'")
            }

            // Fallback: try to find AXWebArea with accurate URL (uncommon in Chrome)
            if currentURL.isEmpty {
                if
                    let webArea = firstDescendant(
                        element: axWindow,
                        role: "AXWebArea",
                        maxDepth: 6
                    ) {
                    logDebug("✅ Found AXWebArea in Chrome tree")

                    for attr in [kAXURLAttribute, kAXDocumentAttribute] {
                        var ref: CFTypeRef?
                        if
                            AXUIElementCopyAttributeValue(
                                webArea,
                                attr as CFString,
                                &ref
                            ) ==
                            .success {
                            if let s = ref as? String, !s.isEmpty {
                                currentURL = s
                                logDebug(
                                    "Got URL from Chrome AXWebArea.\(attr): '\(s.prefix(50))'"
                                )
                                break
                            }
                            else if CFGetTypeID(ref) == CFURLGetTypeID() {
                                let cfURL = ref as! CFURL
                                let s = CFURLGetString(cfURL) as String
                                if !s.isEmpty {
                                    currentURL = s
                                    logDebug(
                                        "Got URL from Chrome AXWebArea.\(attr) (CFURL): '\(s.prefix(50))'"
                                    )
                                    break
                                }
                            }
                        }
                    }
                }
            }

        }
        else {
            // Safari/Arc and other WebKit browsers - use AXWebArea
            if let webArea = firstDescendant(element: axWindow, role: "AXWebArea") {
                logDebug("✅ Found AXWebArea in \(currentApp.name)")

                for attr in [kAXURLAttribute, kAXDocumentAttribute] {
                    var ref: CFTypeRef?
                    if
                        AXUIElementCopyAttributeValue(webArea, attr as CFString, &ref) ==
                        .success {

                        // String case
                        if let s = ref as? String, !s.isEmpty {
                            currentURL = s
                            logDebug("Got URL from AXWebArea.\(attr): '\(s.prefix(50))'")
                            break
                        }

                        // CFURL case
                        if CFGetTypeID(ref) == CFURLGetTypeID() {
                            let cfURL = ref as! CFURL
                            let s = CFURLGetString(cfURL) as String
                            if !s.isEmpty {
                                currentURL = s
                                logDebug(
                                    "Got URL from AXWebArea.\(attr) (CFURL): '\(s.prefix(50))'"
                                )
                                break
                            }
                        }
                    }
                }

                var titleRef: CFTypeRef?
                if
                    AXUIElementCopyAttributeValue(
                        webArea,
                        kAXTitleAttribute as CFString,
                        &titleRef
                    ) == .success,
                    let t = titleRef as? String, !t.isEmpty {
                    currentTitle = t
                    logDebug("Got title from AXWebArea: '\(t.prefix(50))'")
                }
            }
            else {
                logDebug("❌ No AXWebArea found in \(currentApp.name)")
            }
        }

        // 2) Tab count extraction for any remaining browsers that support it
        if let tabsAttr = capabilities.tabsAttribute {
            var tabsRef: CFTypeRef?
            if
                AXUIElementCopyAttributeValue(
                    axWindow,
                    tabsAttr as CFString,
                    &tabsRef
                ) == .success,
                let tabs = tabsRef as? [AXUIElement], !tabs.isEmpty {
                tabCount = tabs.count
                logDebug("Found \(tabCount ?? 0) tabs in \(currentApp.name)")
            }
        }

        // 3) Change detection
        let focusChanged = currentApp.bundleIdentifier != lastAppBundleId
        if focusChanged || currentURL != lastURL || currentTitle != lastPageTitle {
            hasChanges = true
        }
        guard hasChanges else { return nil }

        // Persist state
        lastURL = currentURL
        lastPageTitle = currentTitle
        lastAppBundleId = currentApp.bundleIdentifier

        let domain = URL(string: currentURL)?.host ?? "unknown"

        return BrowserNavigationEvent(
            timestamp: timestamp,
            mousePosition: mousePosition,
            app: currentApp,
            currentURL: currentURL,
            domain: domain,
            tabCount: tabCount,
            pageTitle: currentTitle.isEmpty ? nil : currentTitle
        )
    }

    // Helper: depth-first search for the first element of a given AXRole
    private func firstDescendant(
        element: AXUIElement,
        role wanted: String,
        depth: Int = 0,
        maxDepth: Int = 6
    )
        -> AXUIElement? {
        guard depth < maxDepth else { return nil }

        var kidsRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &kidsRef
            ) == .success,
            let kids = kidsRef as? [AXUIElement] {
            for kid in kids {
                var roleRef: CFTypeRef?
                if
                    AXUIElementCopyAttributeValue(
                        kid,
                        kAXRoleAttribute as CFString,
                        &roleRef
                    ) == .success,
                    let role = roleRef as? String, role == wanted {
                    return kid
                }
                if
                    let found = firstDescendant(
                        element: kid,
                        role: wanted,
                        depth: depth + 1,
                        maxDepth: maxDepth
                    ) {
                    return found
                }
            }
        }
        return nil
    }

    // Helper: recursively search for any URL in the accessibility tree
    private func findURLInTree(
        element: AXUIElement,
        depth: Int,
        maxDepth: Int
    )
        -> String {
        guard depth < maxDepth else { return "" }

        // Check URL attributes on current element
        let urlAttributes = [
            "AXURL",
            kAXDocumentAttribute,
            "AXDescription",
            "AXHelp",
            "AXValue"
        ]
        for attr in urlAttributes {
            var ref: CFTypeRef?
            if
                AXUIElementCopyAttributeValue(element, attr as CFString, &ref) ==
                .success {
                if let s = ref as? String, !s.isEmpty, isValidURL(s) {
                    return s
                }
                else if CFGetTypeID(ref) == CFURLGetTypeID() {
                    let cfURL = ref as! CFURL
                    let s = CFURLGetString(cfURL) as String
                    if !s.isEmpty, isValidURL(s) {
                        return s
                    }
                }
            }
        }

        // Recurse into children
        var kidsRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &kidsRef
            ) == .success,
            let kids = kidsRef as? [AXUIElement] {
            for kid in kids {
                let result = findURLInTree(
                    element: kid,
                    depth: depth + 1,
                    maxDepth: maxDepth
                )
                if !result.isEmpty {
                    return result
                }
            }
        }

        return ""
    }

    // Helper: check if string looks like a valid URL
    private func isValidURL(_ string: String) -> Bool {
        string.hasPrefix("http://") || string.hasPrefix("https://") || string
            .contains("://")
    }

    // Additional helper methods for specialized browser URL extraction could be added
    // here
    // Currently focused on Chrome window-level and Safari AXWebArea approaches

    // Legacy helper methods kept for potential future use or debugging
    // These are no longer used in the main URL extraction flow but may be useful
    // for specialized cases or troubleshooting specific browser versions

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
        logDebug(
            "Detecting browser capabilities for: \(app.name) (\(app.bundleIdentifier))"
        )

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get focused window for testing
        var windowRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &windowRef
            ) == .success,
            let window = windowRef,
            CFGetTypeID(window) == AXUIElementGetTypeID()
        else {
            logDebug("No focused window found for \(app.name), skipping browser detection"
            )
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
            if
                AXUIElementCopyAttributeValue(axWindow, attr as CFString, &testRef) ==
                .success,
                let value = testRef as? String,
                !value.isEmpty {
                logDebug("Testing \(attr) for \(app.name): '\(value.prefix(100))'")
                if
                    value.hasPrefix("http://") || value.hasPrefix("https://") || value
                        .contains("://") {
                    urlAttribute = attr
                    logDebug("Found URL attribute \(attr) for \(app.name)")
                    break
                }
            }
        }

        // If no URL found in window, try to find address bar in children
        if urlAttribute == nil {
            var childrenRef: CFTypeRef?
            if
                AXUIElementCopyAttributeValue(
                    axWindow,
                    kAXChildrenAttribute as CFString,
                    &childrenRef
                ) == .success,
                let children = childrenRef as? [AXUIElement] {
                logDebug(
                    "Searching \(children.count) child elements for URL info in \(app.name)"
                )

                for child in children.prefix(8) { // Limit search to first 8 children
                    for attr in ["AXURL", "AXValue", "AXDescription"] {
                        var testRef: CFTypeRef?
                        if
                            AXUIElementCopyAttributeValue(
                                child,
                                attr as CFString,
                                &testRef
                            ) == .success,
                            let value = testRef as? String,
                            !value.isEmpty,
                            value.hasPrefix("http://") || value
                                .hasPrefix("https://") || value.contains("://") {
                            urlAttribute = attr
                            logDebug(
                                "Found URL in child element using \(attr): '\(value.prefix(50))'"
                            )
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
            if
                AXUIElementCopyAttributeValue(axWindow, attr as CFString, &testRef) ==
                .success,
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
            if
                AXUIElementCopyAttributeValue(axWindow, attr as CFString, &testRef) ==
                .success,
                let tabs = testRef as? [Any],
                !tabs.isEmpty {
                tabsAttribute = attr
                break
            }
        }

        // Chrome hack: Even if window doesn't have URL, tabs might have AXURL
        let effectiveURLSupport = urlAttribute != nil || tabsAttribute != nil

        logDebug(
            "Browser capabilities for \(app.name): URL=\(urlAttribute ?? "none"), Title=\(titleAttribute ?? "none"), Tabs=\(tabsAttribute ?? "none"), EffectiveURL=\(effectiveURLSupport)"
        )

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

    func hasBrowserCapabilities(app: AppInfo) -> Bool {
        let capabilities = getBrowserCapabilities(for: app)
        return capabilities.hasURLSupport || capabilities.hasTitleSupport
    }

    // ───── Debug helper ──────────────────────────────────────────────────────────
    private func dumpAXTree(
        _ elem: AXUIElement,
        indent: String = "",
        depth: Int = 0,
        maxDepth: Int = 4
    ) {

        guard depth <= maxDepth else { return }

        // Role + (optional) identifier
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            elem,
            kAXRoleAttribute as CFString,
            &roleRef
        )
        let role = (roleRef as? String) ?? "?"

        var idRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            elem,
            kAXIdentifierAttribute as CFString,
            &idRef
        )
        let ident = (idRef as? String) ?? ""

        logDebug("\(indent)• \(role)\(ident.isEmpty ? "" : "  id=\(ident)")")

        // Dump all attributes (name: value)
        var namesCF: CFArray?
        if
            AXUIElementCopyAttributeNames(elem, &namesCF) == .success,
            let names = namesCF as? [String] {
            for name in names {
                var vRef: CFTypeRef?
                if
                    AXUIElementCopyAttributeValue(
                        elem,
                        name as CFString,
                        &vRef
                    ) == .success {
                    let txt: String = if let s = vRef as? String { s }
                    else if CFGetTypeID(vRef) == CFURLGetTypeID() {
                        CFURLGetString((vRef as! CFURL)) as String
                    }
                    else {
                        String(describing: vRef)
                    }
                    logDebug("\(indent)   \(name): \(txt.prefix(120))")
                }
            }
        }

        // Recurse into children
        var kidsRef: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                elem,
                kAXChildrenAttribute as CFString,
                &kidsRef
            ) == .success,
            let kids = kidsRef as? [AXUIElement] {
            for kid in kids {
                dumpAXTree(
                    kid,
                    indent: indent + "  ",
                    depth: depth + 1,
                    maxDepth: maxDepth
                )
            }
        }
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
            focusState: "unfocused", executableURL: "", launchDate: 0,
            windowTitle: nil, focusedElementInfo: nil
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

    // Get window title from focused window
    var windowTitle: String? = nil
    if hasTree {
        var focusedWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        ) == .success,
           let focusedWindow = focusedWindowRef,
           CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() {
            
            let axWindow = focusedWindow as! AXUIElement
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                axWindow,
                kAXTitleAttribute as CFString,
                &titleRef
            ) == .success,
               let title = titleRef as? String,
               !title.isEmpty {
                windowTitle = title
            }
        }
    }

    // Get focused element information for rich context
    var focusedElementInfo: String? = nil
    let canAccessFocus: Bool = {
        guard hasTree else { return false }
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
           let focusedElement = focusedRef,
           CFGetTypeID(focusedElement) == AXUIElementGetTypeID() {
            
            let axElement = focusedElement as! AXUIElement
            focusedElementInfo = extractFocusedElementContext(axElement)
            return true
        }
        return false
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
        launchDate: app.launchDate?.timeIntervalSince1970 ?? 0,
        windowTitle: windowTitle,
        focusedElementInfo: focusedElementInfo
    )
}

private func extractFocusedElementContext(_ element: AXUIElement) -> String? {
    var contextParts: [String] = []
    
    // Get role
    var roleRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
       let role = roleRef as? String {
        contextParts.append("role:\(role)")
    }
    
    // Get role description
    var roleDescRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescRef) == .success,
       let roleDesc = roleDescRef as? String {
        contextParts.append("desc:\(roleDesc)")
    }
    
    // Get title/label
    var titleRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
       let title = titleRef as? String, !title.isEmpty {
        contextParts.append("title:\(title.prefix(50))")
    }
    
    // Get value for input fields
    var valueRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
       let value = valueRef as? String, !value.isEmpty {
        contextParts.append("value:\(value.prefix(30))")
    }
    
    // Get help text
    var helpRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &helpRef) == .success,
       let help = helpRef as? String, !help.isEmpty {
        contextParts.append("help:\(help.prefix(50))")
    }
    
    return contextParts.isEmpty ? nil : contextParts.joined(separator: "|")
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
    }
    catch {
        logError("Failed to start ActivityTracker: \(error)")
        exit(1)
    }
}

public func runActivityTrackerComprehensive() {
    runActivityTracker(config: .comprehensive)
}
