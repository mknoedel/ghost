const liveSel = require('./mac-live-selection');
const macSelection = require('./mac-selection');
const Logger = require('./logger');

class SelectionMonitor {
  constructor(onSelectionCallback) {
    this.onSelection = onSelectionCallback;
    this.isRunning = false;
    this.logger = new Logger('SelectionMonitor');
    this.swiftActive = false;
    this.appleScriptActive = false;
    this.restrictedApps = new Set();
    this.fallbackStarted = false;
  }

  async start() {
    if (this.isRunning) {
      this.logger.info('Already running');
      return;
    }

    this.logger.info('Starting...');

    // Try Swift binary first
    const swiftSuccess = await this.startSwiftBinary();
    if (swiftSuccess) {
      this.isRunning = true;
      this.logger.success('Started with Swift binary');
    } else {
      // Fallback to AppleScript if Swift completely fails
      this.logger.warn('Swift binary failed, falling back to AppleScript...');
      const appleScriptSuccess = await this.startAppleScript();
      if (appleScriptSuccess) {
        this.isRunning = true;
        this.logger.success('Started with AppleScript (fallback)');
      } else {
        this.logger.warn('All strategies failed, manual mode only');
      }
    }

    // Manual trigger removed
  }

  stop() {
    if (!this.isRunning) return;

    this.logger.info('Stopping...');

    // Stop Swift binary if active
    if (this.swiftActive) {
      liveSel.stopLiveWatcher();
      this.swiftActive = false;
    }

    // Stop AppleScript if active
    if (this.appleScriptActive) {
      macSelection.stopWatching();
      this.appleScriptActive = false;
    }

    // Manual trigger removed

    // Reset fallback state
    this.fallbackStarted = false;
    this.restrictedApps.clear();

    this.isRunning = false;
    this.logger.info('Stopped');
  }

  // Manual trigger functionality removed

  async startSwiftBinary() {
    try {
      const success = await liveSel.startLiveWatcher(this.onSelection, statusData => {
        // Handle status messages from Swift binary for runtime fallback
        if (statusData.status === 'isolated' || statusData.status === 'fallback_needed') {
          const appName = statusData.appName || 'unknown';

          // Cache this app as restricted
          this.restrictedApps.add(appName);
          this.logger.debug(
            `Swift binary limitation detected for ${appName}, starting AppleScript fallback...`
          );

          // Start AppleScript fallback if not already running
          if (!this.appleScriptActive && !this.fallbackStarted) {
            this.fallbackStarted = true;
            this.startAppleScript();
          }
        }
      });

      if (success) {
        this.swiftActive = true;
        return true;
      }
    } catch (error) {
      this.logger.error('Swift binary error:', error.message);
    }
    return false;
  }

  async startAppleScript() {
    try {
      const success = await macSelection.startWatching(this.onSelection);
      if (success) {
        this.appleScriptActive = true;
        this.logger.success('AppleScript polling active');
        return true;
      }
    } catch (error) {
      this.logger.error('AppleScript error:', error.message);
    }
    return false;
  }
}

module.exports = SelectionMonitor;
