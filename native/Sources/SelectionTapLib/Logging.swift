// Logging.swift – Activity Tracker Logging Utilities
// -------------------------------------------------------------
// Provides efficient, lightweight logging for the activity
// tracker with configurable log levels and performance-optimized
// output formatting.
// -------------------------------------------------------------

import Foundation

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
