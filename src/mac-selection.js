const { spawn } = require('child_process');
const path = require('path');
const { screen } = require('electron');
const Logger = require('./logger');
const { isValidSelection } = require('./selection-utils');

const SCRIPTS_DIR = path.join(__dirname, 'mac-scripts');

class MacSelectionWatcher {
  constructor() {
    this.isWatching = false;
    this.checkInterval = null;
    this.lastSelection = '';
    this.callback = null;
    this.logger = new Logger('MacSelection');
  }

  /* ---------- public API ---------- */

  async startWatching(callback) {
    if (this.isWatching) {
      this.logger.info('Already watching');
      return true;
    }

    this.callback = callback;
    this.logger.step('Checking accessibility permissions...');

    const hasPermissions = await this.checkAccessibilityPermissions();
    if (!hasPermissions) {
      this.logger.fail('No accessibility permissions');
      const choice = await this.requestPermissions();
      if (choice === 'manual') return false;
      if (!(await this.checkAccessibilityPermissions())) {
        this.logger.fail('Permissions still not granted');
        return false;
      }
    }

    this.checkInterval = setInterval(() => this.checkForSelection(), 2000);
    this.isWatching = true;
    this.logger.success('Started watching (2s interval)');
    return true;
  }

  stopWatching() {
    if (!this.isWatching) return;
    clearInterval(this.checkInterval);
    this.checkInterval = null;
    this.isWatching = false;
    this.callback = null;
    this.lastSelection = '';
    this.logger.info('Stopped watching');
  }

  /* ---------- internals ---------- */

  async checkForSelection() {
    try {
      const text = await this.getSelectedText();
      
      // Always hide popup on any selection change, even invalid ones
      if (text !== this.lastSelection) {
        // First, hide any existing popup
        this.callback?.({ hideOnly: true });
        
        // Then, only create a new popup if the selection is valid
        if (isValidSelection(text)) {
          this.lastSelection = text;
          const { x, y } = screen.getCursorScreenPoint();
          this.callback?.({ text, x, y, timestamp: Date.now() });
          this.logger.success(`"${text.slice(0, 50)}"`);
        } else {
          // Update lastSelection even for invalid selections to prevent repeated hide calls
          this.lastSelection = text;
        }
      }
    } catch (err) {
      this.logger.error('Error:', err.message);
    }
  }

  /* Runs external script instead of inline blob */
  async getSelectedText() {
    const scriptPath = path.join(SCRIPTS_DIR, 'get-selection.applescript');
    return this.runOsa(scriptPath);
  }

  /*  Proper AX trust check */
  async checkAccessibilityPermissions() {
    const scriptPath = path.join(SCRIPTS_DIR, 'check-ax-trusted.applescript');
    const result = await this.runOsa(scriptPath);
    return result.trim() === 'true';
  }

  /* shared helper */
  runOsa(scriptPath) {
    return new Promise((resolve) => {
      const proc = spawn('osascript', [scriptPath]);
  
      let out = '';
      let err = '';
  
      proc.stdout.on('data', (d) => (out += d));
      proc.stderr.on('data', (d) => (err += d));
  
      proc.on('close', (code) => {
        if (err) this.logger.debug('[osascript stderr] ' + err.trim());
        if (code !== 0) this.logger.warn('osascript exit code', code);
        resolve(out.trim());
      });
  
      proc.on('error', (e) => {
        this.logger.error('spawn error:', e.message);
        resolve('');
      });
    });
  }
  

  /* (unchanged) */
  async requestPermissions() {
    const script = `
      display dialog ¬
        "⚠️  Ghost needs the macOS *Accessibility* permission to read text selections without copying.\\n\\
        \\nHow to grant it now:\\n • Click “Open Settings”.\\n • In the window that appears, go to Privacy & Security → Accessibility.\\n • Unlock with your password, then enable the checkbox next to ‘Ghost’.\\n\\
        \\nIf you’d rather skip this, choose Manual Mode and use the ⌘‑⇧‑⌥‑C hotkey instead." ¬
        buttons {"Manual Mode", "Open Settings"} default button "Open Settings" with icon caution

      if button returned of result is "Open Settings" then
        tell application "System Settings"
          activate
          reveal anchor "Privacy_Accessibility" of pane id "com.apple.preference.security"
        end tell
        return "prompted"
      else
        return "manual"
      end if`;
    return this.runOsaInline(script);
  }

  runOsaInline(inline) {
    return new Promise((resolve) => {
      const proc = spawn('osascript', ['-e', inline]);
      let out = '';
      proc.stdout.on('data', (d) => (out += d));
      proc.on('close', () => resolve(out.trim()));
      proc.on('error', () => resolve(''));
    });
  }
}

/* ---------- module facade ---------- */

let watcher = null;
exports.startWatching = (cb) => {
  watcher ??= new MacSelectionWatcher();
  return watcher.startWatching(cb);
};
exports.stopWatching = () => {
  watcher?.stopWatching();
  watcher = null;
};
