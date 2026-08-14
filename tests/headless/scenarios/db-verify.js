"use strict";
// scenarios/db-verify.js — Thorough DB verification via headless experiments + direct state reads.
const fs=require("node:fs");
const path=require("node:path");
const os=require("node:os");
const { spawn, spawnSync } = require("node:child_process");
const { DatabaseSync } = require("node:sqlite");
const seed=require("../seed");
const launcher=require("../launch");
const { sleep, showChat, waitStreamingIdle } = require("./helpers");
const scenarios=[];
scenarios.push({
  id: 104,
  regression: true,
  name: "DB health: schema, indexes, FTS, foreign keys intact",
  mode: null,
  noApp: true,
  async body(){
    const os=require("os");
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),"db-health-"));
    const dbPath=seed.createDb(dir,{ threads:[{id:"t1",title:"x"}], messages:[{id:"m1",thread_id:"t1",role:"user",content:"hi"}]});
    function q(sql){ return seed.query(dbPath, sql); }
    const tables=q("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").map(r=>r.name);
    for(const t of ["chat_threads","messages","message_attachments","chat_usage","command_usage","chat_locks"]) if(!tables.includes(t)) throw new Error("missing "+t);
    const cols=q("PRAGMA table_info(chat_threads)").map(r=>r.name);
    for(const c of ["cumulative_cost","font_size","folder_id","advanced_toggles","is_locked"]) if(!cols.includes(c)) throw new Error("missing col "+c);
    const w=new DatabaseSync(dbPath); w.exec("INSERT INTO messages_fts(msg_id, content) VALUES ('probe','hello FTS world')"); w.close();
    if(q("SELECT * FROM messages_fts WHERE messages_fts MATCH 'hello'").length!==1) throw new Error("FTS");
    if(q("SELECT COUNT(*) as c FROM messages WHERE thread_id NOT IN (SELECT id FROM chat_threads)")[0].c!==0) throw new Error("orphan");
    if(!/ON DELETE CASCADE/.test(fs.readFileSync(path.join(launcher.REPO_ROOT,"chat/db/ChatDB.ahk"),"utf8"))) throw new Error("CASCADE");
    return "schema OK, FTS OK, no orphans";
  }
});
scenarios.push({
  id: 105,
  regression: true,
  name: "DB live: HardDelete re-parents, clears FTS, recomputes cumulative counters (bug #65 fixed)",
  mode: null,
  settings:{},
  fixtures:{
    threads:[{id:"t-hard-105", title:"HardDelete Test", active_leaf_id:"m104", cumulative_input_tokens:10, cumulative_output_tokens:20, cumulative_cost:1.5}],
    messages:[
      {id:"m101", thread_id:"t-hard-105", role:"user", content:"hello", token_count:5, active_path_tokens:5},
      {id:"m102", thread_id:"t-hard-105", role:"assistant", content:"hi", model:"openai/gpt-4", parent_id:"m101", token_count:10, active_path_tokens:15},
      {id:"m103", thread_id:"t-hard-105", role:"user", content:"follow", parent_id:"m102", token_count:5, active_path_tokens:20},
      {id:"m104", thread_id:"t-hard-105", role:"assistant", content:"answer", model:"openai/gpt-4", parent_id:"m103", token_count:10, active_path_tokens:30},
    ]
  },
  async body({cdp, dbPath}){
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length>0',15000,300,"list");
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length>=4',15000,300,"loaded");
    await sleep(700);
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Delete"]');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null',5000,200,"confirm");
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(900);
    const msgs=seed.query(dbPath,"SELECT id, parent_id FROM messages WHERE thread_id='t-hard-105' ORDER BY created_at");
    if(msgs.find(m=>m.id==="m102")) throw new Error("m102 not deleted");
    const m103=msgs.find(m=>m.id==="m103");
    if(!m103 || m103.parent_id!=="m101") throw new Error("m103 not reparented "+JSON.stringify(m103));
    const thread=seed.query(dbPath,"SELECT active_leaf_id, cumulative_cost FROM chat_threads WHERE id='t-hard-105'")[0];
    // FIXED (bug #65): the counters are recomputed from the remaining
    // messages instead of staying stale at the seeded 1.5.
    if(Number(thread.cumulative_cost)===1.5) throw new Error("cumulative still stale 1.5 "+JSON.stringify(thread));
    if(seed.query(dbPath,"SELECT * FROM messages_fts WHERE msg_id='m102'").length) throw new Error("FTS not cleared");
    const m104Ap=seed.query(dbPath,"SELECT active_path_tokens FROM messages WHERE id='m104'")[0].active_path_tokens;
    if(Number(m104Ap)!==20) throw new Error("active_path "+m104Ap);
    const input=seed.query(dbPath,"SELECT cumulative_input_tokens FROM chat_threads WHERE id='t-hard-105'")[0].cumulative_input_tokens;
    if(Number(input)!==10) throw new Error("recomputed cumulative_input_tokens should be 10, got "+input);
    return "HardDelete OK: reparent, FTS cleared, cumulative recomputed ("+input+" input tokens, cost "+thread.cumulative_cost+"), active_path 20";
  }
});
scenarios.push({
  id: 106,
  regression: true,
  name: "DB live: Fork copies messages and keeps folder/font; cumulative counters recomputed from the fork's own messages (bugs #58/#48/#126)",
  mode: null,
  settings:{},
  fixtures:{
    folders:[{id:"f106", name:"Folder106"}],
    threads:[{id:"t-fork-106", title:"Fork Src", active_leaf_id:"m202", folder_id:"f106", font_size:20, cumulative_input_tokens:10, cumulative_cost:2.0}],
    messages:[
      {id:"m201", thread_id:"t-fork-106", role:"user", content:"hello", token_count:5, active_path_tokens:5},
      {id:"m202", thread_id:"t-fork-106", role:"assistant", content:"hi", model:"openai/gpt-4", parent_id:"m201", token_count:10, active_path_tokens:15},
    ]
  },
  async body({cdp, dbPath}){
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length>0',15000,300,"list");
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length>=2',15000,300,"loaded");
    await sleep(600);
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Fork"]');
    await cdp.waitFor('window.activeThreadId !== "t-fork-106"',15000,300,"forked");
    const nid=await cdp.eval('window.activeThreadId');
    await sleep(600);
    const fork=seed.query(dbPath,"SELECT folder_id, cumulative_cost, cumulative_input_tokens, cumulative_output_tokens, font_size FROM chat_threads WHERE id=?",[nid])[0];
    const cnt=seed.query(dbPath,"SELECT COUNT(*) as c FROM messages WHERE thread_id=?",[nid])[0].c;
    // Forked from the assistant message: the copy holds u1 + a1.
    if(cnt!==2) throw new Error("cnt "+cnt);
    // FIXED (bug #58/#48/#126): the fork keeps the source folder and font size
    // (per-message context is still copied), but the cumulative counters are
    // RECOMPUTED from the fork's own messages - only a1's API call (5 input /
    // 10 output), never the source thread's full ledger (cost 2.0).
    if(fork.folder_id!=="f106") throw new Error("folder not kept "+JSON.stringify(fork));
    if(Number(fork.font_size)!==20) throw new Error("font size not kept "+JSON.stringify(fork));
    if(Number(fork.cumulative_input_tokens)!==5 || Number(fork.cumulative_output_tokens)!==10) throw new Error("counters not recomputed "+JSON.stringify(fork));
    if(Number(fork.cumulative_cost)===2.0) throw new Error("source cost still copied "+JSON.stringify(fork));
    return "fork "+nid+" msgs "+cnt+" folder/font kept, counters recomputed (5/10), source cost 2.0 NOT copied";
  }
});
scenarios.push({
  id: 117,
  name: "Deleting a message that holds the same attachment file twice orphans the file on disk (ref-count sees 2 rows)",
  regression: true, // FIXED bug kept as a regression check (duplicate attachment rows must not orphan the file)
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-att-117', title: 'Dup Attach', active_leaf_id: 'm-117-u1' }],
    messages: [{ id: 'm-117-u1', thread_id: 't-att-117', role: 'user', content: 'duplicate attachment message' }]
  },
  async body({ cdp, dbPath, dataDir }) {
    // Physical file + TWO attachment rows sharing the same content-addressable
    // path (the UI allows attaching the same file twice; hash-based filenames
    // make both rows point at one file).
    const fs = require("node:fs");
    const path = require("node:path");
    const { DatabaseSync } = require("node:sqlite");
    const attDir = path.join(dataDir, "attachments");
    fs.mkdirSync(attDir, { recursive: true });
    const filePath = "attachments/dupfile-117.txt";
    fs.writeFileSync(path.join(dataDir, filePath), "duplicate content");
    const db = new DatabaseSync(dbPath, { enableForeignKeyConstraints: false });
    db.prepare("INSERT INTO message_attachments (id, message_id, attachment_type, file_path, mime_type, original_filename, file_size, extracted_text) VALUES ('a-117-1','m-117-u1','text_file',?,'text/plain','dup.txt',17,'')").run(filePath);
    db.prepare("INSERT INTO message_attachments (id, message_id, attachment_type, file_path, mime_type, original_filename, file_size, extracted_text) VALUES ('a-117-2','m-117-u1','text_file',?,'text/plain','dup.txt',17,'')").run(filePath);
    db.close();

    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, "list");
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, "loaded");
    await sleep(700);
    await cdp.click('#chat-messages .msg .msg-action-btn[title="Delete"]');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, "confirm");
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(900);

    const rows = seed.query(dbPath, "SELECT COUNT(*) AS c FROM message_attachments WHERE message_id='m-117-u1'")[0].c;
    const msgGone = seed.query(dbPath, "SELECT COUNT(*) AS c FROM messages WHERE id='m-117-u1'")[0].c === 0;
    const fileStillThere = fs.existsSync(path.join(dataDir, filePath));
    // FIXED (bug #117): _DeleteFileIfOrphaned now runs AFTER the batch row
    // delete - with 2 rows for the same path the file is removed once both
    // rows are gone, instead of both rows seeing refs=2 and orphaning the file.
    if (rows !== 0 || !msgGone || fileStillThere)
      throw new Error('orphan state not cleaned: rows=' + rows + ' msgGone=' + msgGone + ' fileStillThere=' + fileStillThere + ' (file should be removed with the rows)');
    return 'message deleted, 0 attachment rows left, and the physical file at ' + filePath + ' was removed with them';
  }
});
scenarios.push({
  id: 131,
  regression: true, // attachment lifecycle audit: cross-thread sharing + fork + trash + file refcount
  name: 'Attachment files stay reference-counted across forks, thread trash and cross-thread sharing (audit)',
  mode: null,
  settings: {},
  fixtures: {
    threads: [
      { id: 't-src-131', title: 'Src', active_leaf_id: 'm-131-a1' },
      { id: 't-other-131', title: 'Other', active_leaf_id: 'm-131-u1b' }
    ],
    messages: [
      { id: 'm-131-u1', thread_id: 't-src-131', role: 'user', content: 'root', token_count: 10, active_path_tokens: 10 },
      { id: 'm-131-a1', thread_id: 't-src-131', role: 'assistant', content: 'reply', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-131-u1', token_count: 5, active_path_tokens: 15 },
      { id: 'm-131-u1b', thread_id: 't-other-131', role: 'user', content: 'other root', token_count: 10, active_path_tokens: 10 }
    ]
  },
  async body({ cdp, dbPath, dataDir }) {
    const fs = require('node:fs');
    const path = require('node:path');
    const { DatabaseSync } = require('node:sqlite');
    // One physical file shared by the source thread's message, the OTHER
    // thread's message, and later the fork (content-addressable storage).
    const attDir = path.join(dataDir, 'attachments');
    fs.mkdirSync(attDir, { recursive: true });
    const filePath = 'attachments/shared-131.txt';
    fs.writeFileSync(path.join(dataDir, filePath), 'shared content');
    const db = new DatabaseSync(dbPath, { enableForeignKeyConstraints: false });
    const insAtt = db.prepare("INSERT INTO message_attachments (id, message_id, attachment_type, file_path, mime_type, original_filename, file_size, extracted_text) VALUES (?,?,?,?,?,?,?,?)");
    insAtt.run('a-131-1', 'm-131-u1', 'text_file', filePath, 'text/plain', 'shared.txt', 14, '');
    insAtt.run('a-131-2', 'm-131-u1b', 'text_file', filePath, 'text/plain', 'shared.txt', 14, '');
    db.close();

    await showChat();
    // 1. Load the source thread, fork at a1 (the fork copies the attachment row).
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 2', 15000, 300, 'thread loaded');
    await sleep(700);
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Fork"]');
    await cdp.waitFor('window.activeThreadId !== "t-src-131"', 15000, 300, 'fork created');
    const forkId = await cdp.eval('window.activeThreadId');
    await sleep(700);
    let refs = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [filePath])[0].c;
    if (refs !== 3) throw new Error('after fork refs should be 3 (src + other + fork), got ' + refs);
    if (!fs.existsSync(path.join(dataDir, filePath))) throw new Error('file vanished after fork');

    // 2. Trash + permanently delete the SOURCE thread (its rows drop; file stays via the other refs).
    await cdp.eval(`(() => {
      const items = [...document.querySelectorAll('#thread-list .chat-item')];
      const it = items.find((el) => el.getAttribute('data-chat') === 't-src-131');
      if (!it) return false;
      it.querySelector('.chat-action-btn.danger').click();
      return true;
    })()`);
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'trash confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(800);
    await cdp.waitFor('document.querySelectorAll(".trash-item").length >= 1', 10000, 250, 'trash item');
    await cdp.click('.trash-item button.danger');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'delete forever confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(800);
    refs = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [filePath])[0].c;
    if (refs !== 2) throw new Error('after deleting source thread refs should be 2 (fork + other), got ' + refs);
    if (!fs.existsSync(path.join(dataDir, filePath))) throw new Error('file deleted while fork/other still reference it');

    // 3. Load the OTHER thread and delete it forever; file must still exist (fork ref).
    await cdp.eval(`(() => {
      const items = [...document.querySelectorAll('#thread-list .chat-item')];
      const it = items.find((el) => el.getAttribute('data-chat') === 't-other-131');
      if (!it) return false;
      it.click();
      return true;
    })()`);
    await cdp.waitFor('chatMessages.length >= 1 && chatMessages[0] && chatMessages[0].content === "other root"', 15000, 300, 'other thread loaded');
    await sleep(600);
    await cdp.eval(`(() => {
      const items = [...document.querySelectorAll('#thread-list .chat-item')];
      const it = items.find((el) => el.getAttribute('data-chat') === 't-other-131');
      if (!it) return false;
      it.querySelector('.chat-action-btn.danger').click();
      return true;
    })()`);
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'trash confirm 2');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(800);
    await cdp.click('.trash-item button.danger');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'delete forever confirm 2');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(800);
    refs = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [filePath])[0].c;
    if (refs !== 1) throw new Error('after deleting other thread refs should be 1 (fork), got ' + refs);
    if (!fs.existsSync(path.join(dataDir, filePath))) throw new Error('file deleted while the fork still references it');

    // 4. Load the fork and delete its root message; the file becomes orphaned and must be removed.
    await cdp.eval(`(() => {
      const items = [...document.querySelectorAll('#thread-list .chat-item')];
      const it = items.find((el) => el.getAttribute('data-chat') === '${forkId}');
      if (!it) return false;
      it.click();
      return true;
    })()`);
    await cdp.waitFor('chatMessages.length >= 1 && chatMessages[0] && chatMessages[0].content === "root"', 15000, 300, 'fork loaded');
    await sleep(600);
    await cdp.click('#chat-messages .msg:nth-child(1) .msg-action-btn[title="Delete"]');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'msg delete confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(800);
    refs = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [filePath])[0].c;
    const fileGone = !fs.existsSync(path.join(dataDir, filePath));
    // Final state: no rows reference the file and the physical file is removed.
    if (refs !== 0) throw new Error('final refs should be 0, got ' + refs);
    if (!fileGone) throw new Error('orphaned file still on disk after the last reference was deleted');
    return 'shared attachment file survived fork + both thread deletions (refcount held), then was removed when the last referencing message was deleted (refs=' + refs + ', fileGone=' + fileGone + ')';
  }
});
scenarios.push({
  id: 136,
  name: 'Complex branched tree with attachments: branch-edit copy, mid-path retry, fork, deletes and thread trash keep DB + attachment files consistent (audit)',
  mode: 'sse-success',
  regression: true, // audit: complex-tree branching + attachment refcounts + fork/trash lifecycle stay consistent
  settings: {},
  fixtures: {
    threads: [{
      id: 't-cplx-136', title: 'Complex', active_leaf_id: 'm-136-a2',
      cumulative_input_tokens: 360, cumulative_output_tokens: 160, cumulative_cached_tokens: 0
    }],
    messages: [
      { id: 'm-136-u1', thread_id: 't-cplx-136', role: 'user', content: 'root', token_count: 100, active_path_tokens: 100 },
      { id: 'm-136-a1', thread_id: 't-cplx-136', role: 'assistant', content: 'reply A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-136-u1', sibling_group: 'sg-136-a', sibling_index: 0, token_count: 50, prompt_tokens: 100, active_path_tokens: 150 },
      { id: 'm-136-a1b', thread_id: 't-cplx-136', role: 'assistant', content: 'reply B', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-136-u1', sibling_group: 'sg-136-a', sibling_index: 1, token_count: 50, prompt_tokens: 100, active_path_tokens: 150 },
      { id: 'm-136-u2', thread_id: 't-cplx-136', role: 'user', content: 'follow A', parent_id: 'm-136-a1', token_count: 60, active_path_tokens: 210 },
      { id: 'm-136-a2', thread_id: 't-cplx-136', role: 'assistant', content: 'ans A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-136-u2', token_count: 60, prompt_tokens: 160, active_path_tokens: 220 }
    ]
  },
  async body({ cdp, dbPath, dataDir }) {
    const fs = require('node:fs');
    const path = require('node:path');
    const { DatabaseSync } = require('node:sqlite');
    const attDir = path.join(dataDir, 'attachments');
    fs.mkdirSync(attDir, { recursive: true });
    const fileF = 'attachments/f-136.txt';
    const fileF2 = 'attachments/f2-136.txt';
    fs.writeFileSync(path.join(dataDir, fileF), 'root attachment');
    fs.writeFileSync(path.join(dataDir, fileF2), 'follow attachment');
    const db = new DatabaseSync(dbPath, { enableForeignKeyConstraints: false });
    const insAtt = db.prepare("INSERT INTO message_attachments (id, message_id, attachment_type, file_path, mime_type, original_filename, file_size, extracted_text) VALUES (?,?,?,?,?,?,?,?)");
    insAtt.run('a-136-f1', 'm-136-u1', 'text_file', fileF, 'text/plain', 'f.txt', 15, '');
    insAtt.run('a-136-f2', 'm-136-u2', 'text_file', fileF2, 'text/plain', 'f2.txt', 17, '');
    db.close();

    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('chatMessages.length === 4 && chatMessages[3] && chatMessages[3].id === "m-136-a2"', 15000, 300, 'complex thread loaded');
    await sleep(800);

    // 1. Branch switch: a1 -> a1b (off-path sibling). Path becomes u1,a1b.
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Next branch"]');
    await cdp.waitFor('chatMessages.length === 2 && chatMessages[1] && chatMessages[1].id === "m-136-a1b"', 15000, 300, 'branch switched to a1b');
    await sleep(700);
    let ctx = await cdp.text('#tokenBar .tu-item:first-child .tu-val');
    if (String(ctx).indexOf('150') !== 0) throw new Error('branch switch context wrong: ' + JSON.stringify(ctx));
    // Back to a1's leaf (Previous branch).
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Previous branch"]');
    await cdp.waitFor('chatMessages.length === 4 && chatMessages[3] && chatMessages[3].id === "m-136-a2"', 15000, 300, 'branch switched back');
    await sleep(700);

    // 2. Branch-edit the user message u2 (index 3) -> u2b copy (attachments copied) + real request -> a2b.
    await cdp.click('#chat-messages .msg:nth-child(3) .msg-action-btn[title="Edit"]');
    await cdp.waitFor('document.querySelector("#chat-messages .msg:nth-child(3)").classList.contains("editing")', 5000, 200, 'edit ui open');
    await cdp.type('#chat-messages .msg:nth-child(3) .msg-edit-textarea', 'follow A (branch)');
    await cdp.click('#chat-messages .msg:nth-child(3) .save-branch');
    await waitStreamingIdle(cdp, 40000);
    await sleep(1200);
    let rows = seed.query(dbPath, "SELECT id, role, content FROM messages WHERE thread_id='t-cplx-136' AND (content='follow A (branch)' OR content='Hello from the mock LLM. This is the streamed answer.') ORDER BY created_at");
    const u2b = rows.find((r) => r.role === 'user');
    const a2b = rows.find((r) => r.role === 'assistant');
    if (!u2b || !a2b) throw new Error('branch-edit did not create u2b/a2b: ' + JSON.stringify(rows));
    let f2refs = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [fileF2])[0].c;
    if (f2refs !== 2) throw new Error('branch-edit should copy the attachment row (F2 refs 2), got ' + f2refs);
    let thread = seed.query(dbPath, 'SELECT cumulative_input_tokens, cumulative_output_tokens, cumulative_cached_tokens FROM chat_threads WHERE id=?', ['t-cplx-136'])[0];
    if (Number(thread.cumulative_input_tokens) !== 372 || Number(thread.cumulative_output_tokens) !== 169 || Number(thread.cumulative_cached_tokens) !== 4)
      throw new Error('counters after branch-edit wrong: ' + JSON.stringify(thread));
    let usage = seed.query(dbPath, 'SELECT call_count, prompt_tokens, completion_tokens, cached_tokens FROM chat_usage')[0];
    if (!usage || usage.call_count !== 1 || usage.prompt_tokens !== 12) throw new Error('chat_usage after branch-edit wrong: ' + JSON.stringify(usage));

    // 3. Mid-path retry of a1 (now message index 2 on the active path u1,a1,u2b,a2b).
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Retry"]');
    await waitStreamingIdle(cdp, 40000);
    await sleep(1200);
    thread = seed.query(dbPath, 'SELECT cumulative_input_tokens, cumulative_output_tokens, cumulative_cached_tokens, active_leaf_id FROM chat_threads WHERE id=?', ['t-cplx-136'])[0];
    if (Number(thread.cumulative_input_tokens) !== 384 || Number(thread.cumulative_output_tokens) !== 178 || Number(thread.cumulative_cached_tokens) !== 8)
      throw new Error('counters after mid-path retry wrong: ' + JSON.stringify(thread));
    const leaf = seed.query(dbPath, 'SELECT id FROM messages WHERE id=?', [thread.active_leaf_id]);
    if (!leaf.length) throw new Error('active leaf dangling after retry');
    const a1Siblings = seed.query(dbPath, "SELECT sibling_group, sibling_index FROM messages WHERE parent_id='m-136-u1' AND role='assistant' ORDER BY sibling_index");
    if (a1Siblings.length !== 3 || a1Siblings[0].sibling_group !== a1Siblings[1].sibling_group || a1Siblings[1].sibling_group !== a1Siblings[2].sibling_group)
      throw new Error('retried a1 not a sibling of a1/a1b: ' + JSON.stringify(a1Siblings));
    usage = seed.query(dbPath, 'SELECT call_count, prompt_tokens, completion_tokens FROM chat_usage')[0];
    if (usage.call_count !== 2) throw new Error('chat_usage after retry wrong: ' + JSON.stringify(usage));

    // 4. Fork at the retried leaf (a1c). The fork is a faithful copy of the
    // whole tree up to the fork point: the active path (u1,a1c) PLUS the
    // off-path siblings of the retried group (a1, a1b) and their full
    // descendant subtrees (u2,a2,u2b,a2b) = 8 messages, FTS synced, counters
    // recomputed from the fork's own assistant rows (100+100+160+12+12 input /
    // 50+50+60+9+9 output / 8 cached), and attachment rows copied (F x2, F2 x4).
    await cdp.click('#chat-messages .msg:last-child .msg-action-btn[title="Fork"]');
    await cdp.waitFor('window.activeThreadId !== "t-cplx-136"', 15000, 300, 'fork created');
    const forkId = await cdp.eval('window.activeThreadId');
    await sleep(900);
    const forkMsgs = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM messages WHERE thread_id=?', [forkId])[0].c;
    const forkFts = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM messages_fts WHERE msg_id IN (SELECT id FROM messages WHERE thread_id=?)', [forkId])[0].c;
    if (forkMsgs !== 8 || forkFts !== 8) throw new Error('fork msgs/FTS wrong: ' + forkMsgs + '/' + forkFts);
    const forkThread = seed.query(dbPath, 'SELECT cumulative_input_tokens, cumulative_output_tokens FROM chat_threads WHERE id=?', [forkId])[0];
    if (Number(forkThread.cumulative_input_tokens) !== 384 || Number(forkThread.cumulative_output_tokens) !== 178)
      throw new Error('fork counters wrong: ' + JSON.stringify(forkThread));
    let fRefs = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [fileF])[0].c;
    if (fRefs !== 2) throw new Error('fork should copy the F attachment row (refs 2), got ' + fRefs);
    let f2RefsAfterFork = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [fileF2])[0].c;
    if (f2RefsAfterFork !== 4) throw new Error('fork should copy the F2 rows (refs 4), got ' + f2RefsAfterFork);
    if (!fs.existsSync(path.join(dataDir, fileF))) throw new Error('F file missing after fork');

    // 5. Delete the fork forever: F refs drop back to 1, F2 refs back to 2,
    // and both files stay.
    await cdp.eval(`(() => {
      const items = [...document.querySelectorAll('#thread-list .chat-item')];
      const it = items.find((el) => el.getAttribute('data-chat') === '${forkId}');
      if (!it) return false;
      it.querySelector('.chat-action-btn.danger').click();
      return true;
    })()`);
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'trash confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(800);
    await cdp.waitFor('document.querySelectorAll(".trash-item").length >= 1', 10000, 250, 'trash item');
    await cdp.click('.trash-item button.danger');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'delete forever confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(800);
    fRefs = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [fileF])[0].c;
    if (fRefs !== 1) throw new Error('after fork delete F refs should be 1, got ' + fRefs);
    if (!fs.existsSync(path.join(dataDir, fileF))) throw new Error('F file removed while the source thread still references it');
    const f2RefsAfterForkDelete = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [fileF2])[0].c;
    if (f2RefsAfterForkDelete !== 2) throw new Error('after fork delete F2 refs should be 2, got ' + f2RefsAfterForkDelete);
    if (!fs.existsSync(path.join(dataDir, fileF2))) throw new Error('F2 file removed while the source thread still references it');

    // 6. Back on the source thread: delete the branch-edited user copy u2b -
    // F2 refs drop to 1 (u2's row) and the file stays.
    await cdp.eval(`(() => {
      const items = [...document.querySelectorAll('#thread-list .chat-item')];
      const it = items.find((el) => el.getAttribute('data-chat') === 't-cplx-136');
      if (!it) return false;
      it.click();
      return true;
    })()`);
    await cdp.waitFor('chatMessages.length >= 2', 15000, 300, 'source thread reloaded');
    await sleep(800);
    // The source thread's active path ends at the retried leaf (a1c); u2b is
    // off-path inside the a1 subtree. Navigate to it through the tree modal.
    await cdp.click('#treeBtn');
    await cdp.waitFor('typeof window._treeData !== "undefined" && window._treeData.length > 0', 15000, 300, 'tree data');
    await cdp.waitFor('[...document.querySelectorAll(".tree-node")].some((n) => n.textContent.indexOf("follow A (branch)") >= 0)', 15000, 300, 'u2b tree node');
    await cdp.eval('(() => { const n = [...document.querySelectorAll(".tree-node")].find((el) => el.textContent.indexOf("follow A (branch)") >= 0); if (!n) return false; n.click(); return true; })()');
    await cdp.waitFor('chatMessages.length >= 4 && chatMessages.some((m) => m.content === "follow A (branch)") && chatMessages[chatMessages.length - 1].content === "Hello from the mock LLM. This is the streamed answer."', 15000, 300, 'navigated to u2b branch');
    await sleep(800);
    const u2bIdx = await cdp.eval('chatMessages.findIndex((m) => m.content === "follow A (branch)")');
    if (u2bIdx < 0) throw new Error('u2b not in the active view: ' + u2bIdx);
    await cdp.click('#chat-messages .msg:nth-child(' + (u2bIdx + 1) + ') .msg-action-btn[title="Delete"]');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'u2b delete confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(900);
    f2refs = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [fileF2])[0].c;
    if (f2refs !== 1) throw new Error('after deleting u2b F2 refs should be 1 (u2 row), got ' + f2refs);
    if (!fs.existsSync(path.join(dataDir, fileF2))) throw new Error('F2 file removed while u2 still references it');

    // 7. Trash + delete the source thread forever: F2 (last ref gone) is
    // removed from disk; F stays (the fork is gone, so F2 must vanish but F
    // only drops to 0 refs when no other thread holds it - here the fork was
    // deleted, so F is removed too).
    await cdp.eval(`(() => {
      const items = [...document.querySelectorAll('#thread-list .chat-item')];
      const it = items.find((el) => el.getAttribute('data-chat') === 't-cplx-136');
      if (!it) return false;
      it.querySelector('.chat-action-btn.danger').click();
      return true;
    })()`);
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'thread trash confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(800);
    await cdp.waitFor('document.querySelectorAll(".trash-item").length >= 1', 10000, 250, 'trash item 2');
    await cdp.click('.trash-item button.danger');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'thread delete forever confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(900);
    const f2Gone = !fs.existsSync(path.join(dataDir, fileF2));
    const fGone = !fs.existsSync(path.join(dataDir, fileF));
    const f2Rows = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [fileF2])[0].c;
    const fRows = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM message_attachments WHERE file_path = ?', [fileF])[0].c;
    if (f2Rows !== 0 || !f2Gone) throw new Error('F2 orphaned after thread delete: rows=' + f2Rows + ' gone=' + f2Gone);
    if (fRows !== 0 || !fGone) throw new Error('F orphaned after thread delete: rows=' + fRows + ' gone=' + fGone);

    // Final DB integrity sweep on the surviving fork state (nothing left).
    const integrity = seed.query(dbPath, "SELECT (SELECT COUNT(*) FROM messages) AS msgs, (SELECT COUNT(*) FROM messages_fts) AS fts, (SELECT COUNT(*) FROM message_attachments) AS atts");
    return 'complex tree audit: branch-edit copied F2 rows (4->2->1->0), retry sibling group OK, fork (8 msgs, FTS 8, counters 384/178, F refs 2->1->0, F2 refs 4->2->1->0), thread delete removed both files; final rows=' + JSON.stringify(integrity[0]);
  }
});

