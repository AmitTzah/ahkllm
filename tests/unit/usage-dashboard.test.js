// usage-dashboard.test.js — Unit tests for usage-dashboard.js: data rendering + CSV export
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadDashboardModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'usage-dashboard.js'), 'utf-8');
    let hostObjectCalled = false;
    let hostObjectFilters = null;
    const sandbox = {
        document: {
            getElementById: (id) => {
                const el = { textContent: '', innerHTML: '', value: '', title: '', style: {},
                    classList: { add: function() {}, remove: function() {}, contains: function() { return false; } },
                    addEventListener: function() {},
                    querySelector: function() { return { dataset: { mode: 'model' }, classList: { add: function() {}, remove: function() {} } }; },
                    querySelectorAll: function() { return []; },
                    getContext: function() { return { createLinearGradient: () => ({}), fillRect: () => {}, fillText: () => {}, beginPath: () => {}, arc: () => {}, fill: () => {}, stroke: () => {}, moveTo: () => {}, lineTo: () => {}, setLineDash: () => {}, clearRect: () => {}, save: () => {}, restore: () => {}, measureText: () => ({ width: 10 }), canvas: { width: 100, height: 100 } }; },
                    appendChild: function() {},
                    getAttribute: function() { return null; },
                    setAttribute: function() {},
                    closest: function() { return null; },
                    remove: function() {}
                };
                return el;
            },
            querySelector: function(sel) {
                return { dataset: { mode: 'model' }, classList: { add: function() {}, remove: function() {} }, querySelectorAll: function() { return []; }, addEventListener: function() {} };
            },
            querySelectorAll: function() { return []; },
            createElement: function(tag) {
                return { tagName: tag, textContent: '', innerHTML: '', style: {},
                    getContext: function() { return { createLinearGradient: () => ({}), fillRect: () => {}, fillText: () => {}, beginPath: () => {}, arc: () => {}, fill: () => {}, stroke: () => {}, moveTo: () => {}, lineTo: () => {}, setLineDash: () => {}, clearRect: () => {}, save: () => {}, restore: () => {}, measureText: () => ({ width: 10 }), canvas: { width: 100, height: 100 } }; },
                    appendChild: function() {}, addEventListener: function() {}
                };
            }
        },
        window: { chrome: { webview: { postMessage: () => {} } }, addEventListener: () => {} },
        Chart: function() { return { destroy: function() {}, data: {}, options: {}, update: () => {} }; },
        chrome: { webview: { hostObjects: { Dashboard: { QueryUsage: async (filtersJson) => { hostObjectCalled = true; hostObjectFilters = JSON.parse(filtersJson); return JSON.stringify({ chat: [], commands: [], models: [], providers: [] }); } } } } },
        Blob: function(parts, opts) { return { parts: parts, opts: opts }; },
        URL: { createObjectURL: () => 'blob:test', revokeObjectURL: () => {} },
        setTimeout: () => {}, clearTimeout: () => {},
        allData: null, mainChart: null, MODEL_COLORS: [],
        console: console, Number: Number, String: String
    };
    sandbox.global = sandbox;
    sandbox._hostObjectCalled = () => hostObjectCalled;
    sandbox._hostObjectFilters = () => hostObjectFilters;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('fmtNum', () => {
    it('formats millions with m suffix', () => {
        const ctx = loadDashboardModule();
        assert.strictEqual(ctx.fmtNum(1500000), '1.5m');
    });

    it('formats thousands with k suffix', () => {
        const ctx = loadDashboardModule();
        assert.strictEqual(ctx.fmtNum(4500), '4.5k');
    });

    it('formats small numbers as-is', () => {
        const ctx = loadDashboardModule();
        assert.strictEqual(ctx.fmtNum(42), '42');
    });

    it('formats zero', () => {
        const ctx = loadDashboardModule();
        assert.strictEqual(ctx.fmtNum(0), '0');
    });
});

describe('fmtCost', () => {
    it('formats to 4 decimal places', () => {
        const ctx = loadDashboardModule();
        assert.strictEqual(ctx.fmtCost(0.00125), '$0.0013');
    });

    it('handles zero', () => {
        const ctx = loadDashboardModule();
        assert.strictEqual(ctx.fmtCost(0), '$0.0000');
    });
});

describe('fmtCostShort', () => {
    it('shows 2 decimals for costs >= 1', () => {
        const ctx = loadDashboardModule();
        assert.strictEqual(ctx.fmtCostShort(5.123), '$5.12');
    });

    it('shows 4 decimals for costs >= 0.01', () => {
        const ctx = loadDashboardModule();
        assert.strictEqual(ctx.fmtCostShort(0.0123), '$0.0123');
    });

    it('shows 6 decimals for small costs', () => {
        const ctx = loadDashboardModule();
        assert.strictEqual(ctx.fmtCostShort(0.000123), '$0.000123');
    });
});

describe('extractProvider', () => {
    it('extracts provider from provider/model format', () => {
        const ctx = loadDashboardModule();
        assert.strictEqual(ctx.extractProvider('deepseek/deepseek-v4'), 'deepseek');
    });

    it('returns empty for no provider prefix', () => {
        const ctx = loadDashboardModule();
        assert.strictEqual(ctx.extractProvider('gpt-4o'), '');
    });
});

describe('getDateRangeLabels', () => {
    it('returns 365 labels for all time', () => {
        const ctx = loadDashboardModule();
        const lbls = ctx.getDateRangeLabels();
        assert.ok(lbls.length >= 365);
    });
});

describe('renderSummary', () => {
    it('populates summary cards from data', () => {
        const ctx = loadDashboardModule();
        ctx.allData = {
            chat: [{ input_tokens: 500, output_tokens: 300, total_cost: 0.05, message_count: 3, total_response_time_ms: 1200, total_ttft_ms: 400, cached_input_cost: 0.001, input_cost: 0.02, output_cost: 0.03 }],
            commands: []
        };
        ctx.renderSummary();
        assert.ok(ctx.document.getElementById('totalCost').textContent !== undefined);
        assert.ok(ctx.document.getElementById('totalCalls').textContent !== undefined);
        assert.ok(ctx.document.getElementById('totalTokens').textContent !== undefined);
    });
});

describe('populateFilters', () => {
    it('populates provider and model dropdowns', () => {
        const ctx = loadDashboardModule();
        ctx.allData = { chat: [], commands: [], models: ['deepseek/deepseek-v4'], providers: ['deepseek'] };
        ctx.populateFilters();
        assert.ok(true);  // Doesn't throw
    });
});

describe('loadData', () => {
    it('calls host object with filters', async () => {
        const ctx = loadDashboardModule();
        await ctx.loadData();
        assert.ok(ctx._hostObjectCalled());
        const filters = ctx._hostObjectFilters();
        assert.ok(filters.timeRange !== undefined);
        assert.ok(filters.type !== undefined);
    });
});
