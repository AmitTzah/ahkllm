"use strict";
// scenarios/db-verify.js — Thorough DB verification via headless experiments + direct state reads.
const fs=require("node:fs");
const path=require("node:path");
const { DatabaseSync } = require("node:sqlite");
const seed=require("../seed");
const launcher=require("../launch");
const { sleep, showChat } = require("./helpers");
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
    for(const t of ["chat_threads","messages","message_attachments","chat_usage","command_usage"]) if(!tables.includes(t)) throw new Error("missing "+t);
    const cols=q("PRAGMA table_info(chat_threads)").map(r=>r.name);
    for(const c of ["cumulative_cost","font_size","folder_id","advanced_toggles"]) if(!cols.includes(c)) throw new Error("missing col "+c);
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
  name: "DB live: Fork copies messages and keeps folder + cumulative counters (bugs #58/#48 fixed)",
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
    await cdp.click('#chat-messages .msg:nth-child(1) .msg-action-btn[title="Fork"]');
    await cdp.waitFor('window.activeThreadId !== "t-fork-106"',15000,300,"forked");
    const nid=await cdp.eval('window.activeThreadId');
    await sleep(600);
    const fork=seed.query(dbPath,"SELECT folder_id, cumulative_cost, font_size FROM chat_threads WHERE id=?",[nid])[0];
    const cnt=seed.query(dbPath,"SELECT COUNT(*) as c FROM messages WHERE thread_id=?",[nid])[0].c;
    // Forked from the user message (the only bubble with a Fork button), so
    // the copy legitimately holds that single message.
    if(cnt!==1) throw new Error("cnt "+cnt);
    // FIXED (bug #58/#48): the fork keeps the source folder and inherits the
    // cumulative counters so the token bar does not reset.
    if(fork.folder_id!=="f106") throw new Error("folder not kept "+JSON.stringify(fork));
    if(Number(fork.cumulative_cost)!==2.0) throw new Error("cumulative not copied "+JSON.stringify(fork));
    return "fork "+nid+" msgs "+cnt+" folder kept cumulative 2.0";
  }
});
scenarios.push({
  id: 117,
  name: "Deleting a message that holds the same attachment file twice orphans the file on disk (ref-count sees 2 rows)",
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
    // BUG: _DeleteFileIfOrphaned counts rows BEFORE the batch delete - with 2
    // rows for the same path the refs stay 2 for both rows, so neither triggers
    // the file delete, and the rows are then all removed -> orphaned file.
    if (rows !== 0 || !msgGone || !fileStillThere)
      throw new Error('orphan state not reproduced: rows=' + rows + ' msgGone=' + msgGone + ' fileStillThere=' + fileStillThere);
    return 'message deleted, 0 attachment rows left, but the physical file still exists at ' + filePath + ' (orphaned by the double-row ref count)';
  }
});
module.exports=scenarios;
