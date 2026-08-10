// harness-backup-selection.test.js — Regression test for bug #189: the
// headless harness's TWO interrupted-run recovery paths must select the SAME
// (newest) llm-profile-bak-* backup. e2e-suite.recoverInterruptedRun sorts and
// takes backups[length-1]; launch.isolateProfile previously restored the
// FIRST readdirSync entry, so a direct launch could restore a stale profile
// when multiple backups accumulated.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..', '..');
const suiteSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'e2e-suite.js'), 'utf8');
const launchSrc = fs.readFileSync(path.join(ROOT, 'tests', 'headless', 'launch.js'), 'utf8');

function hasNewestBackupSelection(src, tmpExpr) {
  // filter llm-profile-bak-* -> sort() -> take backups[backups.length - 1]
  const sortRe = new RegExp(`backups\\s*=\\s*fs\\.readdirSync\\(${tmpExpr}\\)\\.filter\\(\\(n\\) => n\\.startsWith\\('llm-profile-bak-'\\)\\)\\.sort\\(\\)`);
  return sortRe.test(src) && /backups\[backups\.length - 1\]/.test(src);
}

describe('harness interrupted-run backup selection (bug #189)', () => {
  it('recoverInterruptedRun restores the newest sorted backup', () => {
    assert.ok(
      hasNewestBackupSelection(suiteSrc, 'os\\.tmpdir\\(\\)'),
      'recoverInterruptedRun must sort backups and take the newest'
    );
  });

  it('isolateProfile restores the SAME newest backup (not the first readdir entry)', () => {
    assert.ok(
      hasNewestBackupSelection(launchSrc, 'tmp'),
      'isolateProfile must sort backups and take the newest, matching recoverInterruptedRun'
    );
  });
});
