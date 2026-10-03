const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function settingsUi() {
  const elements = new Map(), requests = [], registered = {};
  class Element {
    constructor() { this.value = ''; this.children = []; this.style = {}; this.dataset = {}; this.textContent = ''; const classes = new Set(); this.classList = {add: name => classes.add(name), remove: name => classes.delete(name), contains: name => classes.has(name)}; }
    focus() {}
    setAttribute() {}
    addEventListener() {}
    querySelectorAll() { return []; }
    append(...children) { this.children.push(...children); }
    appendChild(child) { this.children.push(child); }
    replaceChildren() { this.children = []; }
  }
  const document = {getElementById: id => { if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id); }, createElement: () => new Element()};
  const context = {document, confirm: () => true, Ipc: {request: (action, payload) => {requests.push({action, payload}); return Promise.resolve();}}, SettingsShared: {
    registerSection: (name, section) => {registered[name] = section;},
    setVal: (id, value) => {document.getElementById(id).value = String(value);},
    getVal: id => document.getElementById(id).value
  }};
  context.window = context;
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../webui/js/settings/sections/applications.js'), 'utf8'), context);
  registered.applications.load();
  return {context, document, requests, section: registered.applications};
}

function fillValid(ui) {
  ui.document.getElementById('addApplicationConnection').onclick();
  for (const [id, value] of Object.entries({applicationId:'notes', applicationName:'Notes', applicationProgram:'python', applicationArguments:'-m\nnotes_adapter\npath with spaces', applicationWorkingDirectory:'', applicationTimeout:'60'})) ui.document.getElementById(id).value = value;
}

test('applications section requests connections and does not leak profiles into general settings', () => {
  const ui = settingsUi();
  assert.equal(ui.requests[0].action, 'requestApplicationConnections');
  assert.deepEqual(JSON.parse(JSON.stringify(ui.section.save())), {});
});

test('saving an application preserves argument boundaries and persists through its own host action', async () => {
  const ui = settingsUi(); fillValid(ui);
  await ui.context.SettingsApplications.saveConnection();
  const saved = ui.requests.find(request => request.action === 'saveApplicationConnection').payload.profile;
  assert.deepEqual(JSON.parse(JSON.stringify(saved.command)), ['python', '-m', 'notes_adapter', 'path with spaces']);
  assert.equal(saved.id, 'notes');
  assert.equal(ui.document.getElementById('applicationSettingsStatus').textContent, 'Connection saved.');
});

test('invalid connection IDs and timeouts are rejected before host persistence', async () => {
  const ui = settingsUi(); fillValid(ui);
  ui.document.getElementById('applicationId').value = '../bad';
  await ui.context.SettingsApplications.saveConnection();
  assert.equal(ui.requests.filter(request => request.action === 'saveApplicationConnection').length, 0);
  assert.match(ui.document.getElementById('applicationEditorStatus').textContent, /connection ID/);
  ui.document.getElementById('applicationId').value = 'notes';
  ui.document.getElementById('applicationTimeout').value = '0';
  await ui.context.SettingsApplications.saveConnection();
  assert.match(ui.document.getElementById('applicationEditorStatus').textContent, /Timeout/);
});

test('connected applications render safe names, allow editing, and disconnect without deleting chats', async () => {
  const ui = settingsUi();
  const profile = {id:'notes', name:'<script>Notes</script>', command:['python','-m','notes'], working_directory:'', timeout_seconds:45, chat_count:2};
  ui.context.SettingsApplications.receive({connections:[profile]});
  const card = ui.document.getElementById('applicationConnections').children[0];
  assert.equal(card.children[1].children[0].textContent, profile.name);
  card.children[2].children.find(child => child.textContent === 'Edit').onclick();
  assert.equal(ui.document.getElementById('applicationId').disabled, true);
  assert.equal(ui.document.getElementById('applicationArguments').value, '-m\nnotes');
  card.children[2].children.find(child => child.textContent === 'Disconnect').onclick();
  await Promise.resolve();
  assert.equal(ui.requests.at(-1).action, 'disconnectApplicationConnection');
  assert.equal(ui.requests.at(-1).payload.id, 'notes');
});

test('connection editor opens as a modal and restores its closed state on cancel', () => {
  const ui = settingsUi();
  ui.document.getElementById('addApplicationConnection').onclick();
  assert.equal(ui.document.getElementById('applicationEditor').classList.contains('open'), true);
  assert.equal(ui.document.getElementById('applicationAdvanced').open, false);
  ui.context.SettingsApplications.closeEditor();
  assert.equal(ui.document.getElementById('applicationEditor').classList.contains('open'), false);
  ui.document.getElementById('addApplicationEmpty').onclick();
  assert.equal(ui.document.getElementById('applicationEditor').classList.contains('open'), true);
  assert.equal(ui.document.getElementById('applicationEditorTitle').textContent, 'Add application');
});

test('empty connections show one add control and the guide opens and closes', () => {
  const ui = settingsUi();
  ui.context.SettingsApplications.receive({connections:[]});
  assert.equal(ui.document.getElementById('addApplicationConnection').style.display, 'none');
  ui.context.SettingsApplications.receive({connections:[{id:'notes',name:'Notes',command:['python'],chat_count:0}]});
  assert.equal(ui.document.getElementById('addApplicationConnection').style.display, '');
  assert.equal(ui.document.getElementById('applicationConnectionsEmpty').style.display, 'none');
  ui.document.getElementById('showApplicationGuide').onclick();
  assert.equal(ui.document.getElementById('applicationGuide').classList.contains('open'), true);
  ui.document.getElementById('applicationGuideDone').onclick();
  assert.equal(ui.document.getElementById('applicationGuide').classList.contains('open'), false);
});
