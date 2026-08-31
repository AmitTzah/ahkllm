// offscreen-pipeline.js — Shared machinery for off-screen demo clips.
//
// Node drives an in-page cursor (eased bezier paths) and an in-page caption
// bubble, captures frames on a timer with Page.captureScreenshot, and encodes
// JPEG frames straight into libx264 (the static ffmpeg build's swscale is
// broken for rgb->yuv). Nothing appears on screen.
//
// Extracted from the off-screen demo generator so every clip shares the same
// verified click/caption/capture/encode path.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawn } = require('node:child_process');
const { CDP } = require('../../tests/headless/cdp');
const launcher = require('../../tests/headless/launch');
const { runProbe } = require('../../tests/headless/scenarios/helpers');
const { startMockServer } = require('../../tests/headless/mock-llm-server');

const FFMPEG = path.join(__dirname, '..', '..', '.tools', 'ffmpeg', 'bin', 'ffmpeg.exe');
const OUT_DIR = path.join(__dirname, '..', '..', 'docs', 'videos');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Hard per-scene budget. Video takes can run for minutes, so the default is
// generous; verification passes a short timeout to prove hangs are reaped.
const DEFAULT_SCENE_TIMEOUT_MS = 20 * 60 * 1000;
// Children spawned by this process (ffmpeg encodes). The emergency cleanup
// kills them so a force-exit can never leave an orphaned encoder behind.
const activeChildren = new Set();

// In-page UI injected into the WebView: cursor, caption bubble, token-bar CSS.
const INJECT_UI = `(() => {
  if (document.getElementById('vcursor')) return;
  const s = document.createElement('style');
  s.textContent = '.token-bar{justify-content:flex-end;gap:6px 16px;font-size:11px}.tu-val{font-size:12px}.tu-icon{width:13px;height:13px}.topbar{flex-wrap:wrap}';
  document.head.appendChild(s);
  const c = document.createElement('div');
  c.id = 'vcursor';
  c.style.cssText = 'position:fixed;left:0;top:0;width:24px;height:24px;pointer-events:none;z-index:2147483647;' +
    'background:url("data:image/svg+xml;utf8,<svg xmlns=\\'http://www.w3.org/2000/svg\\' width=\\'24\\' height=\\'24\\' viewBox=\\'0 0 24 24\\'><path d=\\'M4 2l16 9-7 2-3 7z\\' fill=\\'white\\' stroke=\\'%23111\\' stroke-width=\\'1.5\\'/></svg>") no-repeat;';
  document.body.appendChild(c);
  window.__setCursor = (x, y) => {
    c.style.left = x + 'px';
    c.style.top = y + 'px';
  };
  window.__vcursorPress = () => {
    c.style.transform = 'translateY(1px) scale(0.94)';
    setTimeout(() => { c.style.transform = ''; }, 120);
  };
  window.__flashTarget = (el) => {
    if (!el) return;
    el.style.outline = '3px solid rgba(59,130,246,0.85)';
    el.style.outlineOffset = '2px';
    setTimeout(() => {
      el.style.outline = '';
      el.style.outlineOffset = '';
    }, 600);
  };
  const d = document.createElement('div');
  d.id = 'vcaption';
  d.style.cssText = 'position:fixed;top:30px;left:50%;transform:translateX(-50%);background:rgba(0,0,0,0.8);' +
    'color:#fff;font:600 17px Segoe UI,sans-serif;padding:7px 14px;border-radius:9px;' +
    'z-index:2147483646;opacity:0;transition:opacity .15s;pointer-events:none;white-space:normal;' +
    'max-width:50vw;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.35);';
  document.body.appendChild(d);
  const a = document.createElement('div');
  a.id = 'vcaption-arrow';
  a.style.cssText = 'position:absolute;left:50%;width:10px;height:10px;background:rgba(0,0,0,0.8);' +
    'transform:translateX(-50%) rotate(45deg);display:none;';
  d.appendChild(a);
  window.__showCaption = (text, anchor) => {
    d.style.transform = 'none';
    d.textContent = text;
    d.style.left = '0';
    d.style.top = '0';
    const w = d.offsetWidth;
    const h = d.offsetHeight;
    let l, t;
    let place = 'none';
    if (anchor && anchor.l != null && anchor.t != null) {
      const cx = (anchor.l + anchor.r) / 2;
      l = cx - w / 2;
      const above = anchor.t - h - 14;
      if (above >= 12) { t = above; place = 'above'; }
      else { t = anchor.b + 14; place = 'below'; }
    } else if (anchor && anchor.x != null) {
      l = anchor.x - w / 2;
      const above = anchor.y - h - 14;
      if (above >= 12) { t = above; place = 'above'; }
      else { t = anchor.y + 20; place = 'below'; }
    } else {
      l = (window.innerWidth - w) / 2;
      t = 30;
    }
    l = Math.max(10, Math.min(window.innerWidth - w - 10, l));
    t = Math.max(10, Math.min(window.innerHeight - h - 10, t));
    d.style.left = l + 'px';
    d.style.top = t + 'px';
    a.style.display = place === 'none' ? 'none' : 'block';
    if (place === 'above') {
      a.style.top = h - 4 + 'px';
      a.style.bottom = 'auto';
    } else if (place === 'below') {
      a.style.bottom = h - 4 + 'px';
      a.style.top = 'auto';
    }
    d.style.opacity = '1';
  };
  window.__hideCaption = () => { d.style.opacity = '0'; };
})()`;

