import Foundation
import SelectionTapLib

// Parse command line arguments for configuration
func parseConfig() -> ActivityTrackerConfig {
    let args = CommandLine.arguments

    // Check for comprehensive mode
    if args.contains("--comprehensive") {
        return .comprehensive
    }

    // Build custom configuration
    let enableTextSelection = !args.contains("--focus-only")
    let enableFocusTracking = true
    let enableBrowserTracking = args.contains("--browser-tracking")

    return ActivityTrackerConfig(
        enableTextSelection: enableTextSelection,
        enableFocusTracking: enableFocusTracking,
        enableBrowserTracking: enableBrowserTracking
    )
}

// Show help information
func showHelp() {
    print("""
    SelectionTap - Configurable macOS Activity Monitor

    Usage: SelectionTap [options]

    Options:
      --comprehensive      Enable all tracking features
      --browser-tracking   Enable URL and tab information for browsers
      --focus-only         Disable text selection, focus tracking only
      --help              Show this help message

    Default: Text selection, focus tracking, and browser tracking with structured events
    """)
}

// Main execution
if CommandLine.arguments.contains("--help") {
    showHelp()
    exit(0)
}

let config = parseConfig()
runActivityTracker(config: config)
