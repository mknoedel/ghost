const { globalShortcut } = require('electron');
const nut = require('@nut-tree-fork/nut-js');
const { keyboard: nutKeyboard, Key: nutKey } = nut;
const liveSel = require('./mac-live-selection');
const macSelection = require('./mac-selection');
const Logger = require('./logger');
const { isValidSelection } = require('./selection-utils');

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

    // Always register manual trigger hotkey
    this.registerManualTrigger();
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

    // Unregister hotkey
    globalShortcut.unregister('CommandOrControl+Shift+G');
    
    // Reset fallback state
    this.fallbackStarted = false;
    this.restrictedApps.clear();
    
    this.isRunning = false;
    this.logger.info('Stopped');
  }

  registerManualTrigger() {
    try {
      globalShortcut.register('CommandOrControl+Shift+G', () => {
        this.logger.debug('Manual trigger activated');
        this.handleManualTrigger();
      });
      this.logger.success('Manual hotkey (Cmd/Ctrl+Shift+G) registered');
    } catch (error) {
      this.logger.error('Failed to register manual trigger:', error.message);
    }
  }

  async handleManualTrigger() {
    try {
      const { clipboard, screen } = require('electron');
      
      // Preserve original clipboard
      const originalClipboard = clipboard.readText();

      // Send copy command
      const mod = process.platform === 'darwin' ? nutKey.LeftMeta : nutKey.LeftControl;
      await nutKeyboard.pressKey(mod, nutKey.C);
      await nutKeyboard.releaseKey(mod, nutKey.C);

      // Wait for clipboard to update
      await new Promise(resolve => setTimeout(resolve, 120));

      const copiedText = clipboard.readText() || '';
      
      // Restore original clipboard
      clipboard.writeText(originalClipboard);

      // Validate copied text
      if (isValidSelection(copiedText)) {
        this.logger.debug(`Manual trigger text: "${copiedText.slice(0, 30)}${copiedText.length > 30 ? '...' : ''}"`);
        
        const cursor = screen.getCursorScreenPoint();
        this.onSelection({
          text: copiedText,
          x: cursor.x,
          y: cursor.y,
          timestamp: Date.now()
        });
      } else {
        this.logger.debug(`Manual trigger: invalid text (${copiedText.length} chars, contains 'a': ${copiedText.toLowerCase().includes('a')})`);
      }

    } catch (error) {
      this.logger.error('Manual trigger failed:', error.message);
    }
  }

  async startSwiftBinary() {
    try {
      const success = await liveSel.startLiveWatcher(this.onSelection, (statusData) => {
        // Handle status messages from Swift binary for runtime fallback
        if (statusData.status === 'isolated' || statusData.status === 'fallback_needed') {
          const appName = statusData.appName || 'unknown';
          
          // Cache this app as restricted
          this.restrictedApps.add(appName);
          this.logger.debug(`Swift binary limitation detected for ${appName}, starting AppleScript fallback...`);
          
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