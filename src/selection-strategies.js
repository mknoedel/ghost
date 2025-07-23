const Logger = require('./logger');
const liveSel = require('./mac-live-selection');
const macSelection = require('./mac-selection');

class SelectionStrategy {
  constructor(name) {
    this.name = name;
    this.logger = new Logger(`Strategy:${name}`);
    this.isActive = false;
  }

  async start(callback) {
    throw new Error('start() must be implemented by subclass');
  }

  stop() {
    throw new Error('stop() must be implemented by subclass');
  }
}

class SwiftBinaryStrategy extends SelectionStrategy {
  constructor() {
    super('SwiftBinary');
  }

  async start(callback) {
    this.logger.step('Starting Swift binary watcher...');
    const success = await liveSel.startLiveWatcher(callback);
    if (success) {
      this.isActive = true;
      this.logger.success('Swift binary watcher active');
      return true;
    } else {
      this.logger.fail('Swift binary watcher failed');
      return false;
    }
  }

  stop() {
    if (this.isActive) {
      liveSel.stopLiveWatcher();
      this.isActive = false;
      this.logger.info('Swift binary watcher stopped');
    }
  }
}

class AppleScriptStrategy extends SelectionStrategy {
  constructor() {
    super('AppleScript');
  }

  async start(callback) {
    this.logger.step('Starting AppleScript polling...');
    const success = await macSelection.startWatching(callback);
    if (success) {
      this.isActive = true;
      this.logger.success('AppleScript polling active');
      return true;
    } else {
      this.logger.fail('AppleScript polling failed');
      return false;
    }
  }

  stop() {
    if (this.isActive) {
      macSelection.stopWatching();
      this.isActive = false;
      this.logger.info('AppleScript polling stopped');
    }
  }
}

class StrategyManager {
  constructor() {
    this.logger = new Logger('StrategyManager');
    this.strategies = [];
    this.activeStrategy = null;
    
    // Only add macOS strategies for now
    if (process.platform === 'darwin') {
      this.strategies = [
        new SwiftBinaryStrategy(),
        new AppleScriptStrategy()
      ];
    }
  }

  async start(callback) {
    this.logger.info('Starting selection monitoring...');
    
    for (const strategy of this.strategies) {
      try {
        const success = await strategy.start(callback);
        if (success) {
          this.activeStrategy = strategy;
          this.logger.success(`Using ${strategy.name} strategy`);
          return true;
        }
      } catch (error) {
        this.logger.error(`${strategy.name} strategy error:`, error.message);
      }
    }
    
    this.logger.fail('All strategies failed');
    return false;
  }

  stop() {
    if (this.activeStrategy) {
      this.activeStrategy.stop();
      this.activeStrategy = null;
      this.logger.info('Selection monitoring stopped');
    }
  }

  getActiveStrategy() {
    return this.activeStrategy?.name || 'None';
  }
}

module.exports = { StrategyManager };