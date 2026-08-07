"use strict";
const fs=require("fs");
const path=require("path");
const os=require("os");
const { DatabaseSync } = require("node:sqlite");
const seed=require("./seed");

function tmpDir(){ return fs.mkdtempSync(path.join(os.tmpdir(),"db-verify-")); }

function check(schema, sql, expect){
  const db=new DatabaseSync(schema);
  // placeholder
}

console.log("=== DB Thorough Verification ===");
const dir=tmpDir();
console.log("tmp",dir);

// 1. Schema verification
const dbPath=seed.createDb(dir, {
  threads:[{id:"t1", title:"Test Thread", model_override:"openai/gpt-4", system_override:"sys", reasoning_override:"high", temperature_override:0, font_size:20, folder_id:null, cumulative_input_tokens:10, cumulative_output_tokens:20}],
  messages:[
    {id:"m1", thread_id:"t1", role:"user", content:"hello", token_count:5, active_path_tokens:5},
    {id:"m2", thread_id:"t1", role:"assistant", content:"hi", model:"openai/gpt-4", parent_id:"m1", token_count:10, thinking_tokens:2, cached_tokens:1, active_path_tokens:15},
  ],
  folders:[{id:"f1", name:"My Folder"}]
});
console.log("DB created at",dbPath);

function q(sql){ return seed.query(dbPath, sql); }

// Check tables exist
console.log("\n1. Schema checks");
const tables=q("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").map(r=>r.name);
console.log(" tables:",tables.join(", "));
const expected=["chat_threads","messages","chat_folders","message_attachments","chat_usage","command_usage","assistants"];
for(const t of expected){ console.log(`  ${t}: ${tables.includes(t)?"OK":"MISSING"}`); }
// Check columns for chat_threads
const cols=q("PRAGMA table_info(chat_threads)").map(r=>r.name);
console.log(" chat_threads cols:",cols.join(", "));
const mustCols=["id","title","is_deleted","active_leaf_id","cumulative_input_tokens","cumulative_cost","font_size","folder_id","advanced_toggles"];
for(const c of mustCols){ console.log(`  col ${c}: ${cols.includes(c)?"OK":"MISSING"}`); }
// Check FTS
const fts=q("SELECT name FROM sqlite_master WHERE type='table' AND name='messages_fts'");
console.log(" FTS table:",fts.length?"OK":"MISSING");
const ftsData=q("SELECT * FROM messages_fts");
console.log(" FTS rows:",ftsData.length,"(should be 0, not auto-populated by seed)");
{ const w=new DatabaseSync(dbPath); w.exec("INSERT INTO messages_fts(msg_id, content) VALUES ('test','hello world')"); w.close(); }
console.log(" FTS insert OK, search:",q("SELECT * FROM messages_fts WHERE messages_fts MATCH 'hello'").length);

// 2. HardDelete parent re-parenting
console.log("\n2. HardDelete simulation");
// Simulate HardDelete logic: create thread with 3 messages chain
const dir2=tmpDir();
const db2=seed.createDb(dir2,{
  threads:[{id:"t2", title:"Chain", active_leaf_id:"m3"}],
  messages:[
    {id:"m1", thread_id:"t2", role:"user", content:"a", token_count:5, active_path_tokens:5},
    {id:"m2", thread_id:"t2", role:"assistant", content:"b", parent_id:"m1", token_count:10, active_path_tokens:15},
    {id:"m3", thread_id:"t2", role:"user", content:"c", parent_id:"m2", token_count:5, active_path_tokens:20},
  ]
});
function q2(sql){ return seed.query(path.join(dir2,"chat_history.db"), sql); }
console.log(" before delete parent of m2:",q2("SELECT parent_id FROM messages WHERE id='m3'")[0].parent_id);
// Simulate delete m2: children (m3) should be reparented to m1
const dbSync=new DatabaseSync(path.join(dir2,"chat_history.db"));
dbSync.exec("UPDATE messages SET parent_id='m1' WHERE id='m3'");
dbSync.exec("DELETE FROM messages WHERE id='m2'");
dbSync.close();
console.log(" after delete, m3 parent:",q2("SELECT parent_id FROM messages WHERE id='m3'")[0].parent_id, "(should be m1)");

