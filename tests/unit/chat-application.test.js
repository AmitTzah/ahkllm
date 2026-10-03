'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function findControl(node, label) {
  if (node.tagName === 'button' && node.textContent === label) return node;
  for (const child of node.children || []) { const match = findControl(child, label); if (match) return match; }
}

function applicationUi() {
  const elements = new Map();
  class Element {
    constructor(tag = 'div') { this.tagName = tag; this.children = []; this.style = {}; this.textContent = ''; }
    set id(value) { elements.set(value, this); }
    appendChild(child) { this.children.push(child); child.parentElement = this; }
    replaceChildren() { this.children = []; }
    insertBefore(child) { this.appendChild(child); }
    closest() { return this.parentElement; }
  }
  const container = new Element(), composer = new Element(), input = new Element();
  container.appendChild(composer); composer.appendChild(input); input.id = 'chat-input';
  const requests = [];
  const context = {document: {getElementById: id => elements.get(id), createElement: tag => new Element(tag)}, activeThreadId: 'thread-1', confirm: () => true,
    Ipc: {request: (action, payload) => { requests.push({action, payload}); return Promise.resolve(); }}};
  context.window = context;
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../webui/js/chat/chat-application.js'), 'utf8'), context);
  return {context, elements, requests};
}

test('application actions carry the displayed thread and branch ownership', () => {
  const {context, elements, requests} = applicationUi();
  context.showApplicationState({connected: true, threadId: 'thread-1', leafId: 'leaf-1', label: 'Example', phase: 'discussion', actions: [{id: 'approve', label: 'Approve', confirm: true}]});
  const panel = elements.get('applicationPanel');
  findControl(panel, 'Approve').onclick();
  assert.deepEqual(JSON.parse(JSON.stringify(requests)), [{action: 'applicationAction', payload: {id: 'approve', threadId: 'thread-1', leafId: 'leaf-1'}}]);
});

test('late updates for another thread do not clear current application actions', () => {
  const {context, elements} = applicationUi();
  context.showApplicationState({connected: true, threadId: 'thread-1', leafId: 'leaf-1', label: 'Current', actions: []});
  context.showApplicationState({connected: true, threadId: 'thread-2', leafId: 'leaf-2', label: 'Old', actions: []});
  assert.equal(elements.get('applicationPanel').children[0].children[0].textContent, 'Current');
  context.showApplicationState({connected: false});
  assert.equal(elements.get('applicationPanel').style.display, 'none');
});

test('a running application turn exposes status instead of recovery or author actions', () => {
  const {context, elements} = applicationUi();
  context.showApplicationState({connected:true,threadId:'thread-1',label:'Example',running:true,pending:true,actions:[{id:'recover',label:'Recover interrupted turn'}]});
  const panel=elements.get('applicationPanel');
  assert.match(panel.children[0].children[1].textContent, /Working/);
  assert.equal(findControl(panel, 'Recover interrupted turn'), undefined);
});

test('a rejected action is available to retry and cancellation sends no request', async () => {
  const {context, elements, requests} = applicationUi();
  context.Ipc.request = () => Promise.reject(new Error('Branch changed'));
  context.showApplicationState({connected: true, threadId: 'thread-1', leafId: 'leaf-1', label: 'Example', actions: [{id: 'approve', label: 'Approve', confirm: true}]});
  const control = findControl(elements.get('applicationPanel'), 'Approve');
  control.onclick();
  await Promise.resolve();
  assert.equal(control.disabled, false);
  context.confirm = () => false;
  control.onclick();
  assert.equal(requests.length, 0);
});

test('task controls live inside the composer, collapse, and explain confirmation', () => {
  const {context,elements,requests} = applicationUi();
  let confirmation = '';
  context.confirm = text => { confirmation = text; return false; };
  context.showApplicationState({connected:true,threadId:'thread-1',label:'Task',actions:[{
    id:'complete',label:'Finish task',confirm:true,description:'Ends agent work and keeps the chat readable.',
    confirmation_message:'Ends agent work. Finish this task?'
  }]});
  const panel = elements.get('applicationPanel');
  assert.equal(panel.tagName, 'details');
  assert.equal(panel.parentElement, elements.get('chat-input').parentElement);
  assert.equal(panel.open, false);
  findControl(panel,'Finish task').onclick();
  assert.equal(confirmation,'Ends agent work. Finish this task?');
  assert.equal(requests.length,0);
});