// ---- Node-side eased bezier cursor math (mirrors the AHK driver) ----
let move = null;
let draggingCursor = null;

function beginMove(x, y, dur) {
  const x0 = move ? move.x1 : 800;
  const y0 = move ? move.y1 : 450;
  const dx = x - x0, dy = y - y0;
  const dist = Math.hypot(dx, dy);
  const off = Math.min(dist * 0.12, 60);
  const px = dist > 0 ? -dy / dist : 0;
  const py = dist > 0 ? dx / dist : 0;
  move = {
    x0, y0, x1: x, y1: y,
    cx: (x0 + x) / 2 + px * off,
    cy: (y0 + y) / 2 + py * off,
    start: Date.now(), dur
  };
}

function cursorAt(now) {
  if (!move) return { x: 800, y: 450 };
  const t = Math.min(1, (now - move.start) / move.dur);
  const tt = t < 0.5 ? 16 * Math.pow(t, 5) : 1 - Math.pow(-2 * t + 2, 5) / 2;
  return {
    x: (1 - tt) * (1 - tt) * move.x0 + 2 * (1 - tt) * tt * move.cx + tt * tt * move.x1,
    y: (1 - tt) * (1 - tt) * move.y0 + 2 * (1 - tt) * tt * move.cy + tt * tt * move.y1
  };
}

// ---- Encode JPEG frames straight into libx264 (no swscale) ----
function encodeFrames(framesDir, frameCount, fps, outPath) {
  return new Promise((resolve, reject) => {
    const args = [
      '-y', '-f', 'image2pipe', '-c:v', 'mjpeg', '-framerate', fps.toFixed(3), '-i', '-',
      '-vf', 'crop=trunc(iw/2)*2:trunc(ih/2)*2',
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-movflags', '+faststart',
      outPath
    ];
    const proc = spawn(FFMPEG, args, { stdio: ['pipe', 'ignore', 'pipe'] });
    activeChildren.add(proc);
    let errBuf = '';
    proc.stderr.on('data', (d) => { errBuf += d; });
    proc.on('error', (e) => { activeChildren.delete(proc); reject(e); });
    proc.stdin.on('error', () => {});
    proc.on('exit', (code) => {
      activeChildren.delete(proc);
      if (code === 0) resolve();
      else reject(new Error('encode failed (' + code + '): ' + errBuf.slice(-600)));
    });
    const writeFrame = (i) => {
      if (i >= frameCount) { try { proc.stdin.end(); } catch {} return; }
      const buf = fs.readFileSync(path.join(framesDir, String(i).padStart(6, '0') + '.jpg'));
      if (!proc.stdin.write(buf)) proc.stdin.once('drain', () => writeFrame(i + 1));
      else writeFrame(i + 1);
    };
    writeFrame(0);
  });
}

