const { spawn } = require('child_process');
const { screen } = require('electron');

class MacSelectionWatcher {
  constructor() {
    this.isWatching = false;
    this.checkInterval = null;
    this.lastSelection = '';
    this.callback = null;
  }

  async startWatching(callback) {
    if (this.isWatching) {
      console.log('[MacSelection] Already watching');
      return true;
    }

    this.callback = callback;

    console.log('[MacSelection] Checking accessibility permissions...');
    const hasPermissions = await this.checkAccessibilityPermissions();
    
    if (!hasPermissions) {
      console.log('[MacSelection] No accessibility permissions');
      const userChoice = await this.requestPermissions();
      
      if (userChoice === 'manual') {
        console.log('[MacSelection] User chose manual mode');
        return false;
      }
      
      // Check again after user setup
      const hasPermissionsNow = await this.checkAccessibilityPermissions();
      if (!hasPermissionsNow) {
        console.log('[MacSelection] Still no permissions');
        return false;
      }
    }

    // Start checking for selections every 3 seconds
    this.checkInterval = setInterval(() => this.checkForSelection(), 3000);
    this.isWatching = true;
    
    console.log('[MacSelection] ✅ Started watching (checks every 3 seconds)');
    return true;
  }

  stopWatching() {
    if (!this.isWatching) return;

    if (this.checkInterval) {
      clearInterval(this.checkInterval);
      this.checkInterval = null;
    }
    
    this.isWatching = false;
    this.callback = null;
    this.lastSelection = '';
    
    console.log('[MacSelection] Stopped watching');
  }

  async checkForSelection() {
    try {
      console.log('[MacSelection] Checking for text selection...');
      
      const selectedText = await this.getSelectedText();
      
      if (selectedText && 
          selectedText.length > 0 && 
          selectedText !== this.lastSelection &&
          selectedText.toLowerCase().includes('a')) {
        
        console.log(`[MacSelection] ✅ Found: "${selectedText.slice(0, 50)}${selectedText.length > 50 ? '...' : ''}"`);
        
        this.lastSelection = selectedText;
        const cursor = screen.getCursorScreenPoint();
        
        if (this.callback) {
          this.callback({
            text: selectedText,
            x: cursor.x,
            y: cursor.y,
            timestamp: Date.now()
          });
        }
        
      } else if (selectedText) {
        console.log(`[MacSelection] Filtered: "${selectedText.slice(0, 30)}" (duplicate or no 'a')`);
      } else {
        console.log('[MacSelection] No selection found');
      }
      
    } catch (error) {
      console.log('[MacSelection] Check failed:', error.message);
    }
  }

  async getSelectedText() {
    return new Promise((resolve) => {
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
        on error
          return ""
        end try
      `;

      const osascript = spawn('osascript', ['-e', script]);
      let output = '';

      osascript.stdout.on('data', (data) => {
        output += data.toString();
      });

      osascript.on('close', () => {
        const text = output.trim();
        resolve(text || null);
      });

      osascript.on('error', () => {
        resolve(null);
      });
    });
  }

  checkAccessibilityPermissions() {
    return new Promise((resolve) => {
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

  async requestPermissions() {
    const script = `display dialog "Ghost can detect text selections automatically with Accessibility permissions.

Choose your preferred mode:" buttons {"Manual Hotkey Only", "Grant Permissions"} default button "Grant Permissions"

if button returned of result is "Grant Permissions" then
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
}

// Export simple interface
let watcher = null;

function startWatching(callback) {
  if (!watcher) {
    watcher = new MacSelectionWatcher();
  }
  return watcher.startWatching(callback);
}

function stopWatching() {
  if (watcher) {
    watcher.stopWatching();
    watcher = null;
  }
}

module.exports = {
  startWatching,
  stopWatching
};