const { spawn } = require('child_process');
const path = require('path');

let child = null;

function startLiveWatcher(cb) {
  if (child) return true;                     // already running
  const bin = path.join(__dirname, '..', 'native', 'bin', 'SelectionTap');

  try {
    child = spawn(bin);
    let hasOutput = false;
    
    child.stdout.on('data', (buf) => {
      hasOutput = true;
      try { cb(JSON.parse(buf.toString())); } catch (_) {}
    });
    child.stderr.on('data', (d) => {
      console.error('[LiveSel helper]', d.toString().trim());
    });
    child.on('close', (code) => { 
      console.error('[LiveSel helper] Process closed with code:', code);
      child = null; 
    });
    child.on('error', (err) => {
      console.error('[LiveSel helper] Process error:', err.message);
      child = null;
    });

    // Give it a moment to start up and check if it's working
    setTimeout(() => {
      if (!hasOutput && child) {
        console.error('[LiveSel helper] No output detected');
      }
    }, 2000);

    return true;
  } catch (err) {
    console.error('[LiveSel helper] Failed to start:', err.message);
    return false;
  }
}

function stopLiveWatcher() { child?.kill(); child = null; }

module.exports = { startLiveWatcher, stopLiveWatcher };
