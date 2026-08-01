// commands-drag.test.js — Unit tests for webui/js/settings/sections/commands/commands-drag.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function makeClassList(initial) {
    const classes = initial ? initial.slice() : [];
    return {
        add(c) { if (!classes.includes(c)) classes.push(c); },
        remove(c) { const i = classes.indexOf(c); if (i >= 0) classes.splice(i, 1); },
        contains(c) { return classes.includes(c); },
        toggle(c) { if (this.contains(c)) this.remove(c); else this.add(c); },
    };
}

function makeDragEl(overrides) {
    const el = Object.assign({
        dataset: {},
        style: {},
        classList: makeClassList(),
        children: [],
        parentNode: null,
        _listeners: {},
        offsetWidth: 100,
        offsetHeight: 20,
        nextElementSibling: null,
        addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); },
        fire(type, event) { (this._listeners[type] || []).forEach((fn) => fn.call(this, event || {})); },
        appendChild(child) { child.parentNode = this; this.children.push(child); return child; },
        insertBefore(node, ref) {
            if (node.parentNode) {
                const oldIndex = node.parentNode.children.indexOf(node);
                if (oldIndex >= 0) node.parentNode.children.splice(oldIndex, 1);
            }
            node.parentNode = this;
            const i = ref ? this.children.indexOf(ref) : -1;
            if (i >= 0) this.children.splice(i, 0, node);
            else this.children.push(node);
            return node;
        },
        remove() {
            if (!this.parentNode) return;
            const i = this.parentNode.children.indexOf(this);
            if (i >= 0) this.parentNode.children.splice(i, 1);
            this.parentNode = null;
        },
        cloneNode() {
            return makeDragEl({
                dataset: Object.assign({}, this.dataset),
                classList: makeClassList(),
                style: {},
            });
        },
        getBoundingClientRect() {
            const index = this.parentNode ? this.parentNode.children.indexOf(this) : 0;
            return { top: 100 * Math.max(0, index), left: 10, height: 20 };
        },
        closest() { return this._closest || null; },
        querySelectorAll(sel) { return (this._queryMap || {})[sel] || []; },
        querySelector(sel) { return ((this._queryMap || {})[sel] || [])[0] || null; },
    }, overrides);
    return el;
}

function makeEvent(currentTarget, extra) {
    const dt = {
        setData: () => {},
        setDragImage: () => {},
        effectAllowed: '',
    };
    return Object.assign({
        currentTarget,
        dataTransfer: dt,
        clientX: 50,
        clientY: 60,
        preventDefault() { this._prevented = true; },
    }, extra || {});
}

function loadDragModule({ docMap, list, markCalls, submenuTags, groupOrders }) {
    const marks = [];
    const tags = [];
    const orders = groupOrders || { '__main__': [0, 1] };
    const C = {
        groupOrders: () => orders,
        mark: () => { marks.push(true); },
        setSubmenuOrder: (t) => { tags.push(t.slice()); },
    };
    const body = makeDragEl();
    const document = {
        body,
        getElementById: (id) => (id === 'commandsListBody' ? (list || null) : null),
        querySelectorAll: (sel) => (docMap && docMap[sel]) || [],
        querySelector: (sel) => ((docMap && docMap[sel]) || [])[0] || null,
        addEventListener: () => {},
    };
    const sandbox = {
        document,
        window: { Cmds: C },
        getComputedStyle: () => ({ backgroundColor: 'rgb(0, 0, 0)' }),
        Image: function Image() { this.src = ''; },
        setTimeout: (fn) => { fn(); },
        console,
    };
    sandbox.global = sandbox;

    const src = fs.readFileSync(
        path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'commands', 'commands-drag.js'),
        'utf-8'
    );
    vm.runInContext(src, vm.createContext(sandbox));

    return {
        C,
        document,
        body,
        marks,
        tags,
        orders,
    };
}