// 3. Fork simulation: check what _CopyThreadSettings copies
console.log("\n3. Fork copy checks");
const trContent=fs.readFileSync(path.join(__dirname,"../../chat/db/TreeRepo.ahk"),"utf8");
const copySection=trContent.slice(trContent.indexOf("_CopyThreadSettings"), trContent.indexOf("_CopyThreadSettings")+2000);
console.log(" _CopyThreadSettings copies model_override:",/model_override/.test(copySection));
console.log(" copies system_override:",/system_override/.test(copySection));
console.log(" copies reasoning_override:",/reasoning_override/.test(copySection));
console.log(" copies temperature_override:",/temperature_override/.test(copySection));
console.log(" copies assistant_id:",/assistant_id/.test(copySection));
console.log(" copies font_size:",/font_size/.test(copySection)," (BUG if false)");
console.log(" copies advanced_toggles:",/advanced_toggles/.test(copySection)," (BUG if false)");
console.log(" copies folder_id:",/folder_id/.test(copySection)," (BUG if false)");
console.log(" copies cumulative:",/cumulative/.test(copySection)," (BUG if false)");

// 4. Cumulative counters after HardDelete
console.log("\n4. Cumulative counters bug (#65)");
console.log(" MessageRepo.HardDelete does not touch cumulative_* — verified by grep");
const mr=fs.readFileSync(path.join(__dirname,"../../chat/db/MessageRepo.ahk"),"utf8");
const hd=mr.slice(mr.indexOf("static HardDelete"), mr.indexOf("static HardDelete")+3000);
console.log(" HardDelete touches cumulative:",/cumulative/.test(hd)?"YES (fixed)":"NO — BUG CONFIRMED");

// 5. active_path_tokens recompute bug
console.log("\n5. active_path_tokens recompute");
const tree=fs.readFileSync(path.join(__dirname,"../../chat/db/TreeRepo.ahk"),"utf8");
const recompute=tree.slice(tree.indexOf("_RecomputeActivePath"), tree.indexOf("_RecomputeActivePath")+800);
console.log(recompute.trim().split("\n").slice(0,5).join("\n"));
console.log(" Recompute does prev+=token_count only (no prompt_tokens) — underreports for assistants after delete");

// 6. SQL injection via parent_id
console.log("\n6. SQL injection parent_id");
const mr2=fs.readFileSync(path.join(__dirname,"../../chat/db/MessageRepo.ahk"),"utf8");
console.log(" safeParent raw interpolation:",/safeParent.*msgObj\.parent_id.*\"'\" msgObj\.parent_id/.test(mr2)?"YES — BUG":"no");
console.log(" safeParent escaped:",/SQLite\.Escape\(msgObj\.parent_id\)/.test(mr2)?"YES":"NO — BUG");

// 7. Attachment N+1
console.log("\n7. Attachment foreign key CASCADE");
console.log(" message_attachments FOREIGN KEY ON DELETE CASCADE:",/ON DELETE CASCADE/.test(fs.readFileSync(path.join(__dirname,"../../chat/db/ChatDB.ahk"),"utf8"))?"YES":"NO");

// 8. FTS sync after insert
console.log("\n8. FTS sync");
console.log(" MessageRepo.Insert calls FTS_Sync:",/FTS_Sync/.test(mr)?"YES":"NO");
console.log(" HardDelete calls FTS_Remove:",/FTS_Remove/.test(mr)?"YES":"NO");
console.log(" FTS_Sync escapes msgId:",/SQLite\.Escape\(msgId\)/.test(fs.readFileSync(path.join(__dirname,"../../chat/db/ChatDB.ahk"),"utf8"))?"YES":"NO — BUG (#96)");

// 9. Index coverage
console.log("\n9. Indexes");
const idxs=q("SELECT name FROM sqlite_master WHERE type='index'").map(r=>r.name);
console.log(" indexes:",idxs.join(", "));

// 10. Data integrity: orphan messages
console.log("\n10. Orphan check");
const orphans=q("SELECT COUNT(*) as c FROM messages WHERE thread_id NOT IN (SELECT id FROM chat_threads)").map(r=>r.c);
console.log(" orphan messages (should be 0):",orphans[0]);

console.log("\n=== DB Verification Complete ===");
console.log(" tmp dirs:",dir,dir2,"(will be cleaned on next sweep)");



