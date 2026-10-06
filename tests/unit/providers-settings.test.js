// providers-settings.test.js — Unit tests for webui/js/settings/sections/providers.js
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

function makeEl(tag, overrides) {
    const el = Object.assign({
        tagName: tag,
        value: '',
        textContent: '',
        className: '',
        type: '',
        innerHTML: '',
        style: {},
        dataset: {},
        children: [],
        parentNode: null,
        classList: makeClassList(),
        disabled: false,
        _listeners: {},
        focused: 0,
        addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); },
        fire(type, event) { (this._listeners[type] || []).forEach((fn) => fn.call(this, event || {})); },
        appendChild(child) { child.parentNode = this; this.children.push(child); return child; },
        insertBefore(node, ref) {
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
        focus() { this.focused++; },
    }, overrides);
    Object.defineProperty(el, 'parentElement', { get() { return el.parentNode; } });
    return el;
}

function wireQueries(el, selectorMap) {
    el.querySelectorAll = (sel) => (selectorMap && selectorMap[sel]) || [];
    el.querySelector = (sel) => ((selectorMap && selectorMap[sel]) || [])[0] || null;
    return el;
}

function loadSection(opts) {
    opts = opts || {};
    const selectorMap = opts.selectorMap || {};
    const docSelectorMap = opts.docSelectorMap || {};
    const elementMap = opts.els || {};
    const registered = [];
    const dirtyCalls = [];
    const domReady = [];

    const panelStub = {
        registerSection(name, mod) { registered.push({ name, mod }); },
        markDirty() { dirtyCalls.push(true); },
    };

    function makeQueriedEl(tag) {
        const el = makeEl(tag);
        wireQueries(el, opts.createSelectorMap ? opts.createSelectorMap() : selectorMap);
        return el;
    }

    const sandbox = {
        document: {
            getElementById(id) {
                if (id === 'providerGrid') return opts.grid || null;
                if (id === 'addProviderBtn') return opts.addBtn || null;
                return elementMap[id] || null;
            },
            querySelectorAll(sel) { return docSelectorMap[sel] || []; },
            createElement(tag) { return makeQueriedEl(tag); },
            addEventListener(type, fn) { if (type === 'DOMContentLoaded') domReady.push(fn); },
        },
        window: {
            SettingsPanel: Object.prototype.hasOwnProperty.call(opts, 'withSettingsPanel') ? opts.withSettingsPanel : panelStub,
            addEventListener() {},
        },
        setTimeout(fn) { fn(); },
        console,
    };
    sandbox.global = sandbox;

    const sharedSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'settings-shared.js'), 'utf8');
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'providers.js'), 'utf8');
    const ctx = vm.createContext(sandbox);
    vm.runInContext(sharedSrc, ctx);
    vm.runInContext(src, ctx);

    return {
        sandbox,
        module: registered[0] && registered[0].mod,
        dirtyCalls,
        fireDomReady() { domReady.forEach((fn) => fn()); },
    };
}

