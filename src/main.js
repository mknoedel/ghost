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
  
  const currentBounds = `${Math.round(x/10)*10},${Math.round(y/10)*10}`;
  
  // Skip if this is a duplicate position within debounce window
  if (lastPopupBounds === currentBounds) {
    return;
  }
  
  popupDebounceTimer = setTimeout(() => {
    createPopupWindowImmediate(x, y, selectedText);
    lastPopupBounds = currentBounds;
  }, 100); // 100ms debounce for popup creation
}

function createPopupWindowImmediate(x, y, selectedText) {
  if (popupWindow && !popupWindow.isDestroyed()) {
    popupWindow.close();
  }

  // Ensure popup stays within screen bounds
  const { screen } = require('electron');
  const display = screen.getDisplayNearestPoint({ x, y });
  const bounds = display.workArea;
  
  const popupWidth = 400;
  const popupHeight = 60;
  
  // Position popup near selection instead of using arbitrary offset
  let popupX = Math.max(bounds.x, Math.min(x - popupWidth / 2, bounds.x + bounds.width - popupWidth));
  let popupY = Math.max(bounds.y, y - popupHeight - 10); // Small gap above selection

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
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  popupWindow.loadFile(path.join(__dirname, 'renderer', 'popup.html'));
  
  popupWindow.once('ready-to-show', () => {
    popupWindow.webContents.send('selected-text', selectedText);
    popupWindow.show();
    popupWindow.focus();
  });

  // Close popup when Escape key is pressed
  popupWindow.webContents.on('before-input-event', (event, input) => {
    if (input.key === 'Escape' && input.type === 'keyDown') {
      if (popupWindow && !popupWindow.isDestroyed()) {
        popupWindow.close();
      }
    }
  });
}

function handleTextSelection(selectionData) {
  if (selectionData && selectionData.text && selectionData.text.trim().length > 0) {
    createPopupWindow(selectionData.x, selectionData.y, selectionData.text);
  }
}

app.whenReady().then(() => {
  createMainWindow();

  // Initialize selection monitor
  selectionMonitor = new SelectionMonitor(handleTextSelection);
  selectionMonitor.start();
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