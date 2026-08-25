// capture-screenshots.js — Generate README screenshots from the real app.
//
// Reuses the headless harness machinery (launch.js + seed.js + CDP) to run
// the real AhkLLM app with an isolated profile, then captures WebView2 pages
// via Chrome DevTools Protocol. Nothing flashes on screen: the chat window is
// positioned off-screen, and Page.captureScreenshot reads the rendered page
// directly from the browser surface.
//
// Run: node tests/headless/capture-screenshots.js
// Requires: interactive Windows session, AutoHotkey v2, Node 22+.
// The app must NOT already be running (it is #SingleInstance).
//
// The native AHK command menu is NOT captured here. It lives outside the
// WebView2 page and needs keyboard injection, so that shot is best taken by
// hand over a real document.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { CDP } = require('./cdp');
const launcher = require('./launch');
const { writeSettings, createDb, daysAgo } = require('./seed');
const { runProbe } = require('./scenarios/helpers');

const OUT_DIR = path.join(launcher.REPO_ROOT, 'docs', 'screenshots');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function capture(cdp, name) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  await cdp.send('Page.enable').catch(() => {});
  const res = await cdp.send('Page.captureScreenshot', { format: 'png' });
  if (!res || !res.data) throw new Error('captureScreenshot returned no data for ' + name);
  const out = path.join(OUT_DIR, name + '.png');
  fs.writeFileSync(out, Buffer.from(res.data, 'base64'));
  console.log('saved ' + path.relative(launcher.REPO_ROOT, out));
}

// Deterministic usage rows so the dashboard looks consistent between runs.
function buildUsage() {
  const rows = [];
  const defs = [
    { model: 'deepseek/deepseek-v4-pro', provider: 'deepseek', in: 0.28, out: 0.42 },
    { model: 'deepseek/deepseek-v4-flash', provider: 'deepseek', in: 0.07, out: 0.21 },
    { model: 'openai/gpt-5.4-mini', provider: 'openai', in: 0.15, out: 0.60 },
    { model: 'google/gemini-3.5-flash', provider: 'google', in: 0.10, out: 0.40 }
  ];
  for (let d = 20; d >= 0; d--) {
    const date = daysAgo(d);
    defs.forEach((m, i) => {
      const seed = d * 7 + i * 13;
      const calls = 2 + (seed % 18);
      const promptTokens = 600 + ((seed * 37) % 5200);
      const completionTokens = 300 + ((seed * 53) % 3400);
      const thinkingTokens = m.provider === 'deepseek' ? (seed % 900) : 0;
      const cachedTokens = seed % 5 === 0 ? Math.floor(promptTokens * 0.6) : 0;
      const inputCost = (promptTokens / 1e6) * m.in;
      const cachedInputCost = (cachedTokens / 1e6) * m.in * 0.1;
      const outputCost = (completionTokens / 1e6) * m.out;
      rows.push({
        date, model: m.model, provider: m.provider, call_count: calls,
        prompt_tokens: promptTokens, completion_tokens: completionTokens,
        thinking_tokens: thinkingTokens, cached_tokens: cachedTokens,
        input_cost: Number(inputCost.toFixed(8)),
        cached_input_cost: Number(cachedInputCost.toFixed(8)),
        output_cost: Number(outputCost.toFixed(8)),
        total_cost: Number((inputCost + cachedInputCost + outputCost).toFixed(8)),
        total_response_time_ms: 600 + (seed % 4000),
        total_ttft_ms: 120 + (seed % 600)
      });
    });
  }
  return rows;
}

