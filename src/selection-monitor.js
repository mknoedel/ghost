const { clipboard, screen, globalShortcut } = require('electron');
const nut = require('@nut-tree-fork/nut-js');
const { keyboard: nutKeyboard, Key: nutKey } = nut;

// Platform-specific native watchers
let nativeWatcher = null;
try {
  if (process.platform === 'darwin') {
    nativeWatcher = require('./native/mac-selection');
  } else if (process.platform === 'win32') {
    nativeWatcher = require('./native/win-selection');
  } else if (process.platform === 'linux') {
    nativeWatcher = require('./native/linux-selection');
  }
} catch (error) {
  console.warn('Native selection watcher not available:', error.message);
}

class SelectionMonitor {
  constructor(onSelectionCallback, pollMs = 150) {
    this.onSelection = onSelectionCallback;
    this.pollMs = pollMs;
    this.lastSelection = null;
    this.timer = null;
    this.usingNativeWatcher = false;
    this.lastBounds = null;
    this.debounceTimer = null;
    this.lastSelectionKey = null;
  }

  /* ───────────── lifecycle ───────────── */

  start() {
    if (this.timer || this.usingNativeWatcher) return; // already running

    // Try to start native watcher first
    if (nativeWatcher && this.tryStartNativeWatcher()) {
      this.usingNativeWatcher = true;
      console.log(`Selection monitor started using native watcher (${process.platform})`);
    } else {
      // Fallback strategies per platform
      if (process.platform === 'linux') {
        // On Linux, still try polling as final fallback
        this.timer = setInterval(() => this.check(), this.pollMs);
        console.log('Selection monitor started using clipboard polling (Linux fallback)');
      } else {
        console.log('Selection monitor started in manual trigger mode only');
      }
    }

    // Register manual fallback for all platforms
    globalShortcut.register('CommandOrControl+Shift+G', () =>
      this.handleManualTrigger()
    );
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    
    if (this.usingNativeWatcher && nativeWatcher) {
      try {
        nativeWatcher.stopWatching();
      } catch (error) {
        console.error('Error stopping native watcher:', error);
      }
      this.usingNativeWatcher = false;
    }
    
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    
    globalShortcut.unregister('CommandOrControl+Shift+G');
    console.log('Selection monitor stopped');
  }

  /* ───────────── native watcher ───────────── */

  tryStartNativeWatcher() {
    try {
      return nativeWatcher.startWatching((text, bounds) => {
        this.handleNativeSelection(text, bounds);
      });
    } catch (error) {
      console.error('Failed to start native watcher:', error);
      return false;
    }
  }

  handleNativeSelection(text, bounds) {
    if (!text || text.trim().length === 0) return;
    
    // Check if text contains 'a' (case insensitive)
    if (!text.toLowerCase().includes('a')) return;
    
    // Debounce rapid selections to prevent jitter
    this.debouncedFireCallback(text, bounds);
  }

  debouncedFireCallback(text, bounds) {
    // Clear existing debounce timer
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }
    
    // Check if this is a duplicate of recent selection
    const boundsKey = bounds ? `${Math.round(bounds.x/10)*10},${Math.round(bounds.y/10)*10}` : 'unknown';
    const selectionKey = `${text.slice(0, 50)}_${boundsKey}`;
    
    if (this.lastSelectionKey === selectionKey) {
      return; // Skip duplicate
    }
    
    this.debounceTimer = setTimeout(() => {
      this.lastSelectionKey = selectionKey;
      this.lastSelection = text;
      this.lastBounds = bounds;
      
      if (typeof this.onSelection === 'function') {
        this.onSelection({ 
          text, 
          x: bounds ? bounds.x : screen.getCursorScreenPoint().x,
          y: bounds ? bounds.y : screen.getCursorScreenPoint().y,
          timestamp: Date.now() 
        });
      }
    }, 250); // 250ms debounce
  }

  /* ───────────── passive poll ───────────── */

  check() {
    // On macOS & Linux Electron exposes a dedicated “selection” pasteboard
    // that updates when the user selects text *without* copying.
    const raw = (clipboard.readText('selection') || '').trim();

    console.log({lastSection: this.lastSelection, raw})

    if (raw === this.lastSelection) return; // nothing new

    // If we’ve got a genuinely new selection – remember it
    this.lastSelection = raw ?? this.lastSelection;

    // Only act if it contains an “a” (case‑insensitive)
    if (raw.toLowerCase().includes('a')) this.fireCallback(raw);
  }

  /* ───────────── manual fallback ───────────── */

  async handleManualTrigger() {
    const original = clipboard.readText();          // preserve user clipboard
    try {
      const mod = process.platform === 'darwin' ? nutKey.LeftMeta
                                                : nutKey.LeftControl;
      await nutKeyboard.pressKey(mod, nutKey.C);
      await nutKeyboard.releaseKey(mod, nutKey.C);

      await new Promise(r => setTimeout(r, 120));   // wait for clipboard

      const copied = (clipboard.readText() || '').trim();
      if (!copied || copied === this.lastSelection) return;
      this.lastSelection = copied;

      if (copied.toLowerCase().includes('a')) this.fireCallback(copied);
    } catch (err) {
      console.error('Manual trigger failed:', err);
    } finally {
      clipboard.writeText(original);                // put clipboard back
    }
  }

  /* ───────────── callback helper ───────────── */

  fireCallback(text) {
    if (typeof this.onSelection !== 'function') return;

    const { x, y } = screen.getCursorScreenPoint();
    this.onSelection({ text, x, y, timestamp: Date.now() });
  }

  /* ───────────── optional utility ───────────── */

  detectCurrentSelection() {
    return Promise.resolve(
      (clipboard.readText('selection') || '').trim()
    );
  }
}

module.exports = SelectionMonitor;
