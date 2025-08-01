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

// MARK: - Workflow Analysis Structures

public struct WorkflowContext: Codable {
    public let sessionId: String // Groups related activities
    public let sequenceNumber: Int64 // Order within session
    public let timeSinceLastEvent: Double // Seconds since previous event
    public let contextHash: String // Hash of current context for similarity
    public let workflowPhase: String? // Inferred phase: "research", "writing", "editing",
    // etc.

    public init(
        sessionId: String,
        sequenceNumber: Int64,
        timeSinceLastEvent: Double,
        contextHash: String,
        workflowPhase: String? = nil
    ) {
        self.sessionId = sessionId
        self.sequenceNumber = sequenceNumber
        self.timeSinceLastEvent = timeSinceLastEvent
        self.contextHash = contextHash
        self.workflowPhase = workflowPhase
    }
}

public struct ContentMetadata: Codable {
    public let contentType: String // "email", "code", "documentation", etc.

    public init(contentType: String) {
        self.contentType = contentType
    }
}

public struct InteractionContext: Codable {
    public let isMultitasking: Bool // Multiple apps/windows active

    public init(isMultitasking: Bool) {
        self.isMultitasking = isMultitasking
    }
}

// MARK: - Base Event Protocol

public protocol ActivityEvent {
    var eventType: EventType { get }
    var timestamp: Int64 { get }
    var mousePosition: (x: Int, y: Int) { get }
    var workflowContext: WorkflowContext { get } // Enhanced for workflow analysis
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
    public let windowTitle: String?
    public let focusedElementInfo: String?

    public init(
        name: String,
        bundleIdentifier: String,
        processIdentifier: Int32,
        isAccessible: Bool,
        requiresFallback: Bool,
        focusState: String,
        executableURL: String,
        launchDate: Double,
        windowTitle: String? = nil,
        focusedElementInfo: String? = nil
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.isAccessible = isAccessible
        self.requiresFallback = requiresFallback
        self.focusState = focusState
        self.executableURL = executableURL
        self.launchDate = launchDate
        self.windowTitle = windowTitle
        self.focusedElementInfo = focusedElementInfo
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "bundleIdentifier": bundleIdentifier,
            "processIdentifier": processIdentifier,
            "isAccessible": isAccessible,
            "requiresFallback": requiresFallback,
            "focusState": focusState,
            "executableURL": executableURL,
            "launchDate": launchDate
        ]

        if let windowTitle {
            dict["windowTitle"] = windowTitle
        }

        if let focusedElementInfo {
            dict["focusedElementInfo"] = focusedElementInfo
        }

        return dict
    }
}

// MARK: - Specific Event Implementations

public struct FocusChangeEvent: ActivityEvent {
    public let eventType: EventType = .focusChange
    public let timestamp: Int64
    public let mousePosition: (x: Int, y: Int)
    public let workflowContext: WorkflowContext

    public let currentApp: AppInfo
    public let previousApp: AppInfo?
    public let focusDuration: Double
    public let sessionId: String

    // Enhanced workflow analysis data for app switching
    public let interactionContext: InteractionContext
    public let appCategory: String? // "productivity", "communication", "development",
    // "entertainment"
    public let isTaskSwitch: Bool // Likely switching between different tasks vs same
    // workflow

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventType": eventType.rawValue,
            "timestamp": timestamp,
            "x": mousePosition.x,
            "y": mousePosition.y,
            "app": currentApp.toDictionary(),
            "focusDuration": focusDuration,
            "sessionId": sessionId,
            "workflowContext": [
                "sessionId": workflowContext.sessionId,
                "sequenceNumber": workflowContext.sequenceNumber,
                "timeSinceLastEvent": workflowContext.timeSinceLastEvent,
                "contextHash": workflowContext.contextHash,
                "workflowPhase": workflowContext.workflowPhase
            ],
            "interactionContext": [
                "isMultitasking": interactionContext.isMultitasking,
            ],
            "isTaskSwitch": isTaskSwitch,
        ]

        if let previous = previousApp {
            dict["previousApp"] = previous.toDictionary()
        }

        if let appCategory {
            dict["appCategory"] = appCategory
        }

        return dict
    }
}

