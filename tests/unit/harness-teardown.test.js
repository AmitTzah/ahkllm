// Regression coverage for the headless runner teardown path.
'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..', '..');
const suiteSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'e2e-suite.js'), 'utf8');
const launchSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'launch.js'), 'utf8');
const mockSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'mock-llm-server.js'), 'utf8');
const probeSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'probe.ahk'), 'utf8');
const mainSrc = fs.readFileSync(path.join(ROOT, 'Main.ahk'), 'utf8');
const hotkeySrc = fs.readFileSync(path.join(ROOT, 'app', 'HotkeyRegistrar.ahk'), 'utf8');
const chatHotkeySrc = fs.readFileSync(path.join(ROOT, 'chat', 'ChatHotkeys.ahk'), 'utf8');

describe('headless harness teardown', () => {
  it('uses worker-scoped cleanup while sibling E2E instances may still be alive', () => {
    assert.ok(!suiteSrc.includes('spawnedPids'), 'completed scenario PIDs must not trigger duplicate teardown sweeps');
    assert.match(suiteSrc, /launcher\.teardownWorker\(mainPid,\s*worker\.workerId\)/);
    assert.match(launchSrc, /function killE2EWorkerProcesses\(workerId\)/);
    assert.match(launchSrc, /--e2e-worker=/);
    assert.doesNotMatch(suiteSrc, /launcher\.teardown\(0\)/, 'parallel runner must not do a repo-wide sweep while workers are active');
  });

  it('keeps one E2E-only parent backstop for interrupted workers', () => {
    assert.match(suiteSrc, /launcher\.killAllE2EProcesses\(\)/);
    assert.match(launchSrc, /function killAllE2EProcesses\(\)/);
    assert.match(launchSrc, /\.ahkllm-e2e-main-/);
  });

  it('reaps stale internal worker processes without touching a normal E2E parent', () => {
    assert.match(launchSrc, /node\.exe/);
    assert.match(launchSrc, /e2e-suite\.js\*--internal-worker/);
    assert.match(launchSrc, /#NoTrayIcon/);
  });

  it('keeps probes and shutdown scoped to the current worker', () => {
    assert.match(probeSrc, /AHKLLM_E2E_WORKER/);
    assert.match(probeSrc, /ProcessCmdLine\(pid\)/);
    assert.match(mainSrc, /EnvGet\("AHKLLM_E2E_WORKER"\)\s*=\s*""\s*&&\s*WinExist\("ChatWindow\.ahk ahk_class AutoHotkey"\)/);
  });

  it('suppresses system-wide hotkeys inside parallel E2E workers', () => {
    assert.match(hotkeySrc, /EnvGet\("AHKLLM_E2E_WORKER"\)\s*!=\s*""/);
    assert.match(chatHotkeySrc, /EnvGet\("AHKLLM_E2E_WORKER"\)\s*!=\s*""/);
  });

  it('lets killed slow mock requests release their timers on response close', () => {
    assert.match(mockSrc, /function responseDelay\(res, ms\)/);
    assert.match(mockSrc, /res\.once\('close', finish\)/);
    assert.match(mockSrc, /responseDelay\(res, opts\.tavilyDelay\)/);
  });
});
