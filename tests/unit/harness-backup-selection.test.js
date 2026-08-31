// Regression coverage for E2E profile isolation. The suite used to move the
// real %APPDATA%\AhkLLM profile aside and junction that path to a temp folder.
// Parallel workers must never need that recovery path.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..', '..');
const suiteSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'e2e-suite.js'), 'utf8');
const launchSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'launch.js'), 'utf8');
const captureSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'capture-screenshots.js'), 'utf8');
const cleanupSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'verify-cleanup.js'), 'utf8');
const offscreenSrc = fs.readFileSync(path.join(ROOT, 'scripts', 'videos', 'offscreen-pipeline.js'), 'utf8');
const appInfoSrc = fs.readFileSync(path.join(ROOT, 'shared', 'AppInfo.ahk'), 'utf8');
const mainSrc = fs.readFileSync(path.join(ROOT, 'Main.ahk'), 'utf8');

describe('headless E2E profile isolation', () => {
  it('never moves, junctions or restores the real user profile', () => {
    assert.doesNotMatch(suiteSrc, /isolateProfile\s*\(/);
    assert.doesNotMatch(suiteSrc, /restoreProfile\s*\(/);
    assert.doesNotMatch(suiteSrc, /llm-profile-bak-/);
    assert.doesNotMatch(suiteSrc, /New-Item\s+-ItemType\s+Junction/i);
    assert.doesNotMatch(launchSrc, /isolateProfile\s*\(/);
    assert.doesNotMatch(launchSrc, /restoreProfile\s*\(/);
    assert.doesNotMatch(captureSrc, /isolateProfile\s*\(|restoreProfile\s*\(/);
    assert.doesNotMatch(cleanupSrc, /isolateProfile\s*\(|restoreProfile\s*\(/);
    assert.doesNotMatch(offscreenSrc, /isolateProfile\s*\(|restoreProfile\s*\(/);
  });

  it('launches real-app scenarios through an explicit isolated data directory', () => {
    assert.match(appInfoSrc, /EnvGet\("AHKLLM_E2E_WORKER"\)/);
    assert.match(appInfoSrc, /EnvGet\("AHKLLM_E2E_DATA_DIR"\)/);
    assert.match(launchSrc, /env\.AHKLLM_E2E_DATA_DIR\s*=\s*sandbox/);
    assert.match(suiteSrc, /sandbox:\s*worker\.sandboxData/);
  });

  it('gives parallel workers separate process and temp identities', () => {
    assert.match(suiteSrc, /--workers=/);
    assert.match(suiteSrc, /TEMP:\s*workerRoot/);
    assert.match(suiteSrc, /TMP:\s*workerRoot/);
    assert.match(suiteSrc, /createWorkerMain\(workerId\)/);
    assert.match(suiteSrc, /teardownWorker\(mainPid,\s*worker\.workerId\)/);
    assert.match(launchSrc, /#SingleInstance Force/);
    assert.match(mainSrc, /AHKLLM_E2E_WORKER/);
    assert.match(mainSrc, /--e2e-worker=/);
  });
});