// ---- Real-input helpers (every click verified via elementFromPoint) ----
async function cssCenter(cdp, getTargetExpr) {
  const r = await cdp.eval(`(() => {
    const el = (${getTargetExpr});
    if (!el) return null;
    const b = el.getBoundingClientRect();
    return { x: b.left + b.width / 2, y: b.top + b.height / 2 };
  })()`);
  if (!r) throw new Error('target not found: ' + getTargetExpr);
  return r;
}

async function bringIntoView(cdp, getTargetExpr) {
  await cdp.eval(`(() => {
    const el = (${getTargetExpr});
    if (el && el.scrollIntoView) el.scrollIntoView({ block: 'center', inline: 'center' });
    return true;
  })()`);
  await sleep(200);
}

async function rectOf(cdp, getTargetExpr) {
  return await cdp.eval(`(() => {
    const el = (${getTargetExpr});
    if (!el) return null;
    const b = el.getBoundingClientRect();
    return { l: b.left, r: b.right, t: b.top, b: b.bottom };
  })()`);
}

async function verifyHit(cdp, getTargetExpr, x, y) {
  return await cdp.eval(`(() => {
    const target = (${getTargetExpr});
    const el = document.elementFromPoint(${x}, ${y});
    return !!(target && el && (el === target || target.contains(el) || el.contains(target)));
  })()`);
}

// Real Input.dispatchMouseEvent click at the target center. Verifies the hit
// with elementFromPoint immediately before pressing; aborts if it fails.
async function clickTarget(cdp, getTargetExpr, opts = {}) {
  await bringIntoView(cdp, getTargetExpr);
  let r = await cssCenter(cdp, getTargetExpr);
  let hit = await verifyHit(cdp, getTargetExpr, r.x, r.y);
  if (!hit) {
    r = await cssCenter(cdp, getTargetExpr);
    hit = await verifyHit(cdp, getTargetExpr, r.x, r.y);
  }
  if (!hit) throw new Error('cursor not over target before click: ' + getTargetExpr);
  console.log('click verified at ' + Math.round(r.x) + ',' + Math.round(r.y) + ': ' + hit);
  await cdp.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: r.x, y: r.y });
  await sleep(60);
  await cdp.send('Input.dispatchMouseEvent', { type: 'mousePressed', x: r.x, y: r.y, button: 'left', clickCount: 1 });
  await sleep(80);
  await cdp.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: r.x, y: r.y, button: 'left', clickCount: 1 });
  await cdp.eval(`(() => {
    const el = (${getTargetExpr});
    if (el) window.__flashTarget(el);
    window.__vcursorPress();
    return true;
  })()`);
  if (opts.afterClick) await opts.afterClick();
}

// Captioned interaction: show the caption anchored to the target, move the
// cursor, click, hold, hide the caption.
async function interact(cdp, text, textDur, getTargetExpr, moveDur, afterClick) {
  const rect = await rectOf(cdp, getTargetExpr);
  await cdp.eval(`window.__showCaption(${JSON.stringify(text)}, ${JSON.stringify(rect)})`);
  const r = await cssCenter(cdp, getTargetExpr);
  beginMove(r.x, r.y, moveDur);
  await sleep(moveDur + 250);
  await clickTarget(cdp, getTargetExpr, { afterClick });
  await sleep(textDur);
  await cdp.eval('window.__hideCaption()');
}

