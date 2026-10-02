const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function makeTable(entries) {
  const table = {
    children: [],
    querySelectorAll() { return this.children.slice(); },
    querySelector() { return null; },
    appendChild(row) { this.children.push(row); row.parent = this; }
  };
  entries.forEach(([id, provider]) => table.appendChild({
    id, provider, unsavedInput: 'unsaved edit',
    querySelector(selector) { return { value: selector === '[data-field="id"]' ? this.id : this.provider }; },
    remove() { this.parent.children.splice(this.parent.children.indexOf(this), 1); }
  }));
  return table;
}

function loadCatalogUi(tables) {
  const sandbox = { window: {}, document: { getElementById: (id) => tables[id] || null } };
  const source = fs.readFileSync(path.join(__dirname, '../../webui/js/settings/chatgpt-model-catalog.js'), 'utf8');
  vm.runInNewContext(source, sandbox);
  return sandbox.window.ChatGptModelCatalogUi;
}

describe('ChatGPT catalog table reconciliation', () => {
  it('replaces plan and legacy rows while preserving unrelated row identity and unsaved edits', () => {
    const table = makeTable([['kept', 'openai'], ['old', 'chatgpt'], ['codex/legacy', '']]);
    const unrelated = table.children[0];
    const ui = loadCatalogUi({ modelsTableBody: table });
    ui.replaceRows('modelsTableBody', { 'chatgpt/new': { displayName: 'New model' } },
      (id, metadata) => ({ id, metadata }));
    assert.deepEqual(table.children.map((row) => row.id), ['kept', 'chatgpt/new']);
    assert.equal(table.children[0], unrelated);
    assert.equal(unrelated.unsavedInput, 'unsaved edit');
    assert.equal(table.children[1].metadata.displayName, 'New model');
  });

  it('prunes all account rows for a successful empty catalog in both tables', () => {
    const main = makeTable([['a', 'chatgpt'], ['b', 'openai']]);
    const modal = makeTable([['old', 'codex'], ['edited', 'custom']]);
    const ui = loadCatalogUi({ main, modal });
    for (const tableId of ['main', 'modal']) ui.replaceRows(tableId, {}, () => assert.fail('empty catalog adds no rows'));
    assert.deepEqual(main.children.map((row) => row.id), ['b']);
    assert.deepEqual(modal.children.map((row) => row.id), ['edited']);
    ui.replaceRows('not-rendered', {}, () => assert.fail('missing table adds no rows'));
  });
});
