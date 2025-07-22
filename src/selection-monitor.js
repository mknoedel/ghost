const { globalShortcut } = require('electron');
const nut = require('@nut-tree-fork/nut-js');
const { keyboard: nutKeyboard, Key: nutKey } = nut;

// Only macOS selection monitoring
const macSelection = require('./native/mac-selection');

class SelectionMonitor {
  constructor(onSelectionCallback) {
    this.onSelection = onSelectionCallback;
    this.isRunning = false;
  }

  start() {
    if (this.isRunning) {
      console.log('[SelectionMonitor] Already running');
      return;
    }

    console.log('[SelectionMonitor] Starting...');

    // Only try macOS selection monitoring
    if (process.platform === 'darwin') {
      console.log('[SelectionMonitor] Starting macOS selection watcher...');
      const started = macSelection.startWatching(this.onSelection);
      
      if (started) {
        this.isRunning = true;
        console.log('[SelectionMonitor] ✅ macOS selection watcher active');
      } else {
        console.log('[SelectionMonitor] ❌ macOS selection watcher failed, manual mode only');
      }
    } else {
      console.log(`[SelectionMonitor] Platform ${process.platform} not supported, manual mode only`);
    }

    // Always register manual trigger hotkey as fallback
    globalShortcut.register('CommandOrControl+Shift+G', () => {
      console.log('[SelectionMonitor] Manual trigger activated');
      this.handleManualTrigger();
    });

    console.log('[SelectionMonitor] Manual hotkey (Cmd/Ctrl+Shift+G) registered');
  }

  stop() {
    if (!this.isRunning) return;

    console.log('[SelectionMonitor] Stopping...');

    // Stop macOS watcher if running
    if (process.platform === 'darwin') {
      macSelection.stopWatching();
    }

    // Unregister hotkey
    globalShortcut.unregister('CommandOrControl+Shift+G');
    
    this.isRunning = false;
    console.log('[SelectionMonitor] Stopped');
  }

  async handleManualTrigger() {
    try {
      // Get current clipboard content to restore later
      const { clipboard } = require('electron');
      const originalClipboard = clipboard.readText();

      // Send copy command
      const mod = process.platform === 'darwin' ? nutKey.LeftMeta : nutKey.LeftControl;
      await nutKeyboard.pressKey(mod, nutKey.C);
      await nutKeyboard.releaseKey(mod, nutKey.C);

      // Wait for clipboard to update
      await new Promise(resolve => setTimeout(resolve, 120));

      // Get copied text
      const copiedText = clipboard.readText() || '';

      // Restore original clipboard
      clipboard.writeText(originalClipboard);

      // Check if we got valid text with 'a'
      if (copiedText.trim().length > 0 && copiedText.toLowerCase().includes('a')) {
        console.log(`[SelectionMonitor] Manual trigger: "${copiedText.slice(0, 30)}${copiedText.length > 30 ? '...' : ''}"`);
        
        const { screen } = require('electron');
        const cursor = screen.getCursorScreenPoint();
        
        this.onSelection({
          text: copiedText,
          x: cursor.x,
          y: cursor.y,
          timestamp: Date.now()
        });
      } else {
        console.log(`[SelectionMonitor] Manual trigger: no valid text (${copiedText.length} chars, contains 'a': ${copiedText.toLowerCase().includes('a')})`);
      }

    } catch (error) {
      console.error('[SelectionMonitor] Manual trigger failed:', error);
    }
  }
}

module.exports = SelectionMonitor;