scenarios.push({
  id: 183,
  name: 'Search result snippets for attachment-text hits show the message content, not the match (SearchRepo._FTS5 builds the preview from m.content only - a term that exists only in an attachment\'s extracted_text yields an unrelated preview)',
  mode: null,
  regression: true, // FIXED: snippets come from the FTS-indexed content (message + attachment text)
  noApp: true,
  settings: {},
  async body() {
    const outFile = path.join(os.tmpdir(), 'llm-bughunt-db-' + process.pid + '.txt');
    try { fs.unlinkSync(outFile); } catch {}
    const probe = path.join(__dirname, '..', 'probe-bughunt-db.ahk');
    const res = spawnSync(launcher.AHK, ['/ErrorStdOut', probe, outFile, 'fts-attachment-snippet'], { timeout: 25000, windowsHide: true, encoding: 'utf8' });
    if (res.error) throw new Error('fts-snippet probe spawn failed/timed out: ' + res.error.message);
    if (res.stderr) process.stderr.write('[probe stderr] ' + res.stderr);
    const text = fs.readFileSync(outFile, 'utf-8');
    const hitsM = text.match(/hits=(\d+)/);
    const matchM = text.match(/previewHasMatch=(\d)/);
    if (!hitsM || !matchM) throw new Error('probe output missing fields: ' + text);
    const hits = Number(hitsM[1]), previewHasMatch = Number(matchM[1]);
    if (hits < 1) throw new Error('control failed - the attachment text is no longer searchable (bug #165 regression): ' + text);
    // FIXED (bug #183): the snippet is built from the FTS-indexed content
    // (message + decoded attachment text), so the preview shows the matched
    // attachment text instead of the unrelated message content.
    if (previewHasMatch !== 1)
      throw new Error('snippet still does not contain the attachment match (fix incomplete): ' + text);
    return 'search for "needle" (only inside the PDF extracted_text) found ' + hits +
      ' hit(s) and the snippet DOES contain "needle" (previewHasMatch=' + previewHasMatch +
      ') - the preview now shows the matched attachment text';
  }
});

