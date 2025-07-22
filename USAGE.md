# Ghost Usage Guide

## Getting Started

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Run Ghost:**
   ```bash
   npm run dev    # Development mode (shows main window)
   npm start      # Production mode (background only)
   ```

## How to Use

### Method 1: Automatic Detection (Recommended)
1. Select any text containing the letter "a" in any application
2. Ghost will automatically detect the selection and show the popup
3. Click on any action button to perform the desired operation

### Method 2: Manual Trigger
1. Select text in any application
2. Press `Cmd+Shift+G` (macOS) or `Ctrl+Shift+G` (Windows/Linux)
3. The Ghost popup will appear with available actions

## Available Actions

### Text Operations
- **📋 Copy**: Copy selected text to clipboard
- **📝 UPPER**: Convert text to UPPERCASE and copy
- **📝 lower**: Convert text to lowercase and copy
- **📝 Title**: Convert text to Title Case and copy

### Web Integration
- **🔍 Google**: Search selected text on Google
- **🌐 Translate**: Translate text using Google Translate
- **📱 QR Code**: Generate QR code for selected text

### Utilities
- **🔢 Count**: Count words and characters, copy result

## Supported Applications

Ghost works across all applications including:
- **Web Browsers** (Chrome, Safari, Firefox, Edge)
- **Communication Apps** (WhatsApp Web, Slack, Discord, Messenger)
- **Text Editors** (VSCode, Sublime Text, Notepad++)
- **Office Applications** (Word, Pages, Google Docs)
- **System Applications** (Finder, Terminal, etc.)

## Keyboard Shortcuts

- `Cmd+Shift+G` / `Ctrl+Shift+G`: Manually trigger popup
- `Escape`: Close popup window

## Tips

1. **Automatic Detection**: Ghost monitors your clipboard for text selections. Simply select text containing the letter "a" and wait a moment for the popup to appear.

2. **Quick Actions**: The popup appears near your cursor for quick access to actions.

3. **Auto-Close**: The popup automatically closes after 5 seconds of inactivity or when you click outside it.

4. **Cross-Platform**: Ghost works on macOS, Windows, and Linux.

## Troubleshooting

**Popup doesn't appear?**
- Try using the manual trigger (`Cmd+Shift+G`)
- Ensure Ghost is running in the background
- Check that you have selected text (not just clicked)

**Actions not working?**
- Ensure you have an internet connection for web-based actions
- Check that the selected text is not empty

**Performance issues?**
- Ghost runs efficiently in the background with minimal resource usage
- Restart the application if you experience any issues