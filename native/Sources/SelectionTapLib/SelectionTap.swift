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
    
    func checkForEvents(timestamp: Int64, mousePosition: (x: Int, y: Int)) -> ActivityEvent? {
        let currentApp = getCurrentAppInfoStructured()
        
        // Only track browser apps
        let browserIds = ["chrome", "safari", "firefox", "edge"]
        guard browserIds.contains(where: { currentApp.bundleIdentifier.lowercased().contains($0) }) else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(currentApp.processIdentifier)
        
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let window = windowRef,
           CFGetTypeID(window) == AXUIElementGetTypeID() {
            let axWindow = window as! AXUIElement
            
            // Try to get URL (this is browser-specific and may not always work)
            var urlRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, "AXURL" as CFString, &urlRef) == .success,
               let currentURL = urlRef as? String {
                
                if currentURL != lastURL {
                    lastURL = currentURL
                    
                    let domain = URL(string: currentURL)?.host ?? "unknown"
                    
                    return BrowserNavigationEvent(
                        timestamp: timestamp,
                        mousePosition: mousePosition,
                        app: currentApp,
                        currentURL: currentURL,
                        domain: domain,
                        tabCount: nil,
                        pageTitle: nil
                    )
                }
            }
        }
        
        return nil
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
            isAccessible: false, isIsolated: false, requiresFallback: true,
            focusState: "unfocused", executableURL: "", launchDate: 0
        )
    }
    
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    
    // Check accessibility
    var focusedRef: CFTypeRef?
    let isAccessible = AXUIElementCopyAttributeValue(
        appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef
    ) == .success
    
    // Check isolation
    var isoRef: CFTypeRef?
    let isIsolated = AXUIElementCopyAttributeValue(
        appElement, "AXIsolatedTree" as CFString, &isoRef
    ) == .success
    
    return AppInfo(
        name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
        bundleIdentifier: app.bundleIdentifier ?? "unknown",
        processIdentifier: app.processIdentifier,
        isAccessible: isAccessible,
        isIsolated: isIsolated,
        requiresFallback: isIsolated || !isAccessible,
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