// Type into an input by focusing it with a real click, then inserting
// characters one at a time so the take shows real typing.
async function animateType(cdp, selector, text, perCharMs = 28) {
  const getInput = `document.querySelector(${JSON.stringify(selector)})`;
  await clickTarget(cdp, getInput);
  await cdp.eval(`(() => { const el = document.querySelector(${JSON.stringify(selector)}); if (el) el.focus(); return true; })()`);
  await sleep(120);
  for (const ch of text) {
    await cdp.send('Input.insertText', { text: ch });
    await sleep(perCharMs);
  }
}

// ---- Tree helpers ----
async function dragTree(cdp, from, to, steps = 12) {
  draggingCursor = { x: from.x, y: from.y };
  await cdp.eval(`window.__setCursor(${from.x.toFixed(1)}, ${from.y.toFixed(1)})`);
  await cdp.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: from.x, y: from.y });
  await sleep(80);
  await cdp.send('Input.dispatchMouseEvent', { type: 'mousePressed', x: from.x, y: from.y, button: 'left', clickCount: 1 });
  await sleep(80);
  for (let i = 1; i <= steps; i++) {
    const x = from.x + (to.x - from.x) * (i / steps);
    const y = from.y + (to.y - from.y) * (i / steps);
    draggingCursor = {
      x: x + Math.sin(i * 1.3) * 1.2,
      y: y + Math.cos(i * 0.9) * 1.2
    };
    await cdp.eval(`window.__setCursor(${draggingCursor.x.toFixed(1)}, ${draggingCursor.y.toFixed(1)})`);
    await cdp.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, button: 'left', buttons: 1 });
    await sleep(35);
  }
  await cdp.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: to.x, y: to.y, button: 'left', clickCount: 1 });
  draggingCursor = null;
  await sleep(150);
}

async function caption(cdp, text, dur, anchor) {
  await cdp.eval(`window.__showCaption(${JSON.stringify(text)}, ${anchor ? JSON.stringify(anchor) : 'null'})`);
  await sleep(dur);
  await cdp.eval('window.__hideCaption()');
}

// QA: a failed stream shows a red banner in the chat view. No take may contain
// one, so scenes assert its absence after every LLM interaction.
async function assertNoErrorBanners(cdp) {
  const found = await cdp.eval(`(() => {
    return [...document.querySelectorAll('body *')]
      .filter((el) => {
        const r = el.getBoundingClientRect();
        const t = (el.textContent || '').trim();
        return r.width > 0 && r.height > 0 && t.length > 0 && t.length < 200 && /Request failed|Error/i.test(t);
      })
      .map((e) => e.textContent.trim().slice(0, 80));
  })()`);
  if (found && found.length) throw new Error('error banner present in take: ' + JSON.stringify(found));
}

// QA: the token bar must show the seeded cumulative/active-path numbers.
async function assertTokenBar(cdp, expectedPart) {
  await cdp.waitFor(
    'document.getElementById("tokenBar") && document.getElementById("tokenBar").innerText.includes(' + JSON.stringify(expectedPart) + ')',
    15000, 300, 'token bar shows ' + expectedPart
  );
}

async function emptyTreePoint(cdp) {
  return cdp.eval(`(() => {
    const wrap = document.getElementById('treeCanvasWrap');
    if (!wrap) return null;
    const w = wrap.getBoundingClientRect();
    const nodes = [...document.querySelectorAll('#treeOverlay .tree-node')].map((n) => {
      const r = n.getBoundingClientRect();
      return { l: r.left, r: r.right, t: r.top, b: r.bottom };
    });
    for (let i = 0; i < 60; i++) {
      const x = w.left + 50 + Math.random() * Math.max(1, w.width - 100);
      const y = w.top + 50 + Math.random() * Math.max(1, w.height - 100);
      const hit = nodes.some((n) => x >= n.l && x <= n.r && y >= n.t && y <= n.b);
      if (!hit) return { x, y };
    }
    return null;
  })()`);
}

async function clampInWrap(cdp, pt) {
  return cdp.eval(`(() => {
    const el = document.getElementById('treeCanvasWrap');
    if (!el) return ${JSON.stringify(pt)};
    const r = el.getBoundingClientRect();
    return {
      x: Math.min(r.right - 20, Math.max(r.left + 20, ${pt.x})),
      y: Math.min(r.bottom - 20, Math.max(r.top + 20, ${pt.y}))
    };
  })()`);
}

