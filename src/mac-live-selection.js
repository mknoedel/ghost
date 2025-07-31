const { spawn } = require('child_process');
const path = require('path');
const Logger = require('./logger');

const logger = new Logger('LiveSelection');
let child = null;

// Unified logging function for all SelectionTap data
function logUnifiedData(data) {
  // Focus change events
  if (data.eventType === 'focus_change') {
    const prevApp = data.previousApp ? data.previousApp.name : 'Unknown';
    const currentApp = data.app ? data.app.name : 'Unknown';
    const duration = Math.round(data.focusDuration || 0);
    logger.info(`🔄 ${prevApp} → ${currentApp} (${duration}s)`);
    logAppDetails(data.app);
    logCollectorData(data);
    return;
  }

  // Focus heartbeat events (reduced frequency)
  if (data.eventType === 'focus_heartbeat') {
    const currentApp = data.app ? data.app.name : 'Unknown';
    const duration = Math.round(data.focusDuration || 0);
    if (duration % 30 < 1) {
      logger.info(`💓 ${currentApp} (${duration}s)`);
      logCollectorData(data);
    }
    return;
  }

  // Comprehensive data events (modular collectors)
  if (data.eventType === 'comprehensive_data') {
    logger.info('📊 Comprehensive data collected');
    logCollectorData(data);
    return;
  }

  // Text selection events
  if (data.text && !data.eventType) {
    const text = data.text.length > 50 ? data.text.substring(0, 50) + '...' : data.text;
    const app = data.app ? data.app.name : 'Unknown';
    logger.info(`📝 "${text}" from ${app}`);
    return;
  }

  // Status messages
  if (data.status) {
    const statusEmoji = {
      success: '✅',
      fallback_needed: '⚠️',
      isolated: '🔒',
      clipboard_fallback: '📋'
    };
    const emoji = statusEmoji[data.status] || '📊';
    const app = data.app ? data.app.name : data.appName || 'Unknown';
    logger.info(`${emoji} ${data.status} - ${app}${data.message ? ': ' + data.message : ''}`);
    return;
  }

  // Legacy focus tracking (without eventType)
  if (data.app && !data.eventType && !data.text) {
    logAppDetails(data.app);
  }
}

// Helper function to log app details
function logAppDetails(app) {
  if (!app) return;
  const accessible = app.isAccessible ? '✅' : '❌';
  const isolated = app.isIsolated ? '🔒' : '🔓';
  logger.info(`   ${app.name} (${app.bundleIdentifier}) ${accessible} ${isolated}`);
}

// Helper function to log collector data
function logCollectorData(data) {
  const collectors = [];

  if (data.windowContext?.windowTitle) {
    collectors.push(`📱 ${data.windowContext.windowTitle}`);
  }

  if (data.browserData?.currentURL) {
    const domain = data.browserData.domain || new URL(data.browserData.currentURL).hostname;
    collectors.push(
      `🌐 ${domain}${data.browserData.tabCount ? ` (${data.browserData.tabCount} tabs)` : ''}`
    );
  }

  if (data.systemMetrics) {
    const sm = data.systemMetrics;
    const metrics = [];
    if (sm.batteryLevel !== undefined && sm.batteryLevel !== 'unavailable') {
      metrics.push(`🔋${sm.batteryLevel}%`);
    }
    if (metrics.length > 0) {
      collectors.push(metrics.join(' '));
    }
  }

  if (data.timeContext?.timeOfDay) {
    const timeEmoji = {
      morning: '🌅',
      afternoon: '☀️',
      evening: '🌆',
      night: '🌙'
    };
    const emoji = timeEmoji[data.timeContext.timeOfDay] || '🕐';
    collectors.push(`${emoji} ${data.timeContext.timeOfDay}`);
  }

  if (collectors.length > 0) {
    logger.info(`   ${collectors.join(' | ')}`);
  }
}

function startLiveWatcher(cb, statusCb) {
  if (child) return Promise.resolve(true);
  const bin = path.resolve(__dirname, '..', 'native', 'bin', 'SelectionTap');
  const args = ['--comprehensive'];

  logger.info(`Starting SelectionTap with comprehensive mode: ${bin} ${args.join(' ')}`);

  return new Promise(resolve => {
    try {
      child = spawn(bin, args);
      let resolved = false;

      child.stdout.on('data', buf => {
        if (!resolved) {
          resolved = true;
          resolve(true);
        }
        try {
          const data = JSON.parse(buf.toString());

          // Unified logging for all data types
          logUnifiedData(data);

          // Handle callbacks
          if (data.eventType === 'focus_change' || data.eventType === 'focus_heartbeat') {
            if (statusCb) statusCb(data);
          }

          if (data.app && data.apprequiresFallback) {
            if (statusCb) statusCb(data);
          }

          // Call main callback if we have actual text content
          if (data.text) {
            cb(data);
          }
        } catch (e) {
          logger.error('Failed to parse JSON:', e.message);
        }
      });

      child.stderr.on('data', d => {
        logger.error('[LiveSel helper]', d.toString().trim());
      });

      child.on('close', code => {
        logger.warn(`Process closed with code: ${code}`);
        child = null;
        if (!resolved) {
          resolved = true;
          resolve(false);
        }
      });

      child.on('error', err => {
        logger.error('Process error:', err.message);
        child = null;
        if (!resolved) {
          resolved = true;
          resolve(false);
        }
      });

      // The binary only outputs JSON when user actually selects text
      // So we consider it successful if it starts without immediate errors
      setTimeout(() => {
        if (!resolved && child) {
          logger.info('Binary started - waiting for user text selections');
          resolved = true;
          resolve(true); // Consider it successful if process is running
        }
      }, 1000);
    } catch (err) {
      logger.error('Failed to start:', err.message);
      resolve(false);
    }
  });
}

function stopLiveWatcher() {
  child?.kill();
  child = null;
}

module.exports = { startLiveWatcher, stopLiveWatcher };