scenarios.push({
  id: 184,
  regression: true, // REFUTED lead (2026-08-10): dangling mid-stream rows stay invisible in FTS results + thread map; the chat_usage row is the genuinely billed call (kept by design - no GC warranted)
  name: 'Hard-delete-mid-stream leaves dangling message rows (bug #172 "trace") - verify they never leak into FTS results or the thread map, and the dashboard row is the billed call',
  mode: null,
  noApp: true,
  settings: {},
  async body() {
    const outFile = path.join(os.tmpdir(), 'llm-bughunt-db-' + process.pid + '.txt');
    try { fs.unlinkSync(outFile); } catch {}
    const probe = path.join(__dirname, '..', 'probe-bughunt-db.ahk');
    const res = spawnSync(launcher.AHK, ['/ErrorStdOut', probe, outFile, 'dangling-midstream-rows'], { timeout: 25000, windowsHide: true, encoding: 'utf8' });
    if (res.error) throw new Error('dangling probe spawn failed/timed out: ' + res.error.message);
    if (res.stderr) process.stderr.write('[probe stderr] ' + res.stderr);
    const text = fs.readFileSync(outFile, 'utf-8');
    const rowsM = text.match(/rows=(\d+)/);
    const ftsM = text.match(/ftsRows=(\d+)/);
    const searchM = text.match(/searchHits=(\d+)/);
    const listedM = text.match(/threadMapListed=(\d+)/);
    const usageM = text.match(/usageRows=(\d+)/);
    if (!rowsM || !ftsM || !searchM || !listedM || !usageM) throw new Error('probe output missing fields: ' + text);
    const rows = Number(rowsM[1]), ftsRows = Number(ftsM[1]), searchHits = Number(searchM[1]), listed = Number(listedM[1]), usageRows = Number(usageM[1]);
    if (rows < 1 || ftsRows !== 1) throw new Error('dangling row + FTS entry not produced (flow changed): ' + text);
    if (searchHits !== 0) throw new Error('dangling row LEAKED into FTS search results: ' + text);
    if (listed !== 0) throw new Error('dangling row LEAKED into the thread map: ' + text);
    if (usageRows !== 1) throw new Error('the billed call did not reach chat_usage (regression): ' + text);
    return 'deleted mid-stream: ' + rows + ' dangling message row(s) (with ' + ftsRows + ' FTS entry) stay invisible to search (' + searchHits +
      ' hits) and the thread map (' + listed + ' listed); the chat_usage row (' + usageRows + ') is the genuinely billed API call, so no user-visible leak and no GC policy is warranted';
  }
});

