// settings-layout.test.js — Tests for the new settings tab structure:
//   #settingsNav replaces #railLeft when settings are open
//   #settingsCenter replaces chat/dashboard center panel
//   #railRight and #seamRight remain intact (settings don't touch right panel)
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const rightPanelCss = fs.readFileSync(
    path.resolve(__dirname, '..', '..', 'webui', 'css', 'right-panel.css'),
    'utf-8'
);

// =========================================================================
// HTML structure validation — #settingsNav and #settingsCenter
// =========================================================================
describe('index.html settings structure', () => {
    const html = fs.readFileSync(
        path.resolve(__dirname, '..', '..', 'webui', 'index.html'),
        'utf-8'
    );

    it('#settingsNav exists with inline display:none', () => {
        const m = html.match(/<div[^>]*\bid="settingsNav"[^>]*>/);
        assert.ok(m, '#settingsNav must exist');
        assert.ok(m[0].includes('display:none'), '#settingsNav must start hidden (display:none)');
    });

    it('#settingsNav appears after #railLeft closing tag and before #seamLeft', () => {
        const railLeftClose = html.indexOf('</div>', html.indexOf('id="railLeft"'));
        const settingsNavOpen = html.indexOf('id="settingsNav"');
        const seamLeftOpen = html.indexOf('id="seamLeft"');
        assert.ok(railLeftClose > 0, '#railLeft closing tag must exist');
        assert.ok(settingsNavOpen > railLeftClose, '#settingsNav must appear after #railLeft closes');
        assert.ok(settingsNavOpen < seamLeftOpen, '#settingsNav must appear before #seamLeft');
    });

    it('#settingsCenter exists with inline display:none', () => {
        const m = html.match(/<div[^>]*\bid="settingsCenter"[^>]*>/);
        assert.ok(m, '#settingsCenter must exist');
        assert.ok(m[0].includes('display:none'), '#settingsCenter must start hidden (display:none)');
    });

    it('#settingsCenter appears after #dashboard-panel closing tag and before #seamRight', () => {
        const dashClose = html.indexOf('</div>', html.indexOf('id="dashboard-panel"'));
        const settingsCenterOpen = html.indexOf('id="settingsCenter"');
        const seamRightOpen = html.indexOf('id="seamRight"');
        assert.ok(dashClose > 0, '#dashboard-panel closing tag must exist');
        assert.ok(settingsCenterOpen > dashClose, '#settingsCenter must appear after #dashboard-panel closes');
        assert.ok(settingsCenterOpen < seamRightOpen, '#settingsCenter must appear before #seamRight');
    });

    it('#seamRight and #railRight appear after #settingsCenter', () => {
        const settingsCenterOpen = html.indexOf('id="settingsCenter"');
        const seamRightOpen = html.indexOf('id="seamRight"');
        const railRightOpen = html.indexOf('id="railRight"');
        assert.ok(seamRightOpen > settingsCenterOpen, '#seamRight must appear after #settingsCenter');
        assert.ok(railRightOpen > settingsCenterOpen, '#railRight must appear after #settingsCenter');
    });

    it('no settingsWrapper anywhere in the file', () => {
        assert.ok(!html.includes('settingsWrapper'), 'No settingsWrapper should exist');
    });

    it('every settings nav item has a matching section card', () => {
        const navSection = html.substring(
            html.indexOf('id="settingsNav"'),
            html.indexOf('id="settingsCenter"')
        );
        const centerSection = html.substring(
            html.indexOf('id="settingsCenter"'),
            html.indexOf('id="seamRight"')
        );
        // Find all nav items with data-section
        const navItems = navSection.match(/data-section="([^"]+)"/g) || [];
        navItems.forEach(function(match) {
            var sec = match.match(/data-section="([^"]+)"/)[1];
            var cardExists = centerSection.includes('id="sec-' + sec + '"');
            assert.ok(cardExists, 'Nav item data-section="' + sec + '" must have matching sec-' + sec + ' card');
        });
    });

    it('all 9 expected sections exist', () => {
        const expected = ['general', 'ui', 'icons', 'hotkeys', 'menu', 'providers', 'models', 'assistants', 'commands'];
        const centerSection = html.substring(
            html.indexOf('id="settingsCenter"'),
            html.indexOf('id="seamRight"')
        );
        expected.forEach(function(sec) {
            assert.ok(centerSection.includes('id="sec-' + sec + '"'), 'Section sec-' + sec + ' must exist');
        });
    });

    it('setupResize for seamLeft passes a function referencing settingsNav', () => {
        assert.ok(html.includes("setupResize('seamLeft'"), 'setupResize for seamLeft must exist');
        // Get the surrounding 500 chars to verify the function pattern
        var idx = html.indexOf("setupResize('seamLeft'");
        var context = html.substring(idx, idx + 500);
        assert.ok(context.includes('getElementById'), 'seamLeft resolver must use getElementById');
        assert.ok(context.includes('settingsNav'), 'seamLeft resolver must reference settingsNav');
    });

    it('div tag balance check (overall)', () => {
        const openDivs = (html.match(/<div[\s>]/g) || []).length;
        const selfClosing = (html.match(/<div[^>]*\/>/g) || []).length;
        const closeDivs = (html.match(/<\/div>/g) || []).length;
        const netOpens = openDivs - selfClosing;
        assert.strictEqual(netOpens, closeDivs,
            'Div tags must be balanced: ' + netOpens + ' net opens vs ' + closeDivs + ' closes');
    });

    it('#cmdHelpModal exists', () => {
        assert.ok(html.includes('id="cmdHelpModal"'), '#cmdHelpModal must exist in index.html');
    });

    it('every getElementById call in section JS files has matching id in index.html', () => {
        const jsDir = path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections');
        const settingsPanelPath = path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'settings-panel.js');
        var jsFiles = fs.readdirSync(jsDir).filter(function(f) { return f.endsWith('.js'); }).map(function(f) { return path.join(jsDir, f); });
        jsFiles.push(settingsPanelPath);
        // Dynamically-created ids that won't be in index.html static markup
        var ignoreList = [];
        var missing = [];
        jsFiles.forEach(function(filePath) {
            if (!fs.existsSync(filePath)) return;
            var jsContent = fs.readFileSync(filePath, 'utf-8');
            var matches = jsContent.match(/getElementById\s*\(\s*['"]([^'"]+)['"]\s*\)/g);
            if (!matches) return;
            matches.forEach(function(m) {
                var idMatch = m.match(/getElementById\s*\(\s*['"]([^'"]+)['"]\s*\)/);
                if (!idMatch) return;
                var id = idMatch[1];
                if (ignoreList.indexOf(id) >= 0) return;
                if (!html.includes('id="' + id + '"')) {
                    missing.push(filePath.replace(/.*[\/\\]/, '') + ': ' + id);
                }
            });
        });
        assert.deepStrictEqual(missing, [],
            'These getElementById calls have no matching id in index.html: ' + JSON.stringify(missing));
    });
});

describe('right-panel layout', () => {
    it('lets the configuration panel size to its content instead of reserving half the rail', () => {
        assert.match(rightPanelCss, /#rr-session\s*\{[^}]*height:\s*auto;/s);
        assert.doesNotMatch(rightPanelCss, /#rr-session\s*\{[^}]*height:\s*50%/s);
    });
});
