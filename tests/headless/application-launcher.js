'use strict';
const path = require('node:path');
const {spawn} = require('node:child_process');
const launcher = require('./launch');

// Keep the mock HTTP event loop alive while AhkLLM accepts the session.
function launchApplicationPackage(packagePath, dataDir, hwnd) {
  if (!Number.isSafeInteger(Number(hwnd)) || Number(hwnd) <= 0)
    throw new Error('No isolated ChatWindow target is available for application import');
  return new Promise((resolve, reject) => {
    const child = spawn(launcher.AHK, ['/ErrorStdOut', path.join(launcher.REPO_ROOT,'app/ExternalSessionLauncher.ahk'),
      '--open', packagePath, '--target-window', String(hwnd)], {
      windowsHide:true, stdio:['ignore','pipe','pipe'],
      env:{...process.env,AHKLLM_E2E_WORKER:process.env.AHKLLM_E2E_WORKER||'external-test',AHKLLM_E2E_DATA_DIR:dataDir}
    });
    let stdout='',stderr='';
    const timer=setTimeout(()=>{child.kill();reject(new Error('Application launcher timed out'));},35000);
    child.stdout.on('data',chunk=>{stdout+=chunk.toString('utf8');});
    child.stderr.on('data',chunk=>{stderr+=chunk.toString('utf8');});
    child.once('error',error=>{clearTimeout(timer);reject(error);});
    child.once('close',status=>{clearTimeout(timer);resolve({status,stdout,stderr});});
  });
}

module.exports={launchApplicationPackage};
