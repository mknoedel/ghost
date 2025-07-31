// EventSchemas.swift – Activity Tracker Event Definitions
// -------------------------------------------------------------
// Defines all event types and their data schemas for the
// SelectionTap activity tracking system. This file serves as
// the single source of truth for event structure.
// -------------------------------------------------------------

import Foundation

// MARK: - Event Types

public enum EventType: String, CaseIterable {
    case focusChange = "focus_change"
    case textSelection = "text_selection"
    case windowUpdate = "window_update"
    case browserNavigation = "browser_navigation"
    case systemMetrics = "system_metrics"
    case userActivity = "user_activity"
    case heartbeat = "heartbeat"
    
    public var description: String {
        switch self {
        case .focusChange: return "Application focus changed"
        case .textSelection: return "Text selected or input detected"
        case .windowUpdate: return "Window properties changed"
        case .browserNavigation: return "Browser URL or tab changed"
        case .systemMetrics: return "System resource metrics"
        case .userActivity: return "User input activity detected"
        case .heartbeat: return "Periodic activity heartbeat"
        }
    }
}

// MARK: - Base Event Protocol

public protocol ActivityEvent {
    var eventType: EventType { get }
    var timestamp: Int64 { get }
    var mousePosition: (x: Int, y: Int) { get }
    func toDictionary() -> [String: Any]
}

// MARK: - App Information Schema

public struct AppInfo: Codable {
    public let name: String
    public let bundleIdentifier: String
    public let processIdentifier: Int32
    public let isAccessible: Bool
    public let requiresFallback: Bool
    public let focusState: String
    public let executableURL: String
    public let launchDate: Double
    
    public init(name: String, bundleIdentifier: String, processIdentifier: Int32, 
                isAccessible: Bool, requiresFallback: Bool,
                focusState: String, executableURL: String, launchDate: Double) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.isAccessible = isAccessible
        self.requiresFallback = requiresFallback
        self.focusState = focusState
        self.executableURL = executableURL
        self.launchDate = launchDate
    }
    
    public func toDictionary() -> [String: Any] {
        return [
            "name": name,
            "bundleIdentifier": bundleIdentifier,
            "processIdentifier": processIdentifier,
            "isAccessible": isAccessible,
            "requiresFallback": requiresFallback,
            "focusState": focusState,
            "executableURL": executableURL,
            "launchDate": launchDate
        ]
    }
}

// MARK: - Specific Event Implementations

public struct FocusChangeEvent: ActivityEvent {
    public let eventType: EventType = .focusChange
    public let timestamp: Int64
    public let mousePosition: (x: Int, y: Int)
    
    public let currentApp: AppInfo
    public let previousApp: AppInfo?
    public let focusDuration: Double
    public let sessionId: String
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventType": eventType.rawValue,
            "timestamp": timestamp,
            "x": mousePosition.x,
            "y": mousePosition.y,
            "app": currentApp.toDictionary(),
            "focusDuration": focusDuration,
            "sessionId": sessionId
        ]
        
        if let previous = previousApp {
            dict["previousApp"] = previous.toDictionary()
        }
        
        return dict
    }
}

public struct TextSelectionEvent: ActivityEvent {
    public let eventType: EventType = .textSelection
    public let timestamp: Int64
    public let mousePosition: (x: Int, y: Int)
    
    public let app: AppInfo
    public let text: String
    public let selectionLength: Int
    public let source: String // "accessibility", "clipboard", "fallback"
    public let context: String? // surrounding text context
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventType": eventType.rawValue,
            "timestamp": timestamp,
            "x": mousePosition.x,
            "y": mousePosition.y,
            "app": app.toDictionary(),
            "text": text,
            "selectionLength": selectionLength,
            "source": source
        ]
        
        if let context = context {
            dict["context"] = context
        }
        
        return dict
    }
}

public struct WindowUpdateEvent: ActivityEvent {
    public let eventType: EventType = .windowUpdate
    public let timestamp: Int64
    public let mousePosition: (x: Int, y: Int)
    
    public let app: AppInfo
    public let windowTitle: String
    public let windowPosition: (x: Double, y: Double)
    public let windowSize: (width: Double, height: Double)
    public let isMainWindow: Bool
    
    public func toDictionary() -> [String: Any] {
        return [
            "eventType": eventType.rawValue,
            "timestamp": timestamp,
            "x": mousePosition.x,
            "y": mousePosition.y,
            "app": app.toDictionary(),
            "windowTitle": windowTitle,
            "windowPosition": ["x": windowPosition.x, "y": windowPosition.y],
            "windowSize": ["width": windowSize.width, "height": windowSize.height],
            "isMainWindow": isMainWindow
        ]
    }
}

public struct BrowserNavigationEvent: ActivityEvent {
    public let eventType: EventType = .browserNavigation
    public let timestamp: Int64
    public let mousePosition: (x: Int, y: Int)
    
    public let app: AppInfo
    public let currentURL: String
    public let domain: String
    public let tabCount: Int?
    public let pageTitle: String?
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventType": eventType.rawValue,
            "timestamp": timestamp,
            "x": mousePosition.x,
            "y": mousePosition.y,
            "app": app.toDictionary(),
            "currentURL": currentURL,
            "domain": domain
        ]
        
        if let tabCount = tabCount {
            dict["tabCount"] = tabCount
        }
        
        if let pageTitle = pageTitle {
            dict["pageTitle"] = pageTitle
        }
        
        return dict
    }
}

public struct SystemMetricsEvent: ActivityEvent {
    public let eventType: EventType = .systemMetrics
    public let timestamp: Int64
    public let mousePosition: (x: Int, y: Int)
    
    public let batteryLevel: Double?
    public let isCharging: Bool?
    public let screenSize: (width: Double, height: Double)
    public let screenScale: Double
    public let memoryPressure: String?
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventType": eventType.rawValue,
            "timestamp": timestamp,
            "x": mousePosition.x,
            "y": mousePosition.y,
            "screenSize": ["width": screenSize.width, "height": screenSize.height],
            "screenScale": screenScale
        ]
        
        if let batteryLevel = batteryLevel {
            dict["batteryLevel"] = batteryLevel
        }
        
        if let isCharging = isCharging {
            dict["isCharging"] = isCharging
        }
        
        if let memoryPressure = memoryPressure {
            dict["memoryPressure"] = memoryPressure
        }
        
        return dict
    }
}

public struct UserActivityEvent: ActivityEvent {
    public let eventType: EventType = .userActivity
    public let timestamp: Int64
    public let mousePosition: (x: Int, y: Int)
    
    public let app: AppInfo
    public let activityType: String // "typing", "clicking", "scrolling", "idle"
    public let intensity: Double // 0.0 to 1.0
    public let duration: Double
    public let timeOfDay: String // "morning", "afternoon", "evening", "night"
    public let isWeekend: Bool
    
    public func toDictionary() -> [String: Any] {
        return [
            "eventType": eventType.rawValue,
            "timestamp": timestamp,
            "x": mousePosition.x,
            "y": mousePosition.y,
            "app": app.toDictionary(),
            "activityType": activityType,
            "intensity": intensity,
            "duration": duration,
            "timeOfDay": timeOfDay,
            "isWeekend": isWeekend
        ]
    }
}

public struct HeartbeatEvent: ActivityEvent {
    public let eventType: EventType = .heartbeat
    public let timestamp: Int64
    public let mousePosition: (x: Int, y: Int)
    
    public let app: AppInfo
    public let sessionDuration: Double
    public let activeSessions: [String: Double] // bundleId -> duration
    public let totalActiveTime: Double
    
    public func toDictionary() -> [String: Any] {
        return [
            "eventType": eventType.rawValue,
            "timestamp": timestamp,
            "x": mousePosition.x,
            "y": mousePosition.y,
            "app": app.toDictionary(),
            "sessionDuration": sessionDuration,
            "activeSessions": activeSessions,
            "totalActiveTime": totalActiveTime
        ]
    }
}

// MARK: - Event Factory

public class EventFactory {
    public static func createEvent(type: EventType, data: [String: Any]) -> ActivityEvent? {
        switch type {
        case .focusChange:
            return createFocusChangeEvent(from: data)
        case .textSelection:
            return createTextSelectionEvent(from: data)
        case .windowUpdate:
            return createWindowUpdateEvent(from: data)
        case .browserNavigation:
            return createBrowserNavigationEvent(from: data)
        case .systemMetrics:
            return createSystemMetricsEvent(from: data)
        case .userActivity:
            return createUserActivityEvent(from: data)
        case .heartbeat:
            return createHeartbeatEvent(from: data)
        }
    }
    
    // Factory methods for each event type
    private static func createFocusChangeEvent(from data: [String: Any]) -> FocusChangeEvent? {
        // Implementation would extract and validate required fields
        // This is a simplified version - full implementation would include validation
        return nil
    }
    
    private static func createTextSelectionEvent(from data: [String: Any]) -> TextSelectionEvent? {
        return nil
    }
    
    private static func createWindowUpdateEvent(from data: [String: Any]) -> WindowUpdateEvent? {
        return nil
    }
    
    private static func createBrowserNavigationEvent(from data: [String: Any]) -> BrowserNavigationEvent? {
        return nil
    }
    
    private static func createSystemMetricsEvent(from data: [String: Any]) -> SystemMetricsEvent? {
        return nil
    }
    
    private static func createUserActivityEvent(from data: [String: Any]) -> UserActivityEvent? {
        return nil
    }
    
    private static func createHeartbeatEvent(from data: [String: Any]) -> HeartbeatEvent? {
        return nil
    }
}