scenarios.push({
  id: 185,
  regression: true, // REFUTED lead (2026-08-10): two real AHK processes racing ChatDB.Open on one WAL DB stayed idempotent (3/3 runs: no lost rows, no duplicated FTS entries, user_version=7)
  name: 'Cross-process startup on one WAL DB: two AHK processes racing _CreateSchema/_Migrate + the FTS DELETE+INSERT rebuild stay idempotent (no lost rows, no duplicated index entries, user_version guarded)',
  mode: null,
  noApp: true,
  settings: {},
  async body() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'llm-db-race-'));
    // Seed a current-schema DB whose FTS index is EMPTY while messages exist -
    // exactly the condition that triggers the app's startup FTS rebuild, so
    // both concurrent processes race the DELETE + INSERT repair path.
    const threads = [{ id: 't-race', title: 'Race', active_leaf_id: 'm-race-1' }];
    const messages = [];
    for (let i = 1; i <= 150; i++) {
      messages.push({ id: 'm-race-' + i, thread_id: 't-race', role: i % 2 ? 'user' : 'assistant', content: 'race message ' + i, model: i % 2 ? undefined : 'deepseek/deepseek-v4-flash', parent_id: i > 1 ? 'm-race-' + (i - 1) : undefined });
    }
    const dbPath = seed.createDb(dir, { threads, messages });
    if (seed.query(dbPath, 'SELECT COUNT(*) AS c FROM messages_fts')[0].c !== 0)
      throw new Error('harness issue: seeded FTS index must be empty to force the rebuild race');
    const probe = path.join(__dirname, '..', 'probe-bughunt-db.ahk');
    const run = (name) => new Promise((resolve) => {
      const out = path.join(dir, name + '.txt');
      const child = spawn(launcher.AHK, ['/ErrorStdOut', probe, out, 'open-race', dbPath], { windowsHide: true, stdio: 'ignore' });
      const timer = setTimeout(() => { try { child.kill(); } catch {} resolve({ ok: false, out, err: 'timeout' }); }, 30000);
      child.on('exit', (code) => { clearTimeout(timer); resolve({ ok: code === 0, out }); });
      child.on('error', (e) => { clearTimeout(timer); resolve({ ok: false, out, err: e.message }); });
    });
    const [a, b] = await Promise.all([run('a'), run('b')]);
    if (!a.ok || !b.ok) {
      let da = '', db = '';
      try { da = fs.readFileSync(a.out, 'utf-8'); } catch {}
      try { db = fs.readFileSync(b.out, 'utf-8'); } catch {}
      throw new Error('concurrent open failed: A=' + JSON.stringify(a) + ' out=' + da + ' B=' + JSON.stringify(b) + ' out=' + db);
    }
    const msgCount = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM messages')[0].c;
    const ftsCount = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM messages_fts')[0].c;
    const dups = seed.query(dbPath, 'SELECT msg_id, COUNT(*) AS c FROM messages_fts GROUP BY msg_id HAVING COUNT(*) > 1');
    const ver = seed.query(dbPath, 'PRAGMA user_version')[0].user_version;
    if (Number(ftsCount) !== Number(msgCount))
      throw new Error('FTS index diverged after the race (BUG present): messages=' + msgCount + ' fts=' + ftsCount);
    if (dups.length > 0)
      throw new Error('FTS index has duplicated entries after the race (BUG present): ' + JSON.stringify(dups));
    if (ver !== 7)
      throw new Error('user_version not guarded at 7: ' + ver);
    return 'two AHK processes raced ChatDB.Open (schema + migrations + FTS rebuild) on one WAL DB: both exited 0, user_version=' + ver +
      ', messages=' + msgCount + ' = messages_fts=' + ftsCount + ', 0 duplicated index entries - the startup path stays idempotent under busy_timeout';
  }
});

