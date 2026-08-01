// models-pricing-refresh.test.js — Regression test for the "Fetch Latest Models" flow.
//
// The AHK side (chat/callbacks/Dispatch.ahk) sends full multi-line entries from
// scripts/models_metadata.txt as `raw`. The WebUI must extract pricing, context,
// and feature toggles from that raw text. Broken previously because raw only
// contained the model-name line ("provider/model", {) with no pricing fields.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModule() {
    const src = fs.readFileSync(
        path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'models.js'),
        'utf-8'
    );
    const sandbox = {
        document: {
            getElementById: () => null,
            querySelectorAll: () => [],
            createElement: () => ({
                style: {},
                querySelectorAll: () => [],
                addEventListener: () => {},
                appendChild: () => {}
            }),
            addEventListener: () => {}
        },
        window: {
            chrome: { webview: { postMessage: () => {} } },
            SettingsPanel: { registerSection: () => {} },
            addEventListener: () => {}
        },
        setTimeout: () => {},
        clearTimeout: () => {},
        console
    };
    sandbox.global = sandbox;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox.window.SettingsModels;
}

describe('SettingsModels.parsePricingRaw', () => {
    it('extracts pricing from a full multi-line metadata entry (Refresh-Models.ps1 output)', () => {
        const SM = loadModule();
        const raw = [
            '    "deepseek/deepseek-chat", {',
            '        provider: "deepseek", api: "openai-completions",',
            '        compat: Map("thinkingFormat", "deepseek", "supportsReasoningEffort", true),',
            '        thinkingLevelMap: Map("high", "high", "max", "max"),',
            '        thinkingOff: "disabled",',
            '        input: 0.14, cachedInput: 0.0028, output: 0.28, context: 1000000, reasoning: true, vision: false',
            '    },'
        ].join('\n');
        const p = SM.parsePricingRaw(raw);
        assert.strictEqual(p.input, 0.14);
        assert.strictEqual(p.cachedInput, 0.0028);
        assert.strictEqual(p.output, 0.28);
        assert.strictEqual(p.context, 1000000);
        assert.strictEqual(p.reasoning, true);
        assert.strictEqual(p.vision, false);
    });

    it('returns empty pricing for a bare entry header (old broken raw)', () => {
        const SM = loadModule();
        const p = SM.parsePricingRaw('    "openai/gpt-5", {');
        assert.strictEqual(p.input, undefined);
        assert.strictEqual(p.context, undefined);
        assert.strictEqual(p.reasoning, false);
        assert.strictEqual(p.vision, false);
    });
});