public struct TextSelectionEvent: ActivityEvent {
    public let eventType: EventType = .textSelection
    public let timestamp: Int64
    public let mousePosition: (x: Int, y: Int)
    public let workflowContext: WorkflowContext

    public let app: AppInfo
    public let text: String
    public let selectionLength: Int
    public let source: String // "accessibility", "clipboard", "fallback"

    // Enhanced workflow analysis data
    public let contentMetadata: ContentMetadata
    public let interactionContext: InteractionContext
    public let documentContext: String? // File path, document title, etc.

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventType": eventType.rawValue,
            "timestamp": timestamp,
            "x": mousePosition.x,
            "y": mousePosition.y,
            "app": app.toDictionary(),
            "text": text,
            "selectionLength": selectionLength,
            "source": source,
            "workflowContext": [
                "sessionId": workflowContext.sessionId,
                "sequenceNumber": workflowContext.sequenceNumber,
                "timeSinceLastEvent": workflowContext.timeSinceLastEvent,
                "contextHash": workflowContext.contextHash,
                "workflowPhase": workflowContext.workflowPhase
            ],
            "contentMetadata": [
                "contentType": contentMetadata.contentType,
            ],
            "interactionContext": [
                "isMultitasking": interactionContext.isMultitasking,
            ]
        ]

        if let documentContext {
            dict["documentContext"] = documentContext
        }

        return dict
    }
}

public struct BrowserNavigationEvent: ActivityEvent {
    public let eventType: EventType = .browserNavigation
    public let timestamp: Int64
    public let mousePosition: (x: Int, y: Int)
    public let workflowContext: WorkflowContext

    public let app: AppInfo
    public let currentURL: String
    public let domain: String
    public let tabCount: Int?
    public let pageTitle: String?

    // Enhanced workflow analysis data for web browsing
    public let interactionContext: InteractionContext
    public let pageCategory: String? // "social", "work", "shopping", "documentation",
    // etc.

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventType": eventType.rawValue,
            "timestamp": timestamp,
            "x": mousePosition.x,
            "y": mousePosition.y,
            "app": app.toDictionary(),
            "currentURL": currentURL,
            "domain": domain,
            "workflowContext": [
                "sessionId": workflowContext.sessionId,
                "sequenceNumber": workflowContext.sequenceNumber,
                "timeSinceLastEvent": workflowContext.timeSinceLastEvent,
                "contextHash": workflowContext.contextHash,
                "workflowPhase": workflowContext.workflowPhase
            ],
            "interactionContext": [
                "isMultitasking": interactionContext.isMultitasking,
            ],
        ]

        // Add optional fields
        if let pageTitle {
            dict["pageTitle"] = pageTitle
        }
        if let pageCategory {
            dict["pageCategory"] = pageCategory
        }

        return dict
    }
}

public struct HeartbeatEvent: ActivityEvent {
    public let eventType: EventType = .heartbeat
    public let timestamp: Int64
    public let mousePosition: (x: Int, y: Int)
    public let workflowContext: WorkflowContext

    public let app: AppInfo
    public let sessionDuration: Double
    public let activeSessions: [String: Double] // bundleId -> duration

    // Enhanced workflow analysis data for activity patterns
    public let dominantCategory: String? // Most used app category in this session

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventType": eventType.rawValue,
            "timestamp": timestamp,
            "x": mousePosition.x,
            "y": mousePosition.y,
            "app": app.toDictionary(),
            "sessionDuration": sessionDuration,
            "activeSessions": activeSessions,
            "workflowContext": [
                "sessionId": workflowContext.sessionId,
                "sequenceNumber": workflowContext.sequenceNumber,
                "timeSinceLastEvent": workflowContext.timeSinceLastEvent,
                "contextHash": workflowContext.contextHash,
                "workflowPhase": workflowContext.workflowPhase
            ]
        ]

        // Add optional workflow analysis fields
        if let dominantCategory {
            dict["dominantCategory"] = dominantCategory
        }

        return dict
    }
}