function seedData(dataDir, endpoint = 'http://127.0.0.1:9') {
  // Providers point at a closed port: screenshots never send live requests.
  const providers = {
    deepseek: {
      displayName: 'DeepSeek', endpoint, fimEndpoint: '', authMode: 'env',
      authEnvVar: 'DEEPSEEK_API_KEY', apiKey: '', icon: '',
      collapseThinking: false, prefixes: ['deepseek']
    },
    openai: {
      displayName: 'OpenAI', endpoint, fimEndpoint: '', authMode: 'env',
      authEnvVar: 'OPENAI_API_KEY', apiKey: '', icon: '',
      collapseThinking: false, prefixes: ['gpt', 'openai']
    },
    google: {
      displayName: 'Google Gemini', endpoint, fimEndpoint: '', authMode: 'env',
      authEnvVar: 'GOOGLE_API_KEY', apiKey: '', icon: '',
      collapseThinking: false, prefixes: ['gemini', 'gemma', 'google']
    },
    openrouter: {
      displayName: 'OpenRouter', endpoint: 'https://openrouter.ai/api/v1/chat/completions',
      fimEndpoint: '', authMode: 'env', authEnvVar: 'OPENROUTER_API_KEY',
      apiKey: '', icon: '', collapseThinking: false, prefixes: ['openrouter']
    }
  };
  writeSettings(dataDir, { providers, threadTitles: { enabled: false } }, endpoint);

  createDb(dataDir, {
    folders: [
      { id: 'f1', name: 'Work' },
      { id: 'f2', name: 'Research' }
    ],
    threads: [
      {
        id: 't1', title: 'Drafting the launch email', folder_id: 'f1',
        active_leaf_id: 'm4', created_at: '2026-08-05 09:00:00',
        cumulative_input_tokens: 15600, cumulative_output_tokens: 4200,
        cumulative_cached_tokens: 900, cumulative_cost: 0.079,
        cumulative_input_cost: 0.041, cumulative_cached_input_cost: 0.004,
        cumulative_output_cost: 0.034
      },
      {
        id: 't2', title: 'Refactor notes', folder_id: null,
        active_leaf_id: 'm10', created_at: '2026-08-04 14:00:00',
        cumulative_input_tokens: 8900, cumulative_output_tokens: 2300,
        cumulative_cached_tokens: 400, cumulative_cost: 0.043,
        cumulative_input_cost: 0.022, cumulative_cached_input_cost: 0.002,
        cumulative_output_cost: 0.019
      },
      {
        id: 't3', title: 'Gemini vs GPT benchmarks', folder_id: 'f2',
        active_leaf_id: 'm14', created_at: '2026-08-03 11:00:00',
        cumulative_input_tokens: 12400, cumulative_output_tokens: 3600,
        cumulative_cached_tokens: 700, cumulative_cost: 0.061,
        cumulative_input_cost: 0.032, cumulative_cached_input_cost: 0.003,
        cumulative_output_cost: 0.026
      }
    ],
    messages: [
      // t1: a conversation with a shallow fork so the tree modal shows both
      // branches inside the capture viewport.
      {
        id: 'm1', thread_id: 't1', role: 'user', parent_id: null,
        sibling_group: 's1', sibling_index: 0, model: 'deepseek/deepseek-v4-pro',
        content: "Here's my draft subject line: \"Our new AI assistant is here.\" Any ideas for a punchier opener?",
        token_count: 25, active_path_tokens: 25, created_at: '2026-08-05 09:01:00'
      },
      {
        id: 'm2', thread_id: 't1', role: 'assistant', parent_id: 'm1',
        sibling_group: 's2', sibling_index: 0, model: 'deepseek/deepseek-v4-pro',
        content: 'Option 1: \"Meet the assistant that lives in your taskbar.\" Option 2: \"One keystroke. Any app. Your AI.\"',
        token_count: 25, active_path_tokens: 50, created_at: '2026-08-05 09:01:20'
      },
      {
        id: 'm2b', thread_id: 't1', role: 'assistant', parent_id: 'm1',
        sibling_group: 's2', sibling_index: 1, model: 'openai/gpt-5.4-mini',
        content: 'Alternative take: lead with the result. \"Drafts, translations, and rewrites without leaving the app you are in.\"',
        token_count: 23, active_path_tokens: 0, created_at: '2026-08-05 09:02:15'
      },
      {
        id: 'm3', thread_id: 't1', role: 'user', parent_id: 'm2',
        sibling_group: 's3', sibling_index: 0, model: 'deepseek/deepseek-v4-pro',
        content: 'Option 1 it is. Now rewrite the closing paragraph.',
        token_count: 12, active_path_tokens: 62, created_at: '2026-08-05 09:03:00'
      },
      {
        id: 'm4', thread_id: 't1', role: 'assistant', parent_id: 'm3',
        sibling_group: 's4', sibling_index: 0, model: 'deepseek/deepseek-v4-pro',
        content: 'Done. New closing: \"Try it once and you will wonder how you worked without it.\" Full draft is ready in the thread.',
        token_count: 26, active_path_tokens: 88, created_at: '2026-08-05 09:03:10'
      },
      // t2: linear refactor notes
      {
        id: 'm7', thread_id: 't2', role: 'user', parent_id: null,
        sibling_group: 's7', sibling_index: 0, model: 'deepseek/deepseek-v4-pro',
        content: 'I found the freeze in the settings reload path.',
        token_count: 10, created_at: '2026-08-04 14:01:00'
      },
      {
        id: 'm8', thread_id: 't2', role: 'assistant', parent_id: 'm7',
        sibling_group: 's8', sibling_index: 0, model: 'deepseek/deepseek-v4-pro',
        content: 'Walk me through the call chain from SaveFromWebView.',
        token_count: 11, created_at: '2026-08-04 14:01:20'
      },
      {
        id: 'm9', thread_id: 't2', role: 'user', parent_id: 'm8',
        sibling_group: 's9', sibling_index: 0, model: 'deepseek/deepseek-v4-pro',
        content: 'The hook re-registers hotkeys before the old ones are released, so the menu opens twice.',
        token_count: 19, created_at: '2026-08-04 14:02:00'
      },
      {
        id: 'm10', thread_id: 't2', role: 'assistant', parent_id: 'm9',
        sibling_group: 's10', sibling_index: 0, model: 'deepseek/deepseek-v4-pro',
        content: 'That matches the double-SuspendBanner repro. Fix: unregister before re-register in HotkeyRegistrar.',
        token_count: 24, created_at: '2026-08-04 14:02:30'
      },
      // t3: benchmark thread
      {
        id: 'm11', thread_id: 't3', role: 'user', parent_id: null,
        sibling_group: 's11', sibling_index: 0, model: 'openai/gpt-5.4-mini',
        content: 'Run the same summarization task on Gemini 3.5 Flash and GPT-5.4 Mini.',
        token_count: 15, created_at: '2026-08-03 11:00:00'
      },
      {
        id: 'm12', thread_id: 't3', role: 'assistant', parent_id: 'm11',
        sibling_group: 's12', sibling_index: 0, model: 'openai/gpt-5.4-mini',
        content: 'Gemini finished in 1.2s at $0.0004. GPT-5.4 Mini finished in 0.9s at $0.0009.',
        token_count: 22, created_at: '2026-08-03 11:00:20'
      },
      {
        id: 'm13', thread_id: 't3', role: 'user', parent_id: 'm12',
        sibling_group: 's13', sibling_index: 0, model: 'openai/gpt-5.4-mini',
        content: 'Now repeat with the full document context, not just the selection.',
        token_count: 14, created_at: '2026-08-03 11:01:00'
      },
      {
        id: 'm14', thread_id: 't3', role: 'assistant', parent_id: 'm13',
        sibling_group: 's14', sibling_index: 0, model: 'openai/gpt-5.4-mini',
        content: 'Same winner, but the gap closes. Full-context cost nearly doubles for both.',
        token_count: 18, created_at: '2026-08-03 11:01:30'
      }
    ],
    chatUsage: buildUsage()
  });
}

