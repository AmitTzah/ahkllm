// Regression coverage for the headless runner teardown path.
'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..', '..');
const suiteSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'e2e-suite.js'), 'utf8');
const mockSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'mock-llm-server.js'), 'utf8');

describe('headless harness teardown', () => {
  it('does not repeat teardown for every already-cleaned scenario PID', () => {
    assert.ok(!suiteSrc.includes('spawnedPids'), 'completed scenario PIDs must not trigger duplicate teardown sweeps');
    assert.match(suiteSrc, /launcher\.teardown\(0\)/, 'the runner must keep one repo-scoped final backstop sweep');
  });

  it('lets killed slow mock requests release their timers on response close', () => {
    assert.match(mockSrc, /function responseDelay\(res, ms\)/);
    assert.match(mockSrc, /res\.once\('close', finish\)/);
    assert.match(mockSrc, /responseDelay\(res, opts\.tavilyDelay\)/);
  });
});
