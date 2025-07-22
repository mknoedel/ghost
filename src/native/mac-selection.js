const { spawn } = require('child_process');
const { clipboard, screen } = require('electron');

class MacSelectionWatcher {
  constructor() {
    this.isWatching = false;
    this.watchInterval = null;
    this.lastSelection = '';
    this.checkCount = 0;
  }

  checkAccessibilityPermissions() {
    return new Promise((resolve) => {
      // Simple accessibility check
      const script = `tell application "System Events" to get name of first process`;
      
      const osascript = spawn('osascript', ['-e', script]);
      let hasOutput = false;
      
      osascript.stdout.on('data', () => {
        hasOutput = true;
      });
      
      osascript.on('close', () => {
        resolve(hasOutput);
      });
      
      osascript.on('error', () => {
        resolve(false);
      });
    });
  }

  async requestAccessibilityPermissions() {
    const script = `display dialog "Ghost needs Accessibility permissions to detect text selection automatically.

1. Click 'Open System Preferences' below
2. Click the lock icon and enter your password  
3. Find 'Ghost' in the list and check the box
4. Restart Ghost

Or choose 'Manual Only' to use Cmd+Shift+G hotkey only." buttons {"Manual Only", "Open System Preferences"} default button "Open System Preferences"

if button returned of result is "Open System Preferences" then
  tell application "System Preferences"
    activate
    set current pane to pane "com.apple.preference.security"
  end tell
  return "granted"
else
  return "manual"
end if`;

    return new Promise((resolve) => {
      const osascript = spawn('osascript', ['-e', script]);
      let output = '';
      
      osascript.stdout.on('data', (data) => {
        output += data.toString();
      });
      
      osascript.on('close', () => {
        resolve(output.trim());
      });
      
      osascript.on('error', () => {
        resolve('manual');
      });
    });
  }

  async startWatching(callback) {
    if (this.isWatching) return true;

    console.log('[macOS] Checking accessibility permissions...');
    
    const hasPermissions = await this.checkAccessibilityPermissions();
    console.log('[macOS] Has permissions:', hasPermissions);
    
    if (!hasPermissions) {
      console.log('[macOS] Requesting permissions...');
      const result = await this.requestAccessibilityPermissions();
      
      if (result === 'manual') {
        console.log('[macOS] User chose manual mode');
        return false;
      }
      
      // Check again after user setup
      const hasPermissionsNow = await this.checkAccessibilityPermissions();
      if (!hasPermissionsNow) {
        console.log('[macOS] Still no permissions, falling back to manual');
        return false;
      }
    }

    // Start the simple watcher
    this.startSimpleWatcher(callback);
    this.isWatching = true;
    console.log('[macOS] Selection watcher started successfully');
    return true;
  }

  startSimpleWatcher(callback) {
    this.watchInterval = setInterval(async () => {
      this.checkCount++;
      
      // Only check every 4th cycle (every ~3 seconds) to be respectful
      if (this.checkCount % 4 !== 0) return;
      
      console.log(`[macOS] Checking for selection... (${this.checkCount})`);
      
      try {
        const selectedText = await this.getSelection();
        
        if (selectedText && 
            selectedText.length > 0 && 
            selectedText !== this.lastSelection &&
            selectedText.toLowerCase().includes('a')) {
          
          console.log(`[macOS] ✅ Selection detected: "${selectedText.slice(0, 50)}${selectedText.length > 50 ? '...' : ''}"`);
          
          this.lastSelection = selectedText;
          const cursor = screen.getCursorScreenPoint();
          
          callback(selectedText, {
            x: cursor.x,
            y: cursor.y,
            width: 0,
            height: 0
          });
        } else if (selectedText) {
          console.log(`[macOS] Selection found but filtered: "${selectedText.slice(0, 30)}" (no 'a' or duplicate)`);
        } else {
          console.log('[macOS] No selection detected');
        }
      } catch (error) {
        console.log('[macOS] Selection check error:', error.message);
      }
    }, 750); // Check every 750ms
  }

  async getSelection() {
    return new Promise((resolve) => {
      // Ultra-simple AppleScript - no app filtering, just try to get selection
      const script = `
        try
          set savedClip to the clipboard
          
          tell application "System Events"
            key code 8 using command down
          end tell
          
          delay 0.1
          
          set newClip to the clipboard
          set the clipboard to savedClip
          
          if newClip is not equal to savedClip then
            return newClip
          else
            return ""
          end if
        on error e
          return ""
        end try
      `;

      console.log('[macOS] Running selection script...');
      
      const osascript = spawn('osascript', ['-e', script]);
      let output = '';
      let stderr = '';

      osascript.stdout.on('data', (data) => {
        output += data.toString();
      });

      osascript.stderr.on('data', (data) => {
        stderr += data.toString();
      });

      osascript.on('close', (code) => {
        console.log(`[macOS] Script finished (code: ${code})`);
        console.log(`[macOS] Output: "${output.trim()}"`);
        if (stderr) console.log(`[macOS] Errors: ${stderr.trim()}`);
        
        const text = output.trim();
        resolve(text || null);
      });

      osascript.on('error', (err) => {
        console.log('[macOS] Script spawn error:', err.message);
        resolve(null);
      });
    });
  }

  stopWatching() {
    if (this.watchInterval) {
      clearInterval(this.watchInterval);
      this.watchInterval = null;
    }
    
    this.isWatching = false;
    this.lastSelection = '';
    this.checkCount = 0;
    console.log('[macOS] Selection watcher stopped');
  }
}

let watcherInstance = null;

function startWatching(callback) {
  if (!watcherInstance) {
    watcherInstance = new MacSelectionWatcher();
  }
  return watcherInstance.startWatching(callback);
}

function stopWatching() {
  if (watcherInstance) {
    watcherInstance.stopWatching();
    watcherInstance = null;
  }
}

function checkAccessibilityPermissions() {
  if (!watcherInstance) {
    watcherInstance = new MacSelectionWatcher();
  }
  return watcherInstance.checkAccessibilityPermissions();
}

module.exports = {
  startWatching,
  stopWatching,
  checkAccessibilityPermissions
};