scenarios.push({
  id: 188,
  regression: true, // REFUTED lead (2026-08-10): the user_version=7 guard holds - the v6 cost backfill runs exactly once; a reopen after a price change never re-prices legacy rows
  name: 'Legacy schema-v6 migration backfill applies ONCE (user_version guard): reopening after a price change keeps the first-open snapshot prices',
  mode: null,
  noApp: true,
  settings: {},
  async body() {
    const outFile = path.join(os.tmpdir(), 'llm-bughunt-db-' + process.pid + '.txt');
    try { fs.unlinkSync(outFile); } catch {}
    const probe = path.join(__dirname, '..', 'probe-bughunt-db.ahk');
    const res = spawnSync(launcher.AHK, ['/ErrorStdOut', probe, outFile, 'migration-backfill-guard'], { timeout: 25000, windowsHide: true, encoding: 'utf8' });
    if (res.error) throw new Error('migration probe spawn failed/timed out: ' + res.error.message);
    if (res.stderr) process.stderr.write('[probe stderr] ' + res.stderr);
    const text = fs.readFileSync(outFile, 'utf-8');
    const v1M = text.match(/v1=(\d+)/);
    const v2M = text.match(/v2=(\d+)/);
    const c1M = text.match(/cost1=([\d.]+)/);
    const c2M = text.match(/cost2=([\d.]+)/);
    if (!v1M || !v2M || !c1M || !c2M) throw new Error('probe output missing fields: ' + text);
    const v1 = Number(v1M[1]), v2 = Number(v2M[1]), cost1 = Number(c1M[1]), cost2 = Number(c2M[1]);
    if (v1 !== 7 || v2 !== 7) throw new Error('user_version not 7 after migration: ' + text);
    if (cost1 <= 0) throw new Error('backfill did not run on the first open: ' + text);
    if (cost1 !== cost2) throw new Error('reopen re-priced the legacy row (guard FAILED): cost1=' + cost1 + ' cost2=' + cost2);
    return 'v5 DB upgraded to user_version=' + v1 + '; the one-time backfill priced the legacy assistant row at cost1=' + cost1 +
      '; after doubling the model price and reopening, user_version=' + v2 + ' and cost2=' + cost2 +
      ' (unchanged) - the guard prevents double-application (known limitation: pre-upgrade rows are priced at first-open prices, the only data available)';
  }
});
module.exports=scenarios;
