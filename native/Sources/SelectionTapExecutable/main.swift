import SelectionTapLib
import Foundation

// Parse command line arguments for configuration
func parseConfig() -> DataCollectorConfig {
    let args = CommandLine.arguments
    
    // Check for comprehensive mode
    if args.contains("--comprehensive") {
        return .comprehensive
    }
    
    // Check for custom configuration flags
    var config = DataCollectorConfig.default
    
    if args.contains("--window-context") {
        config = DataCollectorConfig(
            textSelection: config.textSelection,
            focusTracking: config.focusTracking,
            windowContext: true,
            browserData: config.browserData,
            systemMetrics: config.systemMetrics,
            inputPatterns: config.inputPatterns,
            timeContext: config.timeContext
        )
    }
    
    if args.contains("--browser-data") {
        config = DataCollectorConfig(
            textSelection: config.textSelection,
            focusTracking: config.focusTracking,
            windowContext: config.windowContext,
            browserData: true,
            systemMetrics: config.systemMetrics,
            inputPatterns: config.inputPatterns,
            timeContext: config.timeContext
        )
    }
    
    if args.contains("--system-metrics") {
        config = DataCollectorConfig(
            textSelection: config.textSelection,
            focusTracking: config.focusTracking,
            windowContext: config.windowContext,
            browserData: config.browserData,
            systemMetrics: true,
            inputPatterns: config.inputPatterns,
            timeContext: config.timeContext
        )
    }
    
    if args.contains("--time-context") {
        config = DataCollectorConfig(
            textSelection: config.textSelection,
            focusTracking: config.focusTracking,
            windowContext: config.windowContext,
            browserData: config.browserData,
            systemMetrics: config.systemMetrics,
            inputPatterns: config.inputPatterns,
            timeContext: true
        )
    }
    
    return config
}

// Show help information
func showHelp() {
    print("""
    SelectionTap - Configurable macOS Activity Monitor
    
    Usage: SelectionTap [options]
    
    Options:
      --comprehensive      Enable all data collectors
      --window-context     Enable window title, position, and size tracking
      --browser-data       Enable URL and tab information for browsers
      --system-metrics     Enable system resource and battery monitoring
      --time-context       Enable time-of-day and temporal analysis
      --help              Show this help message
    
    Default: Text selection and focus tracking only
    """)
}

// Main execution
if CommandLine.arguments.contains("--help") {
    showHelp()
    exit(0)
}

let config = parseConfig()
runSelectionTap(config: config)
