const { spawn } = require('child_process');
const { screen } = require('electron');

class LinuxSelectionWatcher {
  constructor() {
    this.proc = null;
    this.lastText = '';
    this.onSelection = null;
  }

  startWatching(callback) {
    if (this.proc) return true;

    this.onSelection = callback;

    const isWayland = process.env.XDG_SESSION_TYPE === 'wayland';
    const cmd = isWayland ? 'wl-paste' : 'xclip';
    const args = isWayland
      ? ['-p', '--watch', '--no-newline']
      : ['-selection', 'primary', '-o', '-loops', '0'];

    console.log(`[Ghost] Starting Linux PRIMARY watcher: ${cmd} ${args.join(' ')}`);
    console.log(`[Ghost] Detected session type: ${process.env.XDG_SESSION_TYPE || 'X11'}`);

    try {
      this.proc = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'ignore'] });
    } catch (err) {
      console.error(`[Ghost] Cannot launch ${cmd}:`, err);
      return false;
    }

    let buf = '';
    this.proc.stdout.on('data', data => {
      buf += data.toString();
      let nl;
      while ((nl = buf.indexOf('\n')) !== -1) {
        const txt = buf.slice(0, nl).trim();
        buf = buf.slice(nl + 1);
        
        // Skip empty or duplicate text
        if (!txt || txt === this.lastText) continue;
        
        this.lastText = txt;
        
        // Only trigger on text containing 'a' (case insensitive)
        if (!/a/i.test(txt)) continue;

        console.log(`[Ghost] PRIMARY selection detected: "${txt.slice(0, 50)}${txt.length > 50 ? '...' : ''}"`);

        // Get cursor position
        const cursor = screen.getCursorScreenPoint();
        
        // Trigger callback
        this.onSelection(txt, {
          x: cursor.x,
          y: cursor.y,
          width: 0,
          height: 0
        });
      }
    });

    this.proc.on('exit', (code) => {
      console.warn(`[Ghost] ${cmd} exited with code ${code}; watcher stopped.`);
      this.proc = null;
    });

    this.proc.on('error', (err) => {
      console.error(`[Ghost] ${cmd} process error:`, err);
      this.proc = null;
    });

    console.log(`[Ghost] Linux PRIMARY watcher started successfully`);
    return true;
  }

  stopWatching() {
    if (this.proc) {
      console.log('[Ghost] Stopping Linux PRIMARY watcher...');
      this.proc.kill();
      this.proc = null;
    }
    this.onSelection = null;
    this.lastText = '';
  }
}

// Export functions to match the interface expected by selection-monitor.js
let watcherInstance = null;

function startWatching(callback) {
  if (!watcherInstance) {
    watcherInstance = new LinuxSelectionWatcher();
  }
  return watcherInstance.startWatching(callback);
}

function stopWatching() {
  if (watcherInstance) {
    watcherInstance.stopWatching();
    watcherInstance = null;
  }
}

module.exports = {
  startWatching,
  stopWatching
};