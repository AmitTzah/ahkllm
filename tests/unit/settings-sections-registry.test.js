// settings-sections-registry.test.js - Hardening item 4: every settings
// section file must register a load() AND a save() with SettingsShared, so a
// section cannot silently ship without participating in the save round-trip
// (the #39/#61/#122/#130 family). sysmsg-modal.js is a modal helper, not a
// section, and is intentionally excluded.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const sectionsDir = path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections');
const files = fs.readdirSync(sectionsDir).filter((f) => f.endsWith('.js') && f !== 'sysmsg-modal.js');

describe('settings sections registry (hardening item 4)', () => {
  it('every section file registers load() and save()', () => {
    assert.ok(files.length >= 8, 'expected at least 8 section files, got ' + files.length);
    for (const f of files) {
      const src = fs.readFileSync(path.join(sectionsDir, f), 'utf8');
      const registered = src.includes('S.registerSection(');
      const hasLoad = /function load\(/.test(src);
      const hasSave = /function save\(/.test(src);
      assert.ok(registered, f + ' must register with SettingsShared');
      assert.ok(hasLoad, f + ' must define load()');
      assert.ok(hasSave, f + ' must define save()');
    }
  });

  it('each section registers its own name (no duplicate section ids)', () => {
    const names = [];
    for (const f of files) {
      const src = fs.readFileSync(path.join(sectionsDir, f), 'utf8');
      const m = src.match(/var sectionName = '([^']+)'/);
      assert.ok(m, f + ' must declare a sectionName');
      names.push(m[1]);
    }
    assert.strictEqual(new Set(names).size, names.length, 'duplicate section names: ' + JSON.stringify(names));
  });
});
