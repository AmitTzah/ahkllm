// offscreen-demo.js — Off-screen demo clip generator via CDP capture.
//
// Thin scene over scripts/videos/offscreen-pipeline.js: seeds a heavily
// branched conversation, opens it, walks the tree, and tours dashboard +
// settings. Fully autonomous: nothing appears on the user's screen.
//
// Run: node scripts/videos/offscreen-demo.js
'use strict';

const { writeSettings, createDb, daysAgo } = require('../../tests/headless/seed');
const { sleep, interact, caption, captionDrag, preloadTree, openTreeZoomedOut,
  cssCenter, emptyTreePoint, clampInWrap, startCapture, encodeClip, runOffscreenScene } = require('./offscreen-pipeline');

// A large, heavily branched conversation so the tree demo needs panning.
function buildComplexSeed(dataDir, endpoint = 'http://127.0.0.1:9') {
  writeSettings(dataDir, { threadTitles: { enabled: false } }, endpoint);
  const t = '2026-08-06 ';
  const mk = (id, thread, role, parent, sg, si, model, content, time, apt = 0) => ({
    id, thread_id: thread, role, parent_id: parent || null,
    sibling_group: sg, sibling_index: si, model,
    content, token_count: content.split(' ').length,
    active_path_tokens: apt, created_at: time
  });
  createDb(dataDir, {
    folders: [
      { id: 'f1', name: 'Work' },
      { id: 'f2', name: 'Research' }
    ],
    threads: [
      {
        id: 't1', title: 'Drafting the launch email', folder_id: 'f1',
        active_leaf_id: 'm14', created_at: t + '09:00:00',
        cumulative_input_tokens: 24500, cumulative_output_tokens: 6800,
        cumulative_cached_tokens: 1500, cumulative_cost: 0.143,
        cumulative_input_cost: 0.082, cumulative_cached_input_cost: 0.006,
        cumulative_output_cost: 0.055
      },
      {
        id: 't2', title: 'Refactor notes', folder_id: null,
        active_leaf_id: 'm17', created_at: t + '10:00:00',
        cumulative_input_tokens: 8900, cumulative_output_tokens: 2300,
        cumulative_cached_tokens: 400, cumulative_cost: 0.043,
        cumulative_input_cost: 0.022, cumulative_cached_input_cost: 0.002,
        cumulative_output_cost: 0.019
      },
      {
        id: 't3', title: 'Gemini vs GPT benchmarks', folder_id: 'f2',
        active_leaf_id: 'm19', created_at: t + '11:00:00',
        cumulative_input_tokens: 12400, cumulative_output_tokens: 3600,
        cumulative_cached_tokens: 700, cumulative_cost: 0.061,
        cumulative_input_cost: 0.032, cumulative_cached_input_cost: 0.003,
        cumulative_output_cost: 0.026
      }
    ],
    messages: [
      mk('m1', 't1', 'user', null, 's1', 0, 'deepseek/deepseek-v4-pro', "Let's take the launch email from the first line to the last.", t + '09:01:00', 12),
      mk('m2', 't1', 'assistant', 'm1', 's2', 0, 'deepseek/deepseek-v4-pro', 'Happy to. I will read it top to bottom and suggest cuts.', t + '09:01:10', 23),
      mk('m3', 't1', 'user', 'm2', 's3', 0, 'deepseek/deepseek-v4-pro', 'Start with the subject line and the opening.', t + '09:02:00', 30),
      mk('m4', 't1', 'assistant', 'm3', 's4', 0, 'deepseek/deepseek-v4-pro', 'Opening A: Meet the assistant that lives in your taskbar.', t + '09:02:10', 39),
      mk('m5', 't1', 'assistant', 'm3', 's4', 1, 'openai/gpt-5.4-mini', 'Opening B: What if every app could answer back?', t + '09:02:12'),
      mk('m6', 't1', 'assistant', 'm3', 's4', 2, 'google/gemini-3.5-flash', 'Opening C: One keystroke. Any app. Your AI.', t + '09:02:14'),
      mk('m7', 't1', 'user', 'm4', 's5', 0, 'deepseek/deepseek-v4-pro', 'Take opening A and tighten the body.', t + '09:03:00', 46),
      mk('m8', 't1', 'assistant', 'm7', 's6', 0, 'deepseek/deepseek-v4-pro', 'Body v1: two short paragraphs, each under 60 words.', t + '09:03:10', 54),
      mk('m9', 't1', 'assistant', 'm7', 's6', 1, 'openai/gpt-5.4-mini', 'Body v2: lead with the result, then one proof point.', t + '09:03:12'),
      mk('m10', 't1', 'user', 'm8', 's7', 0, 'deepseek/deepseek-v4-pro', 'Good. Now rewrite the closing to ask for a trial.', t + '09:04:00', 63),
      mk('m11', 't1', 'assistant', 'm10', 's8', 0, 'deepseek/deepseek-v4-pro', 'Closing v1: Try it once and you will wonder how you worked without it.', t + '09:04:10', 75),
      mk('m11b', 't1', 'assistant', 'm10', 's8', 1, 'openai/gpt-5.4-mini', 'Closing v2: Start your free trial in under a minute.', t + '09:04:12'),
      mk('m13', 't1', 'user', 'm11', 's9', 0, 'deepseek/deepseek-v4-pro', 'Add a P.S. about the free trial.', t + '09:05:00', 82),
      mk('m14', 't1', 'assistant', 'm13', 's10', 0, 'deepseek/deepseek-v4-pro', 'P.S. added: Free for the first 30 days, no card required.', t + '09:05:10', 93),
      mk('m14b', 't1', 'assistant', 'm13', 's10', 1, 'google/gemini-3.5-flash', 'P.S. alt: No credit card. Cancel anytime.', t + '09:05:12'),
      mk('m15', 't1', 'user', 'm9', 's11', 0, 'openai/gpt-5.4-mini', 'Body v2 it is. Trim the second paragraph.', t + '09:06:00'),
      mk('m16', 't1', 'assistant', 'm15', 's12', 0, 'openai/gpt-5.4-mini', 'Trimmed to one sentence.', t + '09:06:10'),
      mk('m30', 't1', 'assistant', 'm15', 's12', 1, 'openai/gpt-5.4-mini', 'Or cut it entirely and keep one strong paragraph.', t + '09:06:12'),
      mk('m31u', 't1', 'user', 'm16', 's27', 0, 'openai/gpt-5.4-mini', 'Good. Now make it shorter.', t + '09:06:20'),
      mk('m32u', 't1', 'assistant', 'm31u', 's28', 0, 'openai/gpt-5.4-mini', 'Shorter: Trimmed to one line.', t + '09:06:30'),
      mk('m17', 't1', 'user', 'm5', 's13', 0, 'openai/gpt-5.4-mini', 'Opening B needs a supporting line.', t + '09:07:00'),
      mk('m18', 't1', 'assistant', 'm17', 's14', 0, 'openai/gpt-5.4-mini', 'Supporting line: because you never leave the app you are in.', t + '09:07:10'),
      mk('m19', 't1', 'assistant', 'm17', 's14', 1, 'openai/gpt-5.4-mini', 'Alt: because the answer comes to you, not the other way.', t + '09:07:12'),
      mk('m20', 't1', 'user', 'm18', 's15', 0, 'openai/gpt-5.4-mini', 'Use the alt line and shorten it.', t + '09:08:00'),
      mk('m21', 't1', 'assistant', 'm20', 's16', 0, 'openai/gpt-5.4-mini', 'Shortened: The answer comes to you.', t + '09:08:10'),
      mk('m31', 't1', 'assistant', 'm20', 's16', 1, 'openai/gpt-5.4-mini', 'Even shorter: Answers, where you already are.', t + '09:08:12'),
      mk('m22', 't1', 'user', 'm6', 's17', 0, 'google/gemini-3.5-flash', 'Opening C reads flat. Warm it up.', t + '09:09:00'),
      mk('m23', 't1', 'assistant', 'm22', 's18', 0, 'google/gemini-3.5-flash', 'Warmed: One keystroke and your AI is right there.', t + '09:09:10'),
      mk('m16t', 't2', 'user', null, 't1', 0, 'deepseek/deepseek-v4-pro', 'I found the freeze in the settings reload path.', t + '10:01:00'),
      mk('m17t', 't2', 'assistant', 'm16t', 't2', 0, 'deepseek/deepseek-v4-pro', 'Walk me through the call chain from SaveFromWebView.', t + '10:01:10'),
      mk('m18t', 't3', 'user', null, 'u1', 0, 'openai/gpt-5.4-mini', 'Run the summarization task on both models.', t + '11:01:00'),
      mk('m19t', 't3', 'assistant', 'm18t', 'u2', 0, 'openai/gpt-5.4-mini', 'Gemini: 1.2s. GPT-5.4 Mini: 0.9s. Same quality.', t + '11:01:10')
    ],
    chatUsage: [
      { date: daysAgo(1), model: 'deepseek/deepseek-v4-pro', provider: 'deepseek', call_count: 12, prompt_tokens: 3200, completion_tokens: 900, thinking_tokens: 200, cached_tokens: 400, input_cost: 0.0009, cached_input_cost: 0.00004, output_cost: 0.00038, total_cost: 0.00132, total_response_time_ms: 4200, total_ttft_ms: 900 },
      { date: daysAgo(0), model: 'openai/gpt-5.4-mini', provider: 'openai', call_count: 8, prompt_tokens: 2100, completion_tokens: 700, thinking_tokens: 0, cached_tokens: 150, input_cost: 0.0003, cached_input_cost: 0.00001, output_cost: 0.00042, total_cost: 0.00073, total_response_time_ms: 2600, total_ttft_ms: 500 }
    ]
  });
}

