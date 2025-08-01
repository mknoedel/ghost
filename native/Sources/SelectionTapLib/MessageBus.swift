// MessageBus.swift – Event Processing and Emission System
// -------------------------------------------------------------
// Provides a clean, decoupled message bus architecture for
// processing and emitting different types of activity events.
// -------------------------------------------------------------

import Foundation

// MARK: - Message Bus Protocol

public protocol MessageBus {
    func emit(_ event: ActivityEvent)
    func addFilter(_ filter: EventFilter)
    func addProcessor(_ processor: EventProcessor)
}

// MARK: - Event Filter Protocol

public protocol EventFilter {
    func shouldEmit(_ event: ActivityEvent) -> Bool
    var priority: Int { get } // Higher numbers = higher priority
}

// MARK: - Event Processor Protocol

public protocol EventProcessor {
    func process(_ event: ActivityEvent) -> ActivityEvent?
    var eventTypes: [EventType] { get } // Which event types this processor handles
}

// MARK: - Standard Message Bus Implementation

public class StandardMessageBus: MessageBus {
    private var filters: [EventFilter] = []
    private var processors: [EventProcessor] = []
    private let outputHandler: (ActivityEvent) -> Void

    public init(outputHandler: @escaping (ActivityEvent) -> Void) {
        self.outputHandler = outputHandler
        setupDefaultFilters()
        setupDefaultProcessors()
    }

    public func emit(_ event: ActivityEvent) {
        // Step 1: Process the event through processors
        var processedEvent = event
        for processor in processors.filter({ $0.eventTypes.contains(event.eventType) }) {
            if let newEvent = processor.process(processedEvent) {
                processedEvent = newEvent
            }
        }

        // Step 2: Apply filters (sorted by priority)
        let sortedFilters = filters.sorted { $0.priority > $1.priority }
        for filter in sortedFilters {
            if !filter.shouldEmit(processedEvent) {
                return // Event filtered out
            }
        }

        // Step 3: Emit the event
        outputHandler(processedEvent)
    }

    public func addFilter(_ filter: EventFilter) {
        filters.append(filter)
    }

    public func addProcessor(_ processor: EventProcessor) {
        processors.append(processor)
    }

    private func setupDefaultFilters() {
        // Add rate limiting filter
        addFilter(RateLimitFilter())

        // Add duplicate event filter
        addFilter(DuplicateEventFilter())

        // Add minimum data quality filter
        addFilter(DataQualityFilter())
    }

    private func setupDefaultProcessors() {
        // Add event enrichment processor
        addProcessor(EventEnrichmentProcessor())

        // Add session tracking processor
        addProcessor(SessionTrackingProcessor())
    }
}

// MARK: - Standard Filters

public class RateLimitFilter: EventFilter {
    public let priority = 100
    private var lastEmissionTimes: [EventType: Date] = [:]
    private let minIntervals: [EventType: TimeInterval] = [
        .heartbeat: 5.0, // Max once per 5 seconds
        .focusChange: 0.1, // Immediate
        .textSelection: 0.1, // Immediate
        .browserNavigation: 0.5 // Max twice per second
    ]

    public func shouldEmit(_ event: ActivityEvent) -> Bool {
        let now = Date()
        let eventType = event.eventType

        if
            let lastTime = lastEmissionTimes[eventType],
            let minInterval = minIntervals[eventType] {
            if now.timeIntervalSince(lastTime) < minInterval {
                return false // Rate limited
            }
        }

        lastEmissionTimes[eventType] = now
        return true
    }
}

public class DuplicateEventFilter: EventFilter {
    public let priority = 90
    private var lastEvents: [EventType: String] = [:]

    public func shouldEmit(_ event: ActivityEvent) -> Bool {
        let eventHash = createEventHash(event)
        let eventType = event.eventType

        if let lastHash = lastEvents[eventType], lastHash == eventHash {
            return false // Duplicate event
        }

        lastEvents[eventType] = eventHash
        return true
    }

