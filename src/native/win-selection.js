const { spawn, exec } = require('child_process');
const { EventEmitter } = require('events');

class WindowsSelectionWatcher extends EventEmitter {
  constructor() {
    super();
    this.isWatching = false;
    this.watchInterval = null;
    this.lastSelection = '';
  }

  async startWatching(callback) {
    if (this.isWatching) return true;

    try {
      // Check if PowerShell is available and UIAutomation is supported
      const hasUIAutomation = await this.checkUIAutomationSupport();
      
      if (hasUIAutomation) {
        this.startPowerShellWatcher(callback);
      } else {
        this.startFallbackWatcher(callback);
      }
      
      this.isWatching = true;
      console.log('Windows text selection watcher started');
      return true;
    } catch (error) {
      console.error('Failed to start Windows selection watcher:', error);
      return false;
    }
  }

  checkUIAutomationSupport() {
    return new Promise((resolve) => {
      // Check if UIAutomation is available via PowerShell
      const script = `
        try {
          Add-Type -AssemblyName UIAutomationClient
          $automation = [System.Windows.Automation.Automation]::GetAutomation()
          if ($automation) {
            Write-Output "true"
          } else {
            Write-Output "false"
          }
        } catch {
          Write-Output "false"
        }
      `;

      const powershell = spawn('powershell', ['-Command', script]);
      let output = '';

      powershell.stdout.on('data', (data) => {
        output += data.toString();
      });

      powershell.on('close', () => {
        resolve(output.trim() === 'true');
      });

      powershell.on('error', () => {
        resolve(false);
      });
    });
  }

  startPowerShellWatcher(callback) {
    // Use PowerShell with UIAutomation for more advanced selection detection
    const script = `
      Add-Type -AssemblyName UIAutomationClient
      Add-Type -AssemblyName System.Windows.Forms
      
      $lastSelection = ""
      
      while ($true) {
        try {
          # Get the focused element
          $automation = [System.Windows.Automation.Automation]::GetAutomation()
          $focusedElement = $automation.GetFocusedElement()
          
          if ($focusedElement) {
            # Try to get text pattern
            $textPattern = $null
            try {
              $textPattern = $focusedElement.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
            } catch {}
            
            if ($textPattern) {
              # Get selection
              $selections = $textPattern.GetSelection()
              if ($selections.Length -gt 0) {
                $selectedText = $selections[0].GetText(-1)
                
                if ($selectedText -and $selectedText -ne $lastSelection -and $selectedText.ToLower().Contains("a")) {
                  $lastSelection = $selectedText
                  
                  # Get cursor position
                  $cursorPos = [System.Windows.Forms.Cursor]::Position
                  
                  # Output result
                  Write-Output "$selectedText|$($cursorPos.X),$($cursorPos.Y)"
                }
              }
            }
          }
        } catch {
          # Silently handle errors
        }
        
        Start-Sleep -Milliseconds 400
      }
    `;

    // For now, use the simpler fallback approach as PowerShell UIAutomation can be complex
    this.startFallbackWatcher(callback);
  }

  startFallbackWatcher(callback) {
    // Use a combination of clipboard monitoring and Windows API calls via PowerShell
    this.watchInterval = setInterval(async () => {
      try {
        const selection = await this.getSelectedText();
        if (selection && selection.text && selection.text.toLowerCase().includes('a')) {
          if (selection.text !== this.lastSelection) {
            this.lastSelection = selection.text;
            callback(selection.text, selection.bounds);
          }
        }
      } catch (error) {
        // Silently handle errors
      }
    }, 400); // 400ms polling for Windows
  }

  async getSelectedText() {
    return new Promise((resolve) => {
      // Use PowerShell to safely copy selection and get cursor position
      const script = `
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        try {
          # Save current clipboard
          $originalClip = ""
          try {
            $originalClip = [System.Windows.Forms.Clipboard]::GetText()
          } catch {}
          
          # Send Ctrl+C to copy selection
          [System.Windows.Forms.SendKeys]::SendWait("^c")
          Start-Sleep -Milliseconds 50
          
          # Get new clipboard content
          $selectedText = ""
          try {
            $selectedText = [System.Windows.Forms.Clipboard]::GetText()
          } catch {}
          
          # Restore original clipboard
          try {
            if ($originalClip) {
              [System.Windows.Forms.Clipboard]::SetText($originalClip)
            }
          } catch {}
          
          # Get cursor position
          $cursorPos = [System.Windows.Forms.Cursor]::Position
          
          # Only output if we got something different
          if ($selectedText -and $selectedText -ne $originalClip) {
            Write-Output "$selectedText|$($cursorPos.X),$($cursorPos.Y)"
          } else {
            Write-Output ""
          }
        } catch {
          Write-Output ""
        }
      `;

      const powershell = spawn('powershell', ['-Command', script]);
      let output = '';

      powershell.stdout.on('data', (data) => {
        output += data.toString();
      });

      powershell.on('close', () => {
        const trimmed = output.trim();
        if (trimmed && trimmed !== '') {
          const parts = trimmed.split('|');
          if (parts.length === 2) {
            const [text, coords] = parts;
            const coordParts = coords.split(',');
            if (coordParts.length === 2) {
              const [x, y] = coordParts.map(Number);
              resolve({
                text: text,
                bounds: { x, y, width: 0, height: 0 }
              });
              return;
            }
          }
        }
        resolve(null);
      });

      powershell.on('error', () => {
        resolve(null);
      });
    });
  }

  // Alternative method using VBScript (for older systems)
  async getSelectedTextViaVBScript() {
    return new Promise((resolve) => {
      const vbScript = `
        Set objShell = CreateObject("WScript.Shell")
        Set objClip = CreateObject("htmlfile")
        
        ' Save current clipboard
        originalClip = objClip.parentWindow.clipboardData.getData("text")
        
        ' Send Ctrl+C
        objShell.SendKeys "^c"
        WScript.Sleep 50
        
        ' Get new clipboard content
        selectedText = objClip.parentWindow.clipboardData.getData("text")
        
        ' Restore clipboard
        objClip.parentWindow.clipboardData.setData "text", originalClip
        
        ' Get cursor position (simplified)
        Set objAPI = CreateObject("WbemScripting.SWbemLocator")
        Set objService = objAPI.ConnectServer(".", "root\\cimv2")
        Set colItems = objService.ExecQuery("SELECT * FROM Win32_PointingDevice")
        
        ' Output result
        If selectedText <> originalClip And Len(selectedText) > 0 Then
          WScript.Echo selectedText & "|" & "0,0"
        Else
          WScript.Echo ""
        End If
      `;

      // For simplicity, we'll stick with PowerShell approach
      resolve(null);
    });
  }

  stopWatching() {
    if (this.watchInterval) {
      clearInterval(this.watchInterval);
      this.watchInterval = null;
    }
    
    this.isWatching = false;
    this.lastSelection = '';
    console.log('Windows text selection watcher stopped');
  }
}

let watcherInstance = null;

function startWatching(callback) {
  if (!watcherInstance) {
    watcherInstance = new WindowsSelectionWatcher();
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