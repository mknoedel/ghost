# 👻 Ghost

A cross-platform text selection popup tool inspired by PopClip, featuring native text selection monitoring for smooth, Grammarly-like performance.

## Features

- **Native Selection Monitoring**: Uses platform-specific APIs for real-time text selection detection
- **Universal Text Selection**: Works across all applications
- **Smart Positioning**: Popup appears near selected text, not at cursor
- **Debounced Updates**: Prevents popup jitter from rapid selection changes  
- **Cross-Platform**: Built with Electron for macOS, Windows, and Linux
- **Manual Trigger**: Fallback hotkey when native monitoring isn't available

## Quick Start

1. Install dependencies:
   ```bash
   npm install
   ```

2. Run in development mode:
   ```bash
   npm run dev
   ```

3. Build for production:
   ```bash
   npm run build
   ```

## System Requirements

### macOS
- **Accessibility Permission Required**: Grant Ghost access in `System Preferences > Security & Privacy > Privacy > Accessibility`
- The app will prompt for permission on first launch
- Uses AppleScript with System Events for reliable text selection monitoring
- Requires Python 3 (for cursor position detection)

### Windows  
- **PowerShell Required**: Windows 10/11 with PowerShell support
- Uses PowerShell with System.Windows.Forms for text selection monitoring
- May require "Enable UI Automation" in Windows accessibility settings
- Falls back to clipboard-based polling when PowerShell isn't available

### Linux
- **PRIMARY Selection Monitoring**: Uses `xclip` (X11) or `wl-paste` (Wayland)
- **Real-time Detection**: No polling, true event-driven selection monitoring
- **Auto-detects Display Server**: Automatically chooses X11 or Wayland tools
- **Dependencies**: Requires `xclip` (X11) or `wl-clipboard` (Wayland) packages
- **No Permissions**: No special permissions required

## Usage

1. **Automatic**: Simply select text containing the letter 'a' - the popup appears instantly
2. **Manual Trigger**: Press `Cmd+Shift+G` (macOS) or `Ctrl+Shift+G` (Windows/Linux) for manual selection
3. Choose from available actions in the popup

## Current Actions

- **Copy**: Copy selected text to clipboard
- **Google Search**: Search selected text on Google
- **Translate**: Translate selected text using Google Translate

## Development

The project structure:
- `src/main.js` - Electron main process and popup management
- `src/selection-monitor.js` - Unified selection monitoring with native watchers
- `src/native/mac-selection.js` - macOS Accessibility API integration
- `src/native/win-selection.js` - Windows UIAutomation integration
- `src/renderer/` - UI components and styles
- `package.json` - Dependencies and build configuration

## Architecture

- **Native Watchers**: Platform-specific selection monitoring
  - macOS: AppleScript + System Events (no native compilation required)
  - Windows: PowerShell + .NET Framework classes  
  - Linux: PRIMARY selection monitoring via `xclip`/`wl-paste` (true event-driven)
- **Selection Monitor**: Unified interface with automatic fallbacks
- **Popup Management**: Debounced, position-aware popup windows
- **Cross-Platform**: Graceful degradation from scripted → polling → manual modes

## Troubleshooting

### macOS: "Accessibility permission denied"
1. Open System Preferences > Security & Privacy > Privacy > Accessibility
2. Click the lock icon and enter your password
3. Find Ghost in the list and check the box
4. Restart the application

### Windows: Selection not detected
1. Check Windows Settings > Ease of Access > Interaction
2. Ensure UI Automation is enabled
3. Try running as administrator if issues persist

### Linux: Missing dependencies
```bash
# For X11 systems
sudo apt install xclip
# or
sudo dnf install xclip

# For Wayland systems  
sudo apt install wl-clipboard
# or
sudo dnf install wl-clipboard
```

### All Platforms: Manual trigger
If native selection monitoring fails, use `Cmd/Ctrl+Shift+G` to manually trigger text selection detection.

## Performance Notes

- **Linux**: True event-driven PRIMARY selection monitoring (no polling!)
- **macOS/Windows**: System scripting reduces polling frequency (150ms → 300-400ms intervals)  
- Debouncing prevents rapid popup creation/destruction  
- Smart duplicate detection reduces unnecessary updates
- No native compilation required - works out of the box
- Clipboard restoration preserves user workflow  
- Fallback modes ensure functionality across all environments