async function main() {
  await runOffscreenScene({
    outName: 'poc.mp4',
    seedFn: buildComplexSeed,
    mock: null,
    async body({ cdp, cap, viewport }) {
      await caption(cdp, 'Welcome to AhkLLM', 1500);

      await interact(cdp, 'Open a conversation', 1200, `document.querySelector('.chat-item[data-chat="t1"]')`, 900);
      await cdp.waitFor('typeof chatMessages !== "undefined" && chatMessages.length > 0', 15000, 300, 'thread opened');
      await sleep(1400);

      // Pre-fetch the tree data so the modal opens already populated.
      await preloadTree(cdp);

      await interact(cdp, 'The tree keeps every branch', 1000, `document.querySelector('#treeBtn')`, 700, openTreeZoomedOut(cdp));
      await cdp.waitFor('document.querySelectorAll("#treeOverlay .tree-node").length >= 24', 20000, 300, 'tree');
      await sleep(600);

      // One quick drag that pans the tree toward the target branch.
      const targetNode = await cssCenter(cdp, `document.querySelector('.tree-node[data-target="m9"]')`);
      const p1 = await emptyTreePoint(cdp);
      if (targetNode && p1) {
        const to = await clampInWrap(cdp, {
          x: p1.x - (targetNode.x - viewport.w / 2),
          y: p1.y - (targetNode.y - viewport.h / 2)
        });
        await captionDrag(cdp, 'Drag to a branch', 1100, p1, to, 600, 650);
      }
      await sleep(400);
      await interact(cdp, 'Click a middle reply', 1100, `document.querySelector('.tree-node[data-target="m9"]')`, 700);
      await cdp.waitFor(
        'chatMessages.length > 0 && chatMessages[chatMessages.length - 1].id === "m32u" && chatMessages.some(m => m.id === "m9")',
        20000, 300, 'snapped to m9'
      );
      await sleep(1600);

      await interact(cdp, 'Usage at a glance', 1400, `document.querySelector('#dashboard-icon')`, 800);
      await sleep(900);
      await cdp.waitFor('document.getElementById("dashboard-panel").style.display === "flex"', 20000, 300, 'dashboard');
      await sleep(1000);

      await interact(cdp, 'Back to chat', 900, `document.querySelector('#sidebar-toggle')`, 700);
      await cdp.waitFor('document.getElementById("chat-layout").style.display !== "none"', 15000, 300, 'chat back');
      await sleep(700);

      await interact(cdp, 'Everything is configurable', 1500, `document.querySelector('#settings-icon')`, 800);
      await cdp.waitFor('document.getElementById("settingsNav").style.display !== "none"', 15000, 300, 'settings open');
      await sleep(1300);

      await caption(cdp, 'That is AhkLLM', 1800);
      await sleep(1700);

      await cap.stop();
      const fps = cap.fps();
      const frameCount = cap.count();
      console.log('captured ' + frameCount + ' frames in ' + cap.elapsed().toFixed(1) + 's (' + fps.toFixed(1) + ' fps)');
      const finalPath = await encodeClip(cap.framesDir, frameCount, fps, 'poc.mp4');
      console.log('PoC written: ' + finalPath + ' (' + (require('node:fs').statSync(finalPath).size / 1048576).toFixed(1) + ' MB, ' + fps.toFixed(1) + ' fps)');
    }
  });
}

if (require.main === module) {
  main().catch((err) => {
    console.error('poc-offscreen failed:', err.message);
    process.exitCode = 1;
  });
}

module.exports = { buildComplexSeed };
