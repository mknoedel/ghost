import SelectionTapLib
import Foundation

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
    let enableWindowTracking = args.contains("--window-tracking")
    let enableBrowserTracking = args.contains("--browser-tracking")
    let enableSystemMetrics = args.contains("--system-metrics")
    let enableUserActivity = args.contains("--user-activity")
    
    return ActivityTrackerConfig(
        enableTextSelection: enableTextSelection,
        enableFocusTracking: enableFocusTracking,
        enableWindowTracking: enableWindowTracking,
        enableBrowserTracking: enableBrowserTracking,
        enableSystemMetrics: enableSystemMetrics,
        enableUserActivity: enableUserActivity
    )
}

// Show help information
func showHelp() {
    print("""
    SelectionTap - Configurable macOS Activity Monitor
    
    Usage: SelectionTap [options]
    
    Options:
      --comprehensive      Enable all tracking features
      --window-tracking    Enable window title, position, and size tracking
      --browser-tracking   Enable URL and tab information for browsers
      --system-metrics     Enable system resource and battery monitoring
      --user-activity      Enable user activity pattern tracking
      --focus-only         Disable text selection, focus tracking only
      --help              Show this help message
    
    Default: Text selection and focus tracking with structured events
    """)
}

// Main execution
if CommandLine.arguments.contains("--help") {
    showHelp()
    exit(0)
}

let config = parseConfig()
runActivityTracker(config: config)
