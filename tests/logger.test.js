const Logger = require('../src/logger');

// Mock console methods
const originalConsole = { ...console };
beforeEach(() => {
  console.log = jest.fn();
  console.error = jest.fn();
});

afterEach(() => {
  Object.assign(console, originalConsole);
});

describe('Logger', () => {
  test('should create logger with prefix', () => {
    const logger = new Logger('TestModule');
    expect(logger).toBeDefined();
  });

  test('should log info messages with prefix', () => {
    const logger = new Logger('TestModule');
    logger.info('test message');
    expect(console.log).toHaveBeenCalledWith(
      expect.stringContaining('[TestModule]'),
      'test message'
    );
  });

  test('should log error messages', () => {
    const logger = new Logger('TestModule');
    logger.error('something went wrong');
    expect(console.error).toHaveBeenCalledWith(
      expect.stringContaining('[TestModule]'),
      'something went wrong'
    );
  });

  test('should handle debug mode', () => {
    // This would need process.env.DEBUG testing
    const logger = new Logger('TestModule');
    logger.debug('debug info');
    // Debug behavior depends on environment
  });
});