async function captionDrag(cdp, text, textDur, from, to, moveDur, dragMs) {
  await cdp.eval(`window.__showCaption(${JSON.stringify(text)}, ${JSON.stringify({ x: from.x, y: from.y })})`);
  beginMove(from.x, from.y, moveDur);
  await sleep(moveDur + 250);
  await dragTree(cdp, from, to, Math.max(6, Math.round(dragMs / 35)));
  await sleep(textDur);
  await cdp.eval('window.__hideCaption()');
}

// Pre-fetch the tree data so the modal opens already populated, and zoom out
// in the modal's afterClick hook so the whole tree is visible from frame one.
async function preloadTree(cdp) {
  await cdp.eval(`Ipc.postToHost('sidebarAction', { subAction: 'loadTree' })`);
  await cdp.waitFor('window._treeData && window._treeData.length > 0', 15000, 300, 'tree data cached');
}

function openTreeZoomedOut(cdp) {
  return () => cdp.eval(`(() => {
    if (window._treeData && document.querySelectorAll('#treeOverlay .tree-node').length === 0) renderChatTree(window._treeData);
    const b = document.getElementById('zoomOut');
    for (let i = 0; i < 4; i++) b.click();
    return true;
  })()`);
}

// ---- Capture loop: JPEG screenshots on a ~50ms timer ----
function startCapture(cdp) {
  const framesDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ahkllm-frames-'));
  let frameIndex = 0;
  let capturing = true;
  const t0 = Date.now();
  const tick = async () => {
    if (!capturing) return;
    try {
      const p = draggingCursor || cursorAt(Date.now());
      await cdp.eval(`window.__setCursor(${p.x.toFixed(1)}, ${p.y.toFixed(1)})`);
      const res = await cdp.send('Page.captureScreenshot', { format: 'jpeg', quality: 85 });
      if (res && res.data) {
        fs.writeFileSync(path.join(framesDir, String(frameIndex++).padStart(6, '0') + '.jpg'), Buffer.from(res.data, 'base64'));
      }
    } catch (e) {
      // A failure AFTER stop() (teardown closing the CDP socket mid-tick) is
      // expected; a failure while the scene is still running is fatal.
      if (capturing) throw e;
      return;
    }
    if (capturing) setTimeout(tick, 50);
  };
  tick();
  return {
    framesDir,
    stop: async () => { capturing = false; await sleep(300); },
    count: () => frameIndex,
    elapsed: () => (Date.now() - t0) / 1000,
    fps: () => Math.max(1, frameIndex / Math.max(0.1, (Date.now() - t0) / 1000))
  };
}

async function encodeClip(framesDir, frameCount, fps, outName) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const finalPath = path.join(OUT_DIR, outName);
  await encodeFrames(framesDir, frameCount, fps, finalPath);
  fs.rmSync(framesDir, { recursive: true, force: true });
  return finalPath;
}