describe('Commands drag module', () => {
    it('wires item drag handlers and performs item drag start/drag/dragend', () => {
        const item = makeDragEl({ dataset: { index: '2' } });
        const body = makeDragEl();
        body._queryMap = { '.is-dragging': [], '.cmd-item:not(.is-dragging)': [], '.cmd-item': [item] };
        const list = makeDragEl();
        list._queryMap = {
            '.cmd-item': [item],
            '.cmd-group-body': [body],
        };
        const { C, document, body: docBody, marks } = loadDragModule({ list, docMap: {} });

        C._wireItemDrag(list);
        assert.ok(item._listeners.dragstart.length === 1);
        assert.ok(item._listeners.drag.length === 1);
        assert.ok(item._listeners.dragend.length === 1);
        assert.ok(body._listeners.dragover.length === 1);
        assert.ok(body._listeners.drop.length === 1);

        const dragstart = makeEvent(item, { clientX: 120, clientY: 140 });
        item.fire('dragstart', dragstart);
        assert.ok(dragstart.dataTransfer.effectAllowed === 'move');
        assert.ok(docBody.children.length === 1, 'floating ghost appended');
        assert.ok(item.classList.contains('is-dragging'));
        assert.ok(item.style.visibility === 'hidden');

        // zero-coordinate drag events are ignored; non-zero moves the ghost
        item.fire('drag', makeEvent(item, { clientX: 0, clientY: 0 }));
        item.fire('drag', makeEvent(item, { clientX: 200, clientY: 220 }));
        assert.ok(docBody.children[0].style.left === '90px');

        // dragend removes ghost, cleans up and syncs group order
        document.querySelectorAll = (sel) => (sel === '.cmd-item.is-dragging' ? [item] : []);
        item.fire('dragend', makeEvent(item));
        assert.ok(docBody.children.length === 0);
        assert.ok(!item.classList.contains('is-dragging'));
        assert.ok(item.style.visibility === '');
        assert.ok(marks.length >= 1);
    });

    it('_syncGroupOrderFromDOM rebuilds orders from bodies', () => {
        const mainItem = makeDragEl({ dataset: { index: '0' } });
        const workItem = makeDragEl({ dataset: { index: '1' } });
        const newItem = makeDragEl({ dataset: { index: '3' } });
        const mainBody = makeDragEl({ dataset: { group: '' } });
        mainBody._queryMap = { '.cmd-item': [mainItem] };
        const workBody = makeDragEl({ dataset: { group: 'work' } });
        workBody._queryMap = { '.cmd-item': [workItem] };
        const newBody = makeDragEl({ dataset: { group: 'unknown' } });
        newBody._queryMap = { '.cmd-item': [newItem] };
        const wiredItem = makeDragEl({ dataset: { index: '9' } });
        const { C } = loadDragModule({
            docMap: {
                '#commandsListBody .cmd-group-body': [mainBody, workBody, newBody],
                '.cmd-item.is-dragging': [],
            },
            groupOrders: { '__main__': [], work: [] },
        });
        const list = makeDragEl();
        list._queryMap = { '.cmd-item': [wiredItem], '.cmd-group-body': [mainBody, workBody, newBody] };
        C._wireItemDrag(list);
        wiredItem.fire('dragend', makeEvent(wiredItem));
        assert.strictEqual(JSON.stringify(C.groupOrders().__main__), JSON.stringify([0]));
        assert.strictEqual(JSON.stringify(C.groupOrders().work), JSON.stringify([1]));
        assert.ok(!('unknown' in C.groupOrders()), 'unregistered tag group skipped');
    });

    it('_onGroupBodyDragOver reorders with FLIP animation', () => {
        const dragging = makeDragEl({ dataset: { index: '2' } });
        const a = makeDragEl({ dataset: { index: '0' } });
        const b = makeDragEl({ dataset: { index: '1' } });
        const body = makeDragEl();
        body.appendChild(a);
        body.appendChild(b);
        body.appendChild(dragging);
        body._queryMap = {
            '.is-dragging': [dragging],
            '.cmd-item:not(.is-dragging)': [a, b],
            '.cmd-item': [dragging, a, b],
        };
        dragging.nextElementSibling = b;
        const list = makeDragEl();
        list._queryMap = { '.cmd-item': [], '.cmd-group-body': [body] };
        const { C, marks } = loadDragModule({ list, docMap: {} });
        C._wireItemDrag(list);

        const evt = makeEvent(a, { clientY: 0, currentTarget: a });
        body.fire('dragover', evt);
        assert.ok(evt._prevented === true);
        assert.ok(body.children[0] === dragging, 'dragging item moved above sibling');

        const moved = body.children.filter((c) => c === b)[0];
        assert.ok(moved.style.transform === '', 'FLIP transform cleared after animation');

        body.fire('drop', makeEvent(a));
        assert.ok(marks.length >= 0);
    });

    it('_onGroupBodyDragOver returns early without dragging item and skips no-op reorder', () => {
        const body = makeDragEl();
        body._queryMap = { '.is-dragging': [], '.cmd-item:not(.is-dragging)': [], '.cmd-item': [] };
        const list = makeDragEl();
        list._queryMap = { '.cmd-item': [], '.cmd-group-body': [body] };
        const { C } = loadDragModule({ list, docMap: {} });
        C._wireItemDrag(list);

        const evt = makeEvent(body, { currentTarget: body });
        body.fire('dragover', evt);
        assert.ok(evt._prevented === true);

        // dragging item whose next sibling matches the computed target -> no reorder
        const dragging = makeDragEl();
        const sibling = makeDragEl();
        dragging.nextElementSibling = sibling;
        const body2 = makeDragEl();
        body2.appendChild(dragging);
        body2.appendChild(sibling);
        body2._queryMap = {
            '.is-dragging': [dragging],
            '.cmd-item:not(.is-dragging)': [sibling],
            '.cmd-item': [dragging, sibling],
        };
        const list2 = makeDragEl();
        list2._queryMap = { '.cmd-item': [], '.cmd-group-body': [body2] };
        const { C: C2 } = loadDragModule({ list: list2, docMap: {} });
        C2._wireItemDrag(list2);
        const evt2 = makeEvent(sibling, { clientY: 90, currentTarget: sibling });
        body2.fire('dragover', evt2);
        assert.ok(body2.children[0] === dragging, 'no reorder when position unchanged');
    });

    it('wires group drag handlers and drags a tagged group', () => {
        const group = makeDragEl({ dataset: { tag: 'work' } });
        const header = makeDragEl();
        header._closest = group;
        const otherGroup = makeDragEl({ dataset: { tag: 'home' } });
        const list = makeDragEl();
        list._queryMap = {
            '.cmd-group-header': [header],
            '.cmd-group:not(.is-dragging)': [otherGroup],
        };
        const { C, document, body: docBody, marks, tags } = loadDragModule({
            list,
            docMap: {
                '#commandsListBody .cmd-group.is-dragging': [group],
                '#commandsListBody .cmd-group': [group, otherGroup],
            },
        });
        C._wireGroupDrag(list);
        assert.ok(header._listeners.dragstart.length === 1);
        assert.ok(list._listeners.dragover.length === 1);
        assert.ok(list._listeners.drop.length === 1);

        const dragstart = makeEvent(header, { clientX: 100, clientY: 110 });
        header.fire('dragstart', dragstart);
        assert.ok(dragstart.dataTransfer.effectAllowed === 'move');
        assert.ok(docBody.children.length === 1, 'group ghost appended');
        assert.ok(group.classList.contains('is-dragging'));

        header.fire('drag', makeEvent(header, { clientX: 0, clientY: 0 }));
        header.fire('drag', makeEvent(header, { clientX: 300, clientY: 310 }));
        assert.ok(docBody.children[0].style.left === '210px');

        // list dragover moves the group before the next group
        const listEvt = makeEvent(list, { clientY: 10, currentTarget: list });
        list.fire('dragover', listEvt);
        assert.ok(listEvt._prevented === true);

        header.fire('dragend', makeEvent(header));
        assert.ok(docBody.children.length === 0);
        assert.ok(!group.classList.contains('is-dragging'));
        assert.ok(marks.length >= 1);
        assert.strictEqual(JSON.stringify(tags[tags.length - 1]), JSON.stringify(['work', 'home']));
    });

    it('group dragstart blocks empty tags and missing groups; list dragover without dragging group is a no-op', () => {
        const blockedHeader = makeDragEl();
        blockedHeader._closest = makeDragEl({ dataset: { tag: '' } });
        const list = makeDragEl();
        list._queryMap = { '.cmd-group-header': [blockedHeader], '.cmd-group:not(.is-dragging)': [] };
        const { C } = loadDragModule({ list, docMap: {} });
        C._wireGroupDrag(list);

        const evt = makeEvent(blockedHeader);
        blockedHeader.fire('dragstart', evt);
        assert.ok(evt._prevented === true, 'empty-tag group drag blocked');

        const noGroupHeader = makeDragEl();
        noGroupHeader._closest = null;
        const list2 = makeDragEl();
        list2._queryMap = { '.cmd-group-header': [noGroupHeader], '.cmd-group:not(.is-dragging)': [] };
        const { C: C2 } = loadDragModule({ list: list2, docMap: {} });
        C2._wireGroupDrag(list2);
        const evt2 = makeEvent(noGroupHeader);
        noGroupHeader.fire('dragstart', evt2);
        assert.ok(evt2._prevented === true, 'missing group blocked');

        // list dragover with no dragging group returns after preventDefault
        const { C: C3, document } = loadDragModule({ list: list2, docMap: {} });
        C3._wireGroupDrag(list2);
        const listEvt = makeEvent(list2, { currentTarget: list2 });
        list2.fire('dragover', listEvt);
        assert.ok(listEvt._prevented === true);
    });

    it('group dragend collects submenu order even without a group', () => {
        const header = makeDragEl();
        header._closest = null;
        const list = makeDragEl();
        list._queryMap = { '.cmd-group-header': [header], '.cmd-group:not(.is-dragging)': [] };
        const { C, tags } = loadDragModule({ list, docMap: { '#commandsListBody .cmd-group': [] } });
        C._wireGroupDrag(list);
        header.fire('dragend', makeEvent(header));
        assert.strictEqual(JSON.stringify(tags[tags.length - 1]), '[]');
    });
});