    private func createEventHash(_ event: ActivityEvent) -> String {
        // Create a simple hash based on key properties
        switch event {
        case let focusEvent as FocusChangeEvent:
            return "focus_\(focusEvent.currentApp.bundleIdentifier)"
        case let textEvent as TextSelectionEvent:
            return "text_\(textEvent.text.prefix(50).hashValue)"
        case let browserEvent as BrowserNavigationEvent:
            // For browser events, include timestamp to allow focus-change events
            // even when navigating to the same page/tab
            let identifier = !browserEvent.currentURL.isEmpty ?
                browserEvent.currentURL :
                (browserEvent.pageTitle ?? "untitled")
            // Include seconds timestamp to allow multiple focuses per second but dedupe
            // rapid duplicates
            return "browser_\(browserEvent.app.bundleIdentifier)_\(identifier.hashValue)_\(browserEvent.timestamp / 1000)"
        default:
            return "\(event.eventType.rawValue)_\(event.timestamp)"
        }
    }
}

public class DataQualityFilter: EventFilter {
    public let priority = 80

    public func shouldEmit(_ event: ActivityEvent) -> Bool {
        // Basic data quality checks
        switch event {
        case let textEvent as TextSelectionEvent:
            return !textEvent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let browserEvent as BrowserNavigationEvent:
            // Allow events with either valid URL or valid page title
            let hasValidURL = !browserEvent.currentURL
                .isEmpty && URL(string: browserEvent.currentURL) != nil
            let hasValidTitle = browserEvent.pageTitle != nil && !browserEvent.pageTitle!
                .isEmpty
            return hasValidURL || hasValidTitle
        default:
            return true
        }
    }
}

// MARK: - Standard Processors

public class EventEnrichmentProcessor: EventProcessor {
    public let eventTypes: [EventType] = EventType.allCases

    public func process(_ event: ActivityEvent) -> ActivityEvent? {
        // Add common enrichment data to all events
        // This is where you could add session IDs, user context, etc.
        event // For now, just pass through
    }
}

public class SessionTrackingProcessor: EventProcessor {
    public let eventTypes: [EventType] = [.focusChange, .heartbeat]
    private var sessionStarts: [String: Date] = [:]

    public func process(_ event: ActivityEvent) -> ActivityEvent? {
        switch event {
        case let focusEvent as FocusChangeEvent:
            let bundleId = focusEvent.currentApp.bundleIdentifier
            if sessionStarts[bundleId] == nil {
                sessionStarts[bundleId] = Date()
            }
            return focusEvent
        case let heartbeatEvent as HeartbeatEvent:
            // Update session durations
            let bundleId = heartbeatEvent.app.bundleIdentifier
            if let startTime = sessionStarts[bundleId] {
                let duration = Date().timeIntervalSince(startTime)
                // Create a new heartbeat event with updated session duration
                let newHeartbeat = HeartbeatEvent(
                    timestamp: heartbeatEvent.timestamp,
                    mousePosition: heartbeatEvent.mousePosition,
                    workflowContext: heartbeatEvent.workflowContext,
                    app: heartbeatEvent.app,
                    sessionDuration: duration,
                    activeSessions: heartbeatEvent.activeSessions,
                    dominantCategory: heartbeatEvent.dominantCategory
                )
                return newHeartbeat
            }
            return heartbeatEvent
        default:
            return event
        }
    }
}

// MARK: - JSON Output Handler

public class JSONOutputHandler {
    public static func handle(_ event: ActivityEvent) {
        let dictionary = event.toDictionary()

        if
            let jsonData = try? JSONSerialization.data(
                withJSONObject: dictionary,
                options: []
            ),
            let jsonString = String(data: jsonData, encoding: .utf8) {
            fputs(jsonString + "\n", stdout)
            fflush(stdout)
        }
    }
}

// MARK: - Convenience Factory

public class MessageBusFactory {
    public static func createStandardBus() -> MessageBus {
        StandardMessageBus(outputHandler: JSONOutputHandler.handle)
    }

    public static func createCustomBus(outputHandler: @escaping (ActivityEvent) -> Void)
        -> MessageBus {
        StandardMessageBus(outputHandler: outputHandler)
    }
}