// ---- Full scene: preflight, worker sandbox, seed, mock, launch, viewport, capture ----
// seedFn(dataDir, endpoint) writes settings + DB. mock is
// { mode, opts } passed to startMockServer. body({ cdp, cap, viewport }) runs
// the scene steps; it must stop the capture and encode via encodeClip itself
// (so scenes control the final fps/duration). timeoutMs bounds the whole scene
// (default 20 min); a hang past it triggers guaranteed cleanup + hard exit.
async function runOffscreenScene({ outName, seedFn, mock, body, timeoutMs = DEFAULT_SCENE_TIMEOUT_MS }) {
  // Self-healing sweep: a previous run that hung (or was force-killed) must
  // not leave orphaned offscreen Node processes or temp dirs behind. E2E app
  // processes are cleaned by their worker marker below; this sweep never kills
  // a normal AhkLLM instance. Runs BEFORE preflight so stale scene artifacts do
  // not obscure the diagnostic.
  const swept = launcher.sweepOffscreenArtifacts();
  if (swept && swept !== 'nothing to clean up')
    console.log('[' + outName + '] self-healing sweep: ' + swept);

  console.log('[' + outName + '] preflight...');
  if (launcher.preflight()) {
    throw new Error('AhkLLM is still running after the self-healing sweep. Close it, then rerun.');
  }

  console.log('[' + outName + '] creating worker sandbox...');
  const worker = launcher.createWorkerContext('offscreen-' + process.pid + '-' + Date.now().toString(36));
  let mainPid = 0;
  let server = null;
  let cdp = null;
  let cap = null;
  let watchdog = null;
  let cleanedUp = false;

  // ONE cleanup path shared by normal completion, scene errors, watchdog
  // timeouts, unhandled rejections and uncaught exceptions: close the CDP
  // socket, kill spawned children, close the mock server (force-dropping
  // keep-alive SSE connections), and tear down only this worker's app/artifacts.
  const cleanup = async (reason) => {
    if (cleanedUp) return;
    cleanedUp = true;
    if (watchdog) clearTimeout(watchdog);
    if (reason) console.error('[' + outName + '] cleaning up after: ' + reason);
    try { if (cap) await cap.stop(); } catch {}
    try { if (cdp) await cdp.close(); } catch {}
    for (const child of activeChildren) { try { child.kill(); } catch {} }
    activeChildren.clear();
    try {
      if (server) {
        const srv = server.server;
        if (srv.closeAllConnections) srv.closeAllConnections();
        if (srv.closeIdleConnections) srv.closeIdleConnections();
        await new Promise((resolve) => {
          srv.close(() => resolve());
          // A stuck keep-alive socket must not block the guaranteed cleanup.
          setTimeout(resolve, 2000).unref();
        });
      }
    } catch {}
    const processOk = launcher.teardownWorker(mainPid, worker.workerId);
    const artifactOk = launcher.disposeWorkerContext(worker);
    if (!processOk || !artifactOk)
      console.error('[' + outName + '] worker cleanup incomplete');
  };

  // Hard per-scene watchdog: if anything keeps the event loop alive past
  // timeoutMs (a CDP wait, a capture, an encode, a stuck promise), clean up
  // and force-exit instead of leaking the process holding the mock port.
  watchdog = setTimeout(() => {
    console.error('[' + outName + '] SCENE TIMEOUT after ' + Math.round(timeoutMs / 1000) + 's - forcing cleanup + exit');
    cleanup('watchdog timeout').finally(() => process.exit(1));
  }, timeoutMs);
  watchdog.unref(); // failsafe only - never keeps the process alive by itself

  // Crash handlers: convert unhandled rejections/exceptions into the same
  // guaranteed cleanup + exit instead of an orphaned process.
  const onUnhandledRejection = (reason) => {
    if (cleanedUp) return; // late stray after the scene already finished
    console.error('[' + outName + '] unhandled rejection: ' + (reason && reason.stack ? reason.stack : reason));
    cleanup('unhandled rejection').finally(() => process.exit(1));
  };
  const onUncaughtException = (err) => {
    if (cleanedUp) return; // late stray after the scene already finished
    console.error('[' + outName + '] uncaught exception: ' + (err && err.stack ? err.stack : err));
    cleanup('uncaught exception').finally(() => process.exit(1));
  };
  process.on('unhandledRejection', onUnhandledRejection);
  process.on('uncaughtException', onUncaughtException);

  try {
    launcher.resetDataDir(worker.dataDir);
    let endpoint = 'http://127.0.0.1:9';
    if (mock) {
      console.log('[' + outName + '] starting mock server...');
      const started = await startMockServer(mock.mode, mock.logFile || '', mock.opts);
      server = started.server;
      endpoint = 'http://127.0.0.1:' + started.port + '/v1/chat/completions';
    }
    console.log('[' + outName + '] seeding data dir...');
    seedFn(worker.dataDir, endpoint);

    const port = await launcher.findFreePort();
    console.log('[' + outName + '] launching app (port ' + port + ')...');
    const launched = launcher.launch({ sandbox: worker.dataDir, port, workerId: worker.workerId, mainScript: worker.mainScript });
    mainPid = launched.mainPid;

    console.log('[' + outName + '] waiting for chat target...');
    const target = await launcher.waitForChatTarget(port, 60000, launched);
    cdp = await CDP.connect(target.webSocketDebuggerUrl);
    runProbe('show-chat');
    await sleep(1500);

    console.log('[' + outName + '] waiting for thread list...');
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length >= 3', 60000, 300, 'threads');
    console.log('[' + outName + '] injecting UI + expanding viewport...');
    await cdp.eval(INJECT_UI);
    // The app auto-collapses both rails when outerWidth/screen.availWidth looks
    // small. Force the default expanded widths at a 1920x1080 layout viewport.
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false
    }).catch(() => {});
    await sleep(400);
    await cdp.eval(`(() => {
      const l = document.getElementById('railLeft');
      const r = document.getElementById('railRight');
      if (l) { l.style.width = '340px'; l.style.transition = 'none'; l.classList.remove('mini'); }
      if (r) { r.style.width = '400px'; r.style.transition = 'none'; }
      return true;
    })()`);
    await sleep(400);
    const viewport = await cdp.eval('({ w: window.innerWidth, h: window.innerHeight })');
    cap = startCapture(cdp);
    try {
      return await body({ cdp, cap, viewport, outName });
    } catch (e) {
      try { await cap.stop(); } catch {}
      try { fs.rmSync(cap.framesDir, { recursive: true, force: true }); } catch {}
      throw e;
    } finally {
      try { await cap.stop(); } catch {}
    }
  } finally {
    try { await cleanup(); } finally {
      process.removeListener('unhandledRejection', onUnhandledRejection);
      process.removeListener('uncaughtException', onUncaughtException);
    }
  }
}

