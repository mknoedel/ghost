const { clipboard, screen, globalShortcut } = require('electron');
const nut = require('@nut-tree-fork/nut-js');
const { keyboard: nutKeyboard, Key: nutKey } = nut;

class SelectionMonitor {
  constructor(onSelectionCallback, pollMs = 150) {
    this.onSelection = onSelectionCallback;
    this.pollMs = pollMs;
    this.lastSelection = null;
    this.timer = null;
  }

  /* ───────────── lifecycle ───────────── */

  start() {
    if (this.timer) return;                          // already running
    this.timer = setInterval(() => this.check(), this.pollMs);

    // manual fallback: user hits ⌘/Ctrl‑Shift‑G → we copy, inspect, restore
    globalShortcut.register('CommandOrControl+Shift+G', () =>
      this.handleManualTrigger()
    );
    console.log('Selection monitor started');
  }

  stop() {
    if (!this.timer) return;
    clearInterval(this.timer);
    this.timer = null;
    globalShortcut.unregister('CommandOrControl+Shift+G');
    console.log('Selection monitor stopped');
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
