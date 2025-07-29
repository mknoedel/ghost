const { spawn } = require('child_process');
const path = require('path');
const Logger = require('./logger');

const logger = new Logger('LiveSelection');
let child = null;

function startLiveWatcher(cb, statusCb) {
  if (child) return Promise.resolve(true);
  const bin = path.join(__dirname, '..', 'native', 'bin', 'SelectionTap');

  return new Promise(resolve => {
    try {
      child = spawn(bin);
      let resolved = false;

      child.stdout.on('data', buf => {
        if (!resolved) {
          resolved = true;
          resolve(true);
        }
        try {
          const data = JSON.parse(buf.toString());

          // Handle status messages for fallback detection
          if (data.status) {
            if (data.status === 'isolated' || data.status === 'fallback_needed') {
              logger.debug(`Status: ${data.status}${data.message ? ' - ' + data.message : ''}`);
              if (statusCb) statusCb(data);
            } else if (data.status === 'clipboard_fallback') {
              logger.debug('Using clipboard fallback');
              if (statusCb) statusCb(data);
            }
          }

          // Only call main callback if we have actual text content
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
