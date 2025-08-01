import ApplicationServices
import XCTest
@testable import SelectionTapLib

/// Test suite for SelectionTap ActivityTracker
/// Note: These tests focus on basic initialization and configuration
/// since accessibility testing requires special permissions and setup
final class SelectionTapTests: XCTestCase {
    override func setUpWithError() throws {
        // Setup code for each test
    }

    override func tearDownWithError() throws {
        // Cleanup code for each test
    }

    // MARK: - Configuration Tests

    func testActivityTrackerConfiguration() throws {
        // Test that ActivityTracker initializes with default config
        let tracker = ActivityTracker()
        XCTAssertNotNil(tracker, "ActivityTracker should initialize")
    }

    func testCustomConfiguration() throws {
        // Test custom configuration
        let config = ActivityTrackerConfig(
            enableTextSelection: true,
            enableFocusTracking: true,
            enableBrowserTracking: false,
            textCheckInterval: 0.5
        )
        let tracker = ActivityTracker(config: config)
        XCTAssertNotNil(tracker, "ActivityTracker should initialize with custom config")
    }

    // MARK: - Idle Detection Tests

    func testIdleDetection() throws {
        // Test idle detection logic
        let mouseIdleTime = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .mouseMoved
        )
        let keyIdleTime = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .keyDown
        )

        // Idle times should be non-negative
        XCTAssertGreaterThanOrEqual(
            mouseIdleTime,
            0,
            "Mouse idle time should be non-negative"
        )
        XCTAssertGreaterThanOrEqual(
            keyIdleTime,
            0,
            "Key idle time should be non-negative"
        )
    }
}
