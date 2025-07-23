const { spawn } = require('child_process');
const path = require('path');

let child = null;

function startLiveWatcher(cb) {
  if (child) return Promise.resolve(true);
  const bin = path.join(__dirname, '..', 'native', 'bin', 'SelectionTap');

  return new Promise((resolve) => {
    try {
      child = spawn(bin);
      let hasOutput = false;
      let resolved = false;
      
      child.stdout.on('data', (buf) => {
        hasOutput = true;
        if (!resolved) {
          resolved = true;
          resolve(true);
        }
        try { cb(JSON.parse(buf.toString())); } catch (_) {}
      });
      
      child.stderr.on('data', (d) => {
        console.error('[LiveSel helper]', d.toString().trim());
      });
      
      child.on('close', (code) => { 
        console.error('[LiveSel helper] Process closed with code:', code);
        child = null;
        if (!resolved) {
          resolved = true;
          resolve(false);
        }
      });
      
      child.on('error', (err) => {
        console.error('[LiveSel helper] Process error:', err.message);
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
          console.error('[LiveSel helper] Binary started - waiting for user text selections');
          resolved = true;
          resolve(true); // Consider it successful if process is running
        }
      }, 1000);

    } catch (err) {
      console.error('[LiveSel helper] Failed to start:', err.message);
      resolve(false);
    }
  });
}

function stopLiveWatcher() { child?.kill(); child = null; }

module.exports = { startLiveWatcher, stopLiveWatcher };