describe('Providers settings section', () => {
    it('offers a preconfigured native Xiaomi provider without replacing saved providers', () => {
        const grid = makeEl('div'), button = makeEl('button');
        grid.querySelectorAll = () => [];
        const ctx = loadSection({grid,els:{addXiaomiProviderBtn:button}});
        ctx.fireDomReady();
        button.fire('click');
        assert.ok(grid.children.some(card=>card.innerHTML.includes('https://api.xiaomimimo.com/v1/chat/completions') && card.innerHTML.includes('MIMO_API_KEY')));
        assert.ok(grid.children.some(card=>card.innerHTML.includes('value="native" selected')));
        assert.ok(ctx.dirtyCalls.length > 0);
    });
    it('renders and saves text mode for any provider without changing transport identity', () => {
        const grid = makeEl('div');
        grid.querySelectorAll = () => [];
        let ctx = loadSection({grid,selectorMap:{}});
        ctx.module.load({providers:{custom:{displayName:'Custom',toolCallingMode:'text-protocol'}}});
        assert.ok(grid.children[0].innerHTML.includes('value="text-protocol" selected'));
        const providerId = makeEl('input',{value:'custom'});
        providerId.dataset.field='providerId';
        const mode = makeEl('select',{value:'text-protocol'});
        mode.dataset.field='toolCallingMode';
        const card = wireQueries(makeEl('div'),{
            '[data-field="providerId"]':[providerId], '[data-field]':[providerId,mode], '.prefix-tags .badge':[]
        });
        ctx=loadSection({docSelectorMap:{'#providerGrid .provider-card':[card]}});
        const saved=ctx.module.save().providers.custom;
        assert.equal(saved.toolCallingMode,'text-protocol');
        assert.equal(saved.transport,'http');
    });
    it('renders provider cards in sorted order and escapes display names', () => {
        const grid = makeEl('div');
        grid.querySelectorAll = () => [];
        const ctx = loadSection({ grid, selectorMap: { '.btn-sm.danger': [makeEl('button')] } });
        ctx.module.load({
            providers: {
                zeta: { displayName: 'Open AI', endpoint: 'https://x' },
                alpha: { displayName: 'Anthropic Claude', endpoint: '' },
                beta: { displayName: 'a&b"c<d>' },
            },
        });
        assert.strictEqual(grid.children.map((c) => c.dataset.providerKey).join(','), 'alpha,beta,zeta');
        assert.ok(grid.children[1].innerHTML.includes('a&amp;b&quot;c&lt;d&gt;'));
    });

    it('renders canonical ChatGPT-plan controls under provider id chatgpt', () => {
        const grid = makeEl('div');
        grid.querySelectorAll = () => [];
        const ctx = loadSection({ grid, selectorMap: {} });
        ctx.module.load({ providers: { chatgpt: { displayName: 'ChatGPT plan', transport: 'chatgpt-responses' } } });
        const html = grid.children[0].innerHTML;
        assert.ok(html.includes('Continue with ChatGPT'));
        assert.ok(html.includes('Refresh models'));
        assert.ok(html.includes('Manage usage'));
        assert.ok(html.includes('ChatGPT may calculate or enforce usage limits differently from Codex CLI'));
        assert.ok(html.includes('chatgpt-sign-out">Sign out</button><a class="btn-sm" href="https://chatgpt.com/#settings/Usage">Manage usage</a>'));
        assert.ok(html.includes('value="chatgpt-responses"'));
        assert.ok(html.includes('value="chatgpt-oauth"'));
        assert.ok(html.includes('value="chatgpt"'));
        assert.ok(html.includes('Check Codex CLI'));
        assert.ok(html.includes('ahkllm.generate_image'));
        const credentialField = 'data-field="' + 'api' + 'Key"';
        assert.ok(!html.includes(credentialField));
    });

    it('applies Codex image-worker status to the ChatGPT-plan provider card', () => {
        const providerId = makeEl('input', { value: 'chatgpt' });
        const transport = makeEl('input', { value: 'chatgpt-responses' });
        const statusEl = makeEl('span');
        const checkBtn = makeEl('button', { disabled: true });
        const card = wireQueries(makeEl('div'), {
            '[data-field="providerId"]': [providerId],
            '[data-field="transport"]': [transport],
            '.codex-status': [statusEl],
            '.check-codex': [checkBtn],
        });
        const ctx = loadSection({ docSelectorMap: { '#providerGrid .provider-card': [card] } });
        ctx.sandbox.window.SettingsProviders.handleCodexStatus({
            installed: true,
            supported: true,
            authenticated: true,
            message: 'Image worker ready.',
        });
        assert.strictEqual(checkBtn.disabled, false);
        assert.ok(statusEl.textContent.includes('ready'));
    });

    it('renders Codex CLI separately from ChatGPT OAuth', () => {
        const grid = makeEl('div');
        grid.querySelectorAll = () => [];
        const ctx = loadSection({ grid, selectorMap: {} });
        ctx.module.load({ providers: {
            codex: { displayName: 'Codex CLI', transport: 'codex-cli' },
            chatgpt: { displayName: 'ChatGPT plan', transport: 'chatgpt-responses' }
        } });
        const html = grid.children.find(card => card.dataset.providerKey === 'codex').innerHTML;
        assert.ok(html.includes('value="codex-cli"'));
        assert.ok(html.includes('Check Codex CLI'));
        assert.ok(html.includes('codex login'));
        assert.ok(!html.includes('Continue with ChatGPT'));
        assert.ok(!html.includes('chatgpt-refresh-models'));
    });

    it('saves Codex CLI authentication without converting it to OAuth', () => {
        const providerId = makeEl('input', { value: 'codex' });
        providerId.dataset.field = 'providerId';
        const transport = makeEl('input', { value: 'codex-cli' });
        transport.dataset.field = 'transport';
        const card = wireQueries(makeEl('div'), {
            '[data-field="providerId"]': [providerId],
            '[data-field]': [providerId, transport],
            '.prefix-tags .badge': []
        });
        const ctx = loadSection({ docSelectorMap: { '#providerGrid .provider-card': [card] } });
        const saved = ctx.module.save().providers.codex;
        assert.strictEqual(saved.transport, 'codex-cli');
        assert.strictEqual(saved.authMode, 'chatgpt');
        assert.strictEqual(saved.endpoint, '');
        assert.strictEqual(saved.apiKey, '');
    });

    it('applies ChatGPT account status without exposing credentials', () => {
        const providerId = makeEl('input', { value: 'chatgpt' });
        const statusEl = makeEl('span');
        const signInBtn = makeEl('button');
        const signOutBtn = makeEl('button');
        const refreshBtn = makeEl('button');
        const select = makeEl('select');
        const card = wireQueries(makeEl('div'), {
            '[data-field="providerId"]': [providerId],
            '.chatgpt-plan-status': [statusEl],
            '.chatgpt-sign-in': [signInBtn],
            '.chatgpt-sign-out': [signOutBtn],
            '.chatgpt-refresh-models': [refreshBtn],
            '.chatgpt-account-select': [select],
        });
        const ctx = loadSection({ docSelectorMap: { '#providerGrid .provider-card': [card] } });
        ctx.sandbox.window.SettingsProviders.handleChatGptPlanStatus({
            authenticated: true,
            clientId: 'client-test',
            email: 'user@example.test',
            accounts: [{ clientId: 'client-test', email: 'user@example.test', active: true }],
            modelCount: 3,
            message: 'Signed in with ChatGPT.',
        });
        assert.ok(statusEl.textContent.includes('3 available models.'));
        assert.strictEqual(signInBtn.textContent, 'Reconnect ChatGPT');
        assert.strictEqual(signOutBtn.disabled, false);
        assert.strictEqual(refreshBtn.disabled, false);
    });

    it('handles missing provider grid and missing provider payload', () => {
        const ctx = loadSection({ grid: null });
        ctx.module.load({ providers: { a: {} } });
        ctx.module.load(null);
        assert.ok(true);
    });

    it('wires switch and remove-button interactions', () => {
        const grid = makeEl('div');
        grid.querySelectorAll = (selector) => selector === '.provider-card' ? grid.children : [];
        const ctx = loadSection({
            grid,
            createSelectorMap() {
                return {
                    '.switch': [makeEl('div', { classList: makeClassList(['switch']) })],
                    '.btn-sm.danger': [makeEl('button')],
                };
            },
        });
        ctx.module.load({ providers: { a: { displayName: 'A' }, b: { displayName: 'B' } } });
        const card = grid.children[0];
        const otherCard = grid.children[1];
        const sw = card.querySelector('.switch');
        const removeBtn = card.querySelector('.btn-sm.danger');
        sw.fire('click');
        assert.ok(sw.classList.contains('on'));
        assert.ok(!otherCard.querySelector('.switch').classList.contains('on'));
        removeBtn.fire('click');
        assert.strictEqual(card.parentNode, null);
        assert.strictEqual(otherCard.parentNode, grid);
        otherCard.querySelector('.btn-sm.danger').fire('click');
        assert.strictEqual(otherCard.parentNode, grid);
        assert.ok(ctx.dirtyCalls.length >= 2);
    });

    it('adds and persists a provider prefix on blur', () => {
        const grid = makeEl('div');
        const prefixDiv = makeEl('div');
        const selectorMap = {
            '.prefix-tags .badge .remove': [],
            '.switch': [],
            'input': [],
            '.btn-sm.danger': [makeEl('button')],
            '.toggle-api-key': [],
            '.prefix-tags': [prefixDiv],
            '.remove': [makeEl('span')],
        };
        const ctx = loadSection({ grid, selectorMap });
        ctx.module.load({ providers: { p: { displayName: 'P', prefixes: [] } } });
        const addLink = prefixDiv.children[prefixDiv.children.length - 1];
        addLink.fire('click');
        const tag = prefixDiv.children[0];
        const input = tag.children[0];
        input.value = 'newprefix';
        input.fire('blur');
        assert.ok(tag.innerHTML.includes('newprefix'));
    });

    it('saves environment-auth provider data', () => {
        const grid = makeEl('div');
        const providerId = makeEl('input', { value: 'prov' });
        providerId.dataset.field = 'providerId';
        const displayName = makeEl('input', { value: 'Provider' });
        displayName.dataset.field = 'displayName';
        const authEnv = makeEl('input', { value: 'MY_PROVIDER_AUTH' });
        authEnv.dataset.field = 'authEnvVar';
        const endpoint = makeEl('input', { value: 'https://example.test/v1/chat/completions' });
        endpoint.dataset.field = 'endpoint';
        const credentialInput = makeEl('input', { value: '' });
        credentialInput.dataset.field = 'api' + 'Key';

        const card = makeEl('div');
        card.dataset.providerKey = 'prov';
        card.dataset.customProvider = 'true';
        wireQueries(card, {
            '[data-field="providerId"]': [providerId],
            '[data-field]': [providerId, displayName, authEnv, endpoint, credentialInput],
            '.prefix-tags .badge': [],
        });

        const ctx = loadSection({ docSelectorMap: { '#providerGrid .provider-card': [card] } });
        const data = JSON.parse(JSON.stringify(ctx.module.save()));
        assert.strictEqual(data.providers.prov.authMode, 'env');
        assert.strictEqual(data.providers.prov.authEnvVar, 'MY_PROVIDER_AUTH');
    });

    it('normalizes a saved ChatGPT-plan provider to OAuth Responses metadata', () => {
        const providerId = makeEl('input', { value: 'chatgpt' });
        providerId.dataset.field = 'providerId';
        const displayName = makeEl('input', { value: 'ChatGPT plan' });
        displayName.dataset.field = 'displayName';
        const transport = makeEl('input', { value: 'chatgpt-responses' });
        transport.dataset.field = 'transport';
        const card = makeEl('div');
        card.dataset.providerKey = 'chatgpt';
        card.dataset.customProvider = 'false';
        wireQueries(card, {
            '[data-field="providerId"]': [providerId],
            '[data-field]': [providerId, displayName, transport],
            '.prefix-tags .badge': [],
        });
        const ctx = loadSection({ docSelectorMap: { '#providerGrid .provider-card': [card] } });
        const data = JSON.parse(JSON.stringify(ctx.module.save()));
        assert.strictEqual(data.providers.chatgpt.transport, 'chatgpt-responses');
        assert.strictEqual(data.providers.chatgpt.authMode, 'chatgpt-oauth');
        assert.strictEqual(data.providers.chatgpt.billingMode, 'chatgpt-subscription');
        assert.strictEqual(data.providers.chatgpt.endpoint, 'https://api.openai.com/v1/responses');
    });

    it('validates ordinary providers but accepts ChatGPT Responses transport without a chat-completions endpoint', () => {
        const missingName = makeEl('input', { value: 'Custom' });
        const missingEndpoint = makeEl('input', { value: '' });
        const customId = makeEl('input', { value: 'custom' });
        const customCard = wireQueries(makeEl('div'), {
            '[data-field="providerId"]': [customId],
            '[data-field="displayName"]': [missingName],
            '[data-field="endpoint"]': [missingEndpoint],
            '[data-field="transport"]': [makeEl('input', { value: 'http' })],
            '[data-field="modelsDevProvider"]': [],
        });

        let ctx = loadSection({ docSelectorMap: { '#providerGrid .provider-card': [customCard] } });
        assert.strictEqual(ctx.module.validate().valid, false);

        const planCard = wireQueries(makeEl('div'), {
            '[data-field="providerId"]': [makeEl('input', { value: 'chatgpt' })],
            '[data-field="displayName"]': [makeEl('input', { value: 'ChatGPT plan' })],
            '[data-field="endpoint"]': [makeEl('input', { value: '' })],
            '[data-field="transport"]': [makeEl('input', { value: 'chatgpt-responses' })],
            '[data-field="modelsDevProvider"]': [],
        });
        ctx = loadSection({ docSelectorMap: { '#providerGrid .provider-card': [planCard] } });
        assert.strictEqual(ctx.module.validate().valid, true);
    });
});
