const { spawn } = require('child_process');
const path = require('path');
const Logger = require('./logger');

const logger = new Logger('LiveSelection');
let child = null;

// Event type mappings for better logging
const EVENT_EMOJIS = {
  focus_change: '🔄',
  text_selection: '📝',
  window_update: '🪟',
  browser_navigation: '🌐',
  system_metrics: '📊',
  user_activity: '👤',
  heartbeat: '💓'
};

function startLiveWatcher(cb, statusCb) {
  if (child) return Promise.resolve(true);

  const bin = path.resolve(__dirname, '..', 'native', 'bin', 'SelectionTap');
  const args = ['--comprehensive']; // Use new event system by default

  logger.info(`Starting SelectionTap: ${bin} ${args.join(' ')}`);

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
          const rawData = buf.toString().trim();

          // Handle multiple JSON objects on separate lines
          const lines = rawData.split('\n').filter(line => line.trim());

          for (const line of lines) {
            try {
              const data = JSON.parse(line);
              processEvent(data, cb, statusCb);
            } catch (lineError) {
              logger.error('Failed to parse JSON line:', lineError.message);
              logger.debug('Raw line:', line);
            }
          }
        } catch (e) {
          logger.error('Failed to process buffer:', e.message);
          logger.debug('Raw data:', buf.toString());
        }
      });

      child.stderr.on('data', d => {
        logger.info('[SelectionTap]', d.toString().trim());
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

      setTimeout(() => {
        if (!resolved && child) {
          logger.info('SelectionTap started - monitoring user activity');
          resolved = true;
          resolve(true);
        }
      }, 1000);
    } catch (err) {
      logger.error('Failed to start:', err.message);
      resolve(false);
    }
  });
}

function processEvent(data, cb, statusCb) {
  // Log the event
  logEvent(data);

  // Handle callbacks based on event type
  handleStructuredEvent(data, cb, statusCb);
}

function handleStructuredEvent(data, cb, statusCb) {
  switch (data.eventType) {
    case 'text_selection':
      if (data.text && cb) cb(data);
      break;
    case 'focus_change':
    case 'heartbeat':
    case 'window_update':
    case 'browser_navigation':
    case 'system_metrics':
    case 'user_activity':
      if (statusCb) statusCb(data);
      break;
  }
}

function logEvent(data) {
  if (!data.eventType) {
    logger.warn('Received event without eventType:', JSON.stringify(data, null, 2));
    return;
  }

  const emoji = EVENT_EMOJIS[data.eventType] || '📋';
  const app = data.app?.name || 'Unknown';

  switch (data.eventType) {
    case 'focus_change':
      logFocusChange(data, emoji);
      break;

    case 'text_selection':
      logTextSelection(data, emoji, app);
      break;

    case 'window_update':
      logWindowUpdate(data, emoji, app);
      break;

    case 'browser_navigation':
      logBrowserNavigation(data, emoji, app);
      break;

    case 'system_metrics':
      logSystemMetrics(data, emoji);
      break;

    case 'user_activity':
      logUserActivity(data, emoji, app);
      break;

    case 'heartbeat':
      logHeartbeat(data, emoji, app);
      break;

    default:
      logger.info(`${emoji} ${data.eventType} - ${app}`);
  }
}

function logFocusChange(data, emoji) {
  const prevApp = data.previousApp?.name || 'Unknown';
  const currentApp = data.app?.name || 'Unknown';
  const duration = Math.round(data.focusDuration || 0);
  const sessionId = data.sessionId ? ` [${data.sessionId}]` : '';

  logger.info(`${emoji} ${prevApp} → ${currentApp} (${duration}s)${sessionId}`);
  logAppDetails(data.app);
}

function logTextSelection(data, emoji, app) {
  const text = data.text.length > 50 ? data.text.substring(0, 50) + '...' : data.text;
  const length = data.selectionLength || data.text.length;
  const source = data.source || 'unknown';

  logger.info(`${emoji} "${text}" from ${app} (${length} chars, ${source})`);
}

function logWindowUpdate(data, emoji, app) {
  const title = data.windowTitle || 'Untitled';
  const x = Math.round(data.windowPosition?.x || 0);
  const y = Math.round(data.windowPosition?.y || 0);

  logger.info(`${emoji} "${title}" (${x}, ${y}) - ${app}`);
}

function logBrowserNavigation(data, emoji, app) {
  const domain = data.domain || 'unknown';
  const tabInfo = data.tabCount ? ` (${data.tabCount} tabs)` : '';

  logger.info(`${emoji} ${domain}${tabInfo} - ${app}`);
}

function logSystemMetrics(data, emoji) {
  const metrics = [];

  if (data.batteryLevel !== undefined && data.batteryLevel !== null) {
    metrics.push(`🔋${Math.round(data.batteryLevel)}%`);
  }

  if (data.screenScale) {
    metrics.push(`📺${data.screenScale}x`);
  }

  const info = metrics.length > 0 ? metrics.join(' ') : 'System info collected';
  logger.info(`${emoji} ${info}`);
}

function logUserActivity(data, emoji, app) {
  const activity = data.activityType || 'general';
  const duration = Math.round(data.duration || 0);
  const timeOfDay = data.timeOfDay || 'unknown';

  const timeEmojis = {
    morning: '🌅',
    afternoon: '☀️',
    evening: '🌆',
    night: '🌙'
  };
  const timeEmoji = timeEmojis[timeOfDay] || '🕐';

  logger.info(`${emoji} ${activity} activity (${duration}s) ${timeEmoji} ${timeOfDay} - ${app}`);
}

function logHeartbeat(data, emoji, app) {
  const sessionDuration = Math.round(data.sessionDuration || 0);
  const totalTime = Math.round(data.totalActiveTime || 0);

  logger.info(`${emoji} ${app} session: ${sessionDuration}s (total: ${totalTime}s)`);
}

function logAppDetails(app) {
  if (!app) return;

  const accessible = app.isAccessible ? '✅' : '❌';
  const fallback = app.requiresFallback ? ' (fallback)' : '';

  logger.info(`   ${app.name} (${app.bundleIdentifier}) ${accessible}${fallback}`);
}

function stopLiveWatcher() {
  if (child) {
    child.kill();
    child = null;
    logger.info('SelectionTap stopped');
  }
}

module.exports = {
  startLiveWatcher,
  stopLiveWatcher
};
