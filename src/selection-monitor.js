const crypto = require('crypto');
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
  }

  async start() {
    if (this.isRunning) {
      this.logger.info('Already running');
      return;
    }

    this.logger.info('Starting both Swift binary and AppleScript monitoring...');

    // Start both Swift binary and AppleScript simultaneously
    const swiftPromise = this.startSwiftBinary();
    const appleScriptPromise = this.startAppleScript();

    // Wait for both to complete initialization
    const [swiftSuccess, appleScriptSuccess] = await Promise.all([
      swiftPromise,
      appleScriptPromise
    ]);

    // Check results and update status
    if (swiftSuccess || appleScriptSuccess) {
      this.isRunning = true;

      if (swiftSuccess && appleScriptSuccess) {
        this.logger.success('Started both Swift binary and AppleScript monitoring');
      } else if (swiftSuccess) {
        this.logger.success('Started Swift binary monitoring (AppleScript failed)');
      } else {
        this.logger.success('Started AppleScript monitoring (Swift binary failed)');
      }
    } else {
      this.logger.warn('All monitoring strategies failed, manual mode only');
    }
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

    // Reset fallback state
    this.fallbackStarted = false;
    this.restrictedApps.clear();

    this.isRunning = false;
    this.logger.info('Stopped');
  }

  async startSwiftBinary() {
    try {
      const success = await liveSel.startLiveWatcher(this.onSelection, data => {
        // Handle status messages from Swift binary
        if (data.app?.requiresFallback) {
          const appName =
            data.app.name ||
            data.app.bundleIdentifier ||
            data.app.executableURL ||
            `unknown-${this._hashObject(data.app)}`;

          // Cache this app as restricted
          this.restrictedApps.add(appName);
          this.logger.debug(`Swift binary limitation detected for ${appName}`);
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

  _hashObject(obj) {
    return crypto.createHash('md5').update(JSON.stringify(obj)).digest('hex').slice(0, 8);
  }
}

module.exports = SelectionMonitor;
