# 👻 Ghost

A cross-platform text selection popup tool inspired by PopClip, designed to work seamlessly across web browsers, WhatsApp, Messenger, Slack, and other applications.

## Features

- **Universal Text Selection**: Works across all applications
- **Quick Actions**: Copy, search, translate, and more
- **Cross-Platform**: Built with Electron for macOS, Windows, and Linux
- **Extensible**: Easy to add new actions and integrations
- **Lightweight**: Minimal resource usage with background operation

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

## Usage

1. Select any text in any application
2. Press `Cmd+Shift+G` (macOS) or `Ctrl+Shift+G` (Windows/Linux)
3. Choose from available actions in the popup

## Current Actions

- **Copy**: Copy selected text to clipboard
- **Google Search**: Search selected text on Google
- **Translate**: Translate selected text using Google Translate

## Development

The project structure:
- `src/main.js` - Electron main process
- `src/renderer/` - UI components and styles
- `package.json` - Dependencies and build configuration

## Roadmap

- [ ] Automatic text selection detection (no keyboard shortcut needed)
- [ ] More built-in actions (dictionary, case conversion, etc.)
- [ ] Plugin system for custom actions
- [ ] Application-specific integrations
- [ ] Customizable UI themes