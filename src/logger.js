/* eslint-disable no-console */

class Logger {
  constructor(prefix) {
    this.prefix = prefix;
    this.debugMode = process.argv.includes('--debug') || process.env.NODE_ENV === 'development';
  }

  debug(...args) {
    if (this.debugMode) {
      console.log(`[${this.prefix}][DEBUG]`, ...args);
    }
  }

  info(...args) {
    console.log(`[${this.prefix}]`, ...args);
  }

  warn(...args) {
    console.warn(`[${this.prefix}][WARN]`, ...args);
  }

  error(...args) {
    console.error(`[${this.prefix}][ERROR]`, ...args);
  }

  success(message) {
    console.log(`[${this.prefix}] ✅ ${message}`);
  }

  fail(message) {
    console.log(`[${this.prefix}] ❌ ${message}`);
  }

  step(message) {
    console.log(`[${this.prefix}] → ${message}`);
  }
}

module.exports = Logger;