async function main() {
  if (launcher.preflight()) {
    throw new Error('AhkLLM is already running. Close it, then rerun.');
  }

  const iso = launcher.isolateProfile();
  let mainPid = 0;
  try {
    launcher.resetDataDir(iso.sandboxData);
    seedData(iso.sandboxData);

    const port = await launcher.findFreePort();
    const launched = launcher.launch({ sandbox: iso.sandboxData, port });
    mainPid = launched.mainPid;

    const target = await launcher.waitForChatTarget(port, 60000);
    const cdp = await CDP.connect(target.webSocketDebuggerUrl);

    // Show the window off-screen and widen it so captures have room to breathe.
    runProbe('show-chat');
    runProbe('resize-chat', ['1600', '900']);
    await sleep(1000);

    await cdp.waitFor(
      'document.querySelectorAll("#thread-list .chat-item").length >= 3',
      60000, 300, 'thread list'
    );

    // Open the branched launch-email thread.
    await cdp.eval(`(() => {
      const el = document.querySelector('.chat-item[data-chat="t1"]');
      if (!el) return false;
      el.click();
      return true;
    })()`);
    await cdp.waitFor(
      'document.body.innerText.includes("rewrite the closing paragraph")',
      30000, 300, 'thread loaded'
    );
    await cdp.waitFor(
      'document.getElementById("tokenBar") && document.getElementById("tokenBar").innerText.includes("88")',
      15000, 300, 'token bar populated'
    );
    await sleep(1500);
    await capture(cdp, 'chat-window');

    // Tree modal.
    await cdp.click('#treeBtn');
    await cdp.waitFor(
      'document.getElementById("treeOverlay") && document.getElementById("treeOverlay").classList.contains("open") && document.querySelectorAll("#treeOverlay .tree-node").length > 0',
      20000, 300, 'tree open'
    );
    await sleep(1000);
    await capture(cdp, 'chat-tree');
    await cdp.eval('(() => { const o = document.getElementById("treeOverlay"); if (o) o.classList.remove("open"); return true; })()');
    await sleep(500);

    // Usage dashboard.
    await cdp.click('#dashboard-icon');
    await cdp.waitFor(
      'document.getElementById("dashboard-panel").style.display === "flex" && document.getElementById("totalCost").textContent !== "$0.00"',
      30000, 300, 'dashboard'
    );
    await sleep(1500);
    await capture(cdp, 'usage-dashboard');
    await cdp.click('#sidebar-toggle');
    await sleep(600);

    // Settings panel, Providers tab (includes the custom OpenRouter card).
    await cdp.click('#settings-icon');
    await cdp.waitFor(
      'document.getElementById("settingsNav").style.display !== "none" && document.getElementById("providerGrid") !== null',
      30000, 300, 'settings open'
    );
    await cdp.click('.settings-nav .nav-item[data-section="providers"]');
    await cdp.waitFor(
      'document.getElementById("providerGrid") && document.getElementById("providerGrid").children.length >= 4',
      20000, 300, 'provider cards'
    );
    await sleep(1000);
    await capture(cdp, 'settings-providers');

    await cdp.close();
    console.log('Screenshots written to docs/screenshots/.');
  } finally {
    launcher.teardown(mainPid);
    const ok = launcher.restoreProfile(iso);
    console.log('Real profile restored:', ok ? 'yes' : 'FAILED');
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('capture-screenshots failed:', err.message);
    process.exitCode = 1;
  });
}

module.exports = { seedData };
