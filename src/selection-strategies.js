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
    this.fallbackCallback = null;
    this.mainCallback = null;
  }

  async start(callback) {
    this.logger.step('Starting Swift binary watcher...');
    this.mainCallback = callback;
    
    const success = await liveSel.startLiveWatcher(callback, (statusData) => {
      // Handle status messages from Swift binary
      if (statusData.status === 'isolated' || statusData.status === 'fallback_needed') {
        this.logger.warn(`Swift binary limitation detected: ${statusData.message || statusData.status}`);
        if (this.fallbackCallback) {
          this.fallbackCallback(statusData.status);
        }
      }
    });
    
    if (success) {
      this.isActive = true;
      this.logger.success('Swift binary watcher active');
      return true;
    } else {
      this.logger.fail('Swift binary watcher failed');
      return false;
    }
  }

  setFallbackCallback(cb) {
    this.fallbackCallback = cb;
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
    this.fallbackStrategy = null;
    this.callback = null;
    
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
    this.callback = callback;
    
    for (const strategy of this.strategies) {
      try {
        const success = await strategy.start(callback);
        if (success) {
          this.activeStrategy = strategy;
          this.logger.success(`Using ${strategy.name} strategy`);
          
          // If this is the Swift strategy, set up fallback to AppleScript
          if (strategy instanceof SwiftBinaryStrategy) {
            const appleScriptStrategy = this.strategies.find(s => s instanceof AppleScriptStrategy);
            if (appleScriptStrategy) {
              strategy.setFallbackCallback(async (status) => {
                this.logger.warn(`Swift strategy needs fallback (${status}), starting AppleScript...`);
                await this.startFallback(appleScriptStrategy, callback);
              });
            }
          }
          
          return true;
        }
      } catch (error) {
        this.logger.error(`${strategy.name} strategy error:`, error.message);
      }
    }
    
    this.logger.fail('All strategies failed');
    return false;
  }

  async startFallback(fallbackStrategy, callback) {
    if (this.fallbackStrategy) {
      this.logger.info(`Fallback ${fallbackStrategy.name} already running`);
      return; // Already have fallback running
    }
    
    try {
      const success = await fallbackStrategy.start(callback);
      if (success) {
        this.fallbackStrategy = fallbackStrategy;
        this.logger.success(`Fallback ${fallbackStrategy.name} strategy active`);
      } else {
        this.logger.fail(`Fallback ${fallbackStrategy.name} strategy failed`);
      }
    } catch (error) {
      this.logger.error(`Fallback ${fallbackStrategy.name} strategy error:`, error.message);
    }
  }

  stop() {
    if (this.activeStrategy) {
      this.activeStrategy.stop();
      this.activeStrategy = null;
    }
    if (this.fallbackStrategy) {
      this.fallbackStrategy.stop();
      this.fallbackStrategy = null;
    }
    this.logger.info('Selection monitoring stopped');
  }

  getActiveStrategy() {
    if (this.activeStrategy && this.fallbackStrategy) {
      return `${this.activeStrategy.name} + ${this.fallbackStrategy.name} (hybrid)`;
    }
    return this.activeStrategy?.name || 'None';
  }
}

module.exports = { StrategyManager };