// Run a scene from a script FILE as a child process with a hard timeout.
// Fixed scenes should live in scripts/videos/ and be run directly; this is
// the cleanup-guaranteeing wrapper for agent-generated one-offs: the child is
// bounded, whatever it left behind is swept, and the temp file is deleted
// afterward. Returns { outcome, swept }.
async function runSceneFile(scriptPath, { timeoutMs = DEFAULT_SCENE_TIMEOUT_MS } = {}) {
  const child = spawn(process.execPath, [scriptPath], {
    stdio: 'inherit',
    cwd: path.join(__dirname, '..', '..')
  });
  const outcome = await new Promise((resolve) => {
    const timer = setTimeout(() => {
      try { child.kill(); } catch {}
      resolve('killed-after-timeout');
    }, timeoutMs);
    child.once('exit', (code, signal) => {
      clearTimeout(timer);
      resolve(signal ? 'signal-' + signal : 'exit-' + code);
    });
    child.once('error', (err) => {
      clearTimeout(timer);
      resolve('spawn-error: ' + err.message);
    });
  });
  // Backstop: a force-killed child never ran its own cleanup, so reap only
  // marked E2E workers before sweeping offscreen artifacts.
  launcher.killAllE2EProcesses();
  const swept = launcher.sweepOffscreenArtifacts();
  try { fs.unlinkSync(scriptPath); } catch {}
  return { outcome, swept };
}

module.exports = {
  FFMPEG, OUT_DIR, INJECT_UI, sleep,
  beginMove, cursorAt,
  encodeFrames, cssCenter, bringIntoView, rectOf, verifyHit, clickTarget,
  interact, animateType, dragTree, caption, assertNoErrorBanners, assertTokenBar, emptyTreePoint, clampInWrap,
  captionDrag, preloadTree, openTreeZoomedOut, startCapture, encodeClip,
  runOffscreenScene, runSceneFile, DEFAULT_SCENE_TIMEOUT_MS
};
