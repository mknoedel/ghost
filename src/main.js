const { app, BrowserWindow, globalShortcut, clipboard, ipcMain } = require('electron');
const path = require('path');
const SelectionMonitor = require('./selection-monitor');

let mainWindow;
let popupWindow;
let selectionMonitor;

function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 400,
    height: 300,
    show: false,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'main.html'));

  if (process.argv.includes('--dev')) {
    mainWindow.webContents.openDevTools();
    mainWindow.show();
  }
}

let lastPopupBounds = null;
let popupDebounceTimer = null;

function createPopupWindow(x, y, selectedText) {
  // Debounce popup creation to prevent jitter
  if (popupDebounceTimer) {
    clearTimeout(popupDebounceTimer);
  }

  const currentBounds = `${Math.round(x / 10) * 10},${Math.round(y / 10) * 10}`;

  // Skip if this is a duplicate position within debounce window
  if (lastPopupBounds === currentBounds) {
    return;
  }

  popupDebounceTimer = setTimeout(() => {
    createPopupWindowImmediate(x, y, selectedText);
    lastPopupBounds = currentBounds;
  }, 10); // 100ms debounce for popup creation
}

function hidePopupWindow() {
  if (popupWindow && !popupWindow.isDestroyed()) {
    popupWindow.close();
  }

  // Reset debounce timer and last bounds
  if (popupDebounceTimer) {
    clearTimeout(popupDebounceTimer);
    popupDebounceTimer = null;
  }
  lastPopupBounds = null;
}

function createPopupWindowImmediate(x, y, selectedText) {
  // Use the dedicated function to hide any existing popup
  hidePopupWindow();

  // Ensure popup stays within screen bounds
  const { screen } = require('electron');
  const display = screen.getDisplayNearestPoint({ x, y });
  const bounds = display.workArea;

  const popupWidth = 400;
  const popupHeight = 60;

  // Position popup near selection instead of using arbitrary offset
  const popupX = Math.max(
    bounds.x,
    Math.min(x - popupWidth / 2, bounds.x + bounds.width - popupWidth)
  );
  const popupY = Math.max(bounds.y, y - popupHeight - 10); // Small gap above selection

  popupWindow = new BrowserWindow({
    width: popupWidth,
    height: popupHeight,
    x: popupX,
    y: popupY,
    frame: false,
    alwaysOnTop: true,
    resizable: false,
    movable: false,
    skipTaskbar: true,
    transparent: true,
    focusable: false,
    show: false,
    acceptFirstMouse: false,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  popupWindow.loadFile(path.join(__dirname, 'renderer', 'popup.html'));

  popupWindow.once('ready-to-show', () => {
    popupWindow.webContents.send('selected-text', selectedText);

    // Show with explicit no-focus flag
    popupWindow.showInactive();

    // Register global Escape shortcut when popup is shown
    globalShortcut.register('Escape', () => {
      if (popupWindow && !popupWindow.isDestroyed()) {
        popupWindow.close();
      }
    });
  });

  // Prevent any focus-related events
  popupWindow.on('focus', () => {
    popupWindow.blur(); // Immediately blur if somehow focused
  });

  popupWindow.on('show', () => {
    // Ensure it never gets focus even when shown
    popupWindow.blur();
  });

  // Unregister Escape shortcut when popup is closed
  popupWindow.on('closed', () => {
    globalShortcut.unregister('Escape');
  });
}

function handleTextSelection(selectionData) {
  // Check if we should just hide the popup
  if (selectionData && selectionData.hideOnly) {
    hidePopupWindow();
    return;
  }

  // Otherwise, create a new popup if we have valid text
  if (selectionData && selectionData.text && selectionData.text.trim().length > 0) {
    createPopupWindow(selectionData.x, selectionData.y, selectionData.text);
  }
}

app.whenReady().then(async () => {
  createMainWindow();

  // Initialize selection monitor
  selectionMonitor = new SelectionMonitor(handleTextSelection);
  await selectionMonitor.start();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createMainWindow();
  }
});

app.on('before-quit', () => {
  if (popupDebounceTimer) {
    clearTimeout(popupDebounceTimer);
  }
  if (selectionMonitor) {
    selectionMonitor.stop();
  }
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});

ipcMain.handle('copy-text', (event, text) => {
  clipboard.writeText(text);
});

ipcMain.handle('close-popup', () => {
  if (popupWindow && !popupWindow.isDestroyed()) {
    popupWindow.close();
  }
});
