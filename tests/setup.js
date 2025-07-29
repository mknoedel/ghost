// Jest setup file
// Mock Electron modules for testing
jest.mock('electron', () => ({
  app: {
    getPath: jest.fn(() => '/tmp'),
    quit: jest.fn()
  },
  BrowserWindow: jest.fn(),
  screen: {
    getCursorScreenPoint: jest.fn(() => ({ x: 100, y: 100 }))
  },
  ipcMain: {
    on: jest.fn(),
    handle: jest.fn()
  }
}));

// Mock child_process for selection monitoring tests
jest.mock('child_process');

// Global test timeout
jest.setTimeout(10000);