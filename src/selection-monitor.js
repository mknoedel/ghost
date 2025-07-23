const { globalShortcut } = require('electron');
const nut = require('@nut-tree-fork/nut-js');
const { keyboard: nutKeyboard, Key: nutKey } = nut;
const { StrategyManager } = require('./selection-strategies');
const Logger = require('./logger');
const { isValidSelection } = require('./selection-utils');

class SelectionMonitor {
  constructor(onSelectionCallback) {
    this.onSelection = onSelectionCallback;
    this.isRunning = false;
    this.logger = new Logger('SelectionMonitor');
    this.strategyManager = new StrategyManager();
  }

  async start() {
    if (this.isRunning) {
      this.logger.info('Already running');
      return;
    }

    this.logger.info('Starting...');

    // Try to start selection monitoring strategies
    const success = await this.strategyManager.start(this.onSelection);
    if (success) {
      this.isRunning = true;
      this.logger.success(`Started with ${this.strategyManager.getActiveStrategy()} strategy`);
    } else {
      this.logger.warn('No strategies available, manual mode only');
    }

    // Always register manual trigger hotkey as fallback
    this.registerManualTrigger();
  }

  stop() {
    if (!this.isRunning) return;

    this.logger.info('Stopping...');

    // Stop strategy manager
    this.strategyManager.stop();

    // Unregister hotkey
    globalShortcut.unregister('CommandOrControl+Shift+G');
    
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

}

module.exports = SelectionMonitor;