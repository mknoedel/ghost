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
    case browserNavigation = "browser_navigation"
    case heartbeat

    public var description: String {
        switch self {
        case .focusChange: "Application focus changed"
        case .textSelection: "Text selected or input detected"
        case .browserNavigation: "Browser URL or tab changed"
        case .heartbeat: "Periodic activity heartbeat"
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

    public init(
        name: String,
        bundleIdentifier: String,
        processIdentifier: Int32,
        isAccessible: Bool,
        requiresFallback: Bool,
        focusState: String,
        executableURL: String,
        launchDate: Double
    ) {
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
        [
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

        if let context {
            dict["context"] = context
        }

        return dict
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

        if let tabCount {
            dict["tabCount"] = tabCount
        }

        if let pageTitle {
            dict["pageTitle"] = pageTitle
        }

        return dict
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
        [
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
    public static func createEvent(
        type: EventType,
        data: [String: Any]
    )
        -> ActivityEvent? {
        switch type {
        case .focusChange:
            createFocusChangeEvent(from: data)
        case .textSelection:
            createTextSelectionEvent(from: data)
        case .browserNavigation:
            createBrowserNavigationEvent(from: data)
        case .heartbeat:
            createHeartbeatEvent(from: data)
        }
    }

    // Factory methods for each event type
    private static func createFocusChangeEvent(from data: [String: Any])
        -> FocusChangeEvent? {
        // Implementation would extract and validate required fields
        // This is a simplified version - full implementation would include validation
        nil
    }

    private static func createTextSelectionEvent(from data: [String: Any])
        -> TextSelectionEvent? {
        nil
    }

    private static func createBrowserNavigationEvent(from data: [String: Any])
        -> BrowserNavigationEvent? {
        nil
    }

    private static func createHeartbeatEvent(from data: [String: Any])
        -> HeartbeatEvent? {
        nil
    }
}
