"use strict";

// Reusable logical/physical audit for isolated scenario databases. SQLite has
// foreign keys for attachments/locks, but the message-tree relationships are
// intentionally application-managed, so this checks both classes explicitly.
const fs = require("node:fs");
const path = require("node:path");
const { DatabaseSync } = require("node:sqlite");

function tableRows(db, sql, params = []) {
  return db.prepare(sql).all(...params);
}

function decodeAttachmentText(value) {
  if (!value) return "";
  try { return Buffer.from(String(value), "base64").toString("utf8"); }
  catch { return ""; }
}

function normalizeRelative(value) {
  return String(value || "").replaceAll("\\", "/").replace(/^\.\//, "").toLowerCase();
}

function physicalFiles(root) {
  const result = new Set();
  if (!root || !fs.existsSync(root)) return result;
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile()) result.add(normalizeRelative(path.relative(path.dirname(root), full)));
    }
  };
  walk(root);
  return result;
}

function auditDatabase(dbPath, dataDir = "") {
  const db = new DatabaseSync(dbPath, { readOnly: true });
  const errors = [];
  try {
    const threads = tableRows(db, "SELECT * FROM chat_threads");
    const messages = tableRows(db, "SELECT * FROM messages");
    const attachments = tableRows(db, "SELECT * FROM message_attachments");
    const threadIds = new Set(threads.map((r) => String(r.id)));
    const messageMap = new Map(messages.map((r) => [String(r.id), r]));
    const children = new Map();
    for (const row of messages) {
      if (!threadIds.has(String(row.thread_id))) errors.push(`orphan message ${row.id} -> ${row.thread_id}`);
      if (row.parent_id != null && row.parent_id !== "" && !messageMap.has(String(row.parent_id)))
        errors.push(`missing parent ${row.parent_id} for ${row.id}`);
      if (row.parent_id && messageMap.has(String(row.parent_id)) && String(messageMap.get(String(row.parent_id)).thread_id) !== String(row.thread_id))
        errors.push(`cross-thread parent ${row.id} -> ${row.parent_id}`);
      if (row.parent_id) {
        const key = String(row.parent_id);
        if (!children.has(key)) children.set(key, []);
        children.get(key).push(row);
      }
    }

    // Check every message, not only active leaves: an off-path cycle can be
    // invisible in the current UI but still break a later branch/fork walk.
    for (const row of messages) {
      const seen = new Set([String(row.id)]);
      let current = row.parent_id == null ? "" : String(row.parent_id);
      while (current) {
        if (seen.has(current)) { errors.push(`parent cycle at ${row.id}/${current}`); break; }
        seen.add(current);
        const parent = messageMap.get(current);
        if (!parent) break;
        current = parent.parent_id == null ? "" : String(parent.parent_id);
      }
    }

    const threadById = new Map(threads.map((r) => [String(r.id), r]));
    for (const thread of threads) {
      const leaf = thread.active_leaf_id == null ? "" : String(thread.active_leaf_id);
      if (!leaf) continue;
      if (!messageMap.has(leaf)) errors.push(`missing active leaf ${thread.id} -> ${leaf}`);
      else if (String(messageMap.get(leaf).thread_id) !== String(thread.id)) errors.push(`cross-thread active leaf ${thread.id} -> ${leaf}`);

      const seen = new Set();
      const pathRows = [];
      let current = leaf;
      while (current) {
        if (seen.has(current)) { errors.push(`parent cycle at ${thread.id}/${current}`); break; }
        seen.add(current);
        const row = messageMap.get(current);
        if (!row) break;
        if (String(row.thread_id) !== String(thread.id)) { errors.push(`active path crosses thread ${thread.id}/${current}`); break; }
        pathRows.unshift(row);
        current = row.parent_id == null ? "" : String(row.parent_id);
      }
      let previous = 0;
      for (const row of pathRows) {
        const tokenCount = Number(row.token_count || 0);
        const thinking = Number(row.thinking_tokens || 0);
        const prompt = Number(row.prompt_tokens || 0);
        const expected = row.role === "assistant" && prompt > 0 ? prompt + tokenCount + thinking : previous + tokenCount + thinking;
        if (Number(row.active_path_tokens || 0) !== expected)
          errors.push(`active_path_tokens ${row.id}: stored=${row.active_path_tokens} expected=${expected}`);
        previous = expected;
      }
    }

    const groups = new Map();
    for (const row of messages) {
      if (!row.sibling_group) continue;
      const key = String(row.sibling_group);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(row);
    }
    for (const [group, rows] of groups) {
      const threadSet = new Set(rows.map((r) => String(r.thread_id)));
      const parentSet = new Set(rows.map((r) => r.parent_id == null ? "" : String(r.parent_id)));
      if (threadSet.size > 1) errors.push(`sibling group ${group} spans threads`);
      if (parentSet.size > 1) errors.push(`sibling group ${group} has different parents`);
      const indexes = new Set();
      for (const row of rows) {
        const index = String(row.sibling_index == null ? "" : row.sibling_index);
        if (indexes.has(index)) errors.push(`duplicate sibling index ${group}/${index}`);
        indexes.add(index);
      }
    }

    const attachmentIds = new Set();
    const referencedFiles = new Set();
    for (const row of attachments) {
      attachmentIds.add(String(row.id));
      if (!messageMap.has(String(row.message_id))) errors.push(`orphan attachment ${row.id} -> ${row.message_id}`);
      const relative = normalizeRelative(row.file_path);
      referencedFiles.add(relative);
      if (dataDir && !fs.existsSync(path.join(dataDir, String(row.file_path).replaceAll("/", path.sep))))
        errors.push(`missing attachment file ${row.id} -> ${row.file_path}`);
    }
    if (dataDir) {
      for (const file of physicalFiles(path.join(dataDir, "attachments"))) {
        if (!referencedFiles.has(file)) errors.push(`unreferenced physical attachment ${file}`);
      }
    }

    const locks = tableRows(db, "SELECT l.thread_id, t.is_locked FROM chat_locks l LEFT JOIN chat_threads t ON t.id=l.thread_id");
    for (const lock of locks) {
      if (!threadIds.has(String(lock.thread_id))) errors.push(`orphan lock ${lock.thread_id}`);
      else if (Number(lock.is_locked || 0) !== 1) errors.push(`lock flag mismatch ${lock.thread_id}`);
    }
    for (const lock of tableRows(db, "SELECT thread_id, kdf, salt, hash, iterations FROM chat_locks")) {
      if (!lock.kdf || !lock.salt || !/^[0-9a-f]{32}$/i.test(String(lock.salt)) || !lock.hash || !/^[0-9a-f]{64}$/i.test(String(lock.hash)) || Number(lock.iterations) < 10000)
        errors.push(`invalid lock metadata ${lock.thread_id}`);
    }
    for (const thread of threads) {
      const lockCount = tableRows(db, "SELECT COUNT(*) AS c FROM chat_locks WHERE thread_id=?", [thread.id])[0].c;
      if (Number(thread.is_locked || 0) === 1 && Number(lockCount) !== 1) errors.push(`locked thread lacks metadata ${thread.id}`);
      if (Number(thread.is_locked || 0) === 0 && Number(lockCount) !== 0) errors.push(`unlocked thread has lock metadata ${thread.id}`);
    }

    const ftsRows = tableRows(db, "SELECT msg_id, content FROM messages_fts");
    const ftsMap = new Map();
    for (const row of ftsRows) {
      const key = String(row.msg_id);
      if (ftsMap.has(key)) errors.push(`duplicate FTS row ${key}`);
      ftsMap.set(key, String(row.content || ""));
    }
    for (const row of messages) {
      let expected = String(row.content || "");
      for (const att of attachments.filter((a) => String(a.message_id) === String(row.id)))
        expected += " " + decodeAttachmentText(att.extracted_text);
      if (!ftsMap.has(String(row.id))) errors.push(`missing FTS row ${row.id}`);
      else if (ftsMap.get(String(row.id)) !== expected) errors.push(`FTS content mismatch ${row.id}`);
    }
    for (const key of ftsMap.keys()) if (!messageMap.has(key)) errors.push(`stale FTS row ${key}`);

    const byThread = new Map();
    for (const row of messages) {
      if (!byThread.has(String(row.thread_id))) byThread.set(String(row.thread_id), []);
      byThread.get(String(row.thread_id)).push(row);
    }
    for (const [threadId, rows] of byThread) {
      const thread = threadById.get(threadId);
      if (!thread) continue;
      const expected = { input: 0, output: 0, cached: 0, inputCost: 0, cachedInputCost: 0, outputCost: 0, cost: 0 };
      const rowMap = new Map(rows.map((r) => [String(r.id), r]));
      for (const row of rows) {
        if (row.role !== "assistant" || !row.model || Number(row.is_local_copy || 0)) continue;
        let prompt = Number(row.prompt_tokens || 0);
        if (!prompt && row.parent_id && rowMap.has(String(row.parent_id))) prompt = Number(rowMap.get(String(row.parent_id)).active_path_tokens || 0);
        expected.input += prompt;
        expected.output += Number(row.token_count || 0) + Number(row.thinking_tokens || 0);
        expected.cached += Number(row.cached_tokens || 0);
        expected.inputCost += Number(row.input_cost || 0);
        expected.cachedInputCost += Number(row.cached_input_cost || 0);
        expected.outputCost += Number(row.output_cost || 0);
        expected.cost += Number(row.total_cost || 0);
      }
      if (Number(thread.cumulative_input_tokens || 0) !== expected.input) errors.push(`cumulative input ${threadId}: stored=${thread.cumulative_input_tokens} expected=${expected.input}`);
      if (Number(thread.cumulative_output_tokens || 0) !== expected.output) errors.push(`cumulative output ${threadId}: stored=${thread.cumulative_output_tokens} expected=${expected.output}`);
      if (Number(thread.cumulative_cached_tokens || 0) !== expected.cached) errors.push(`cumulative cached ${threadId}: stored=${thread.cumulative_cached_tokens} expected=${expected.cached}`);
      if (Math.abs(Number(thread.cumulative_input_cost || 0) - expected.inputCost) > 1e-9) errors.push(`cumulative input cost ${threadId}: stored=${thread.cumulative_input_cost} expected=${expected.inputCost}`);
      if (Math.abs(Number(thread.cumulative_cached_input_cost || 0) - expected.cachedInputCost) > 1e-9) errors.push(`cumulative cached cost ${threadId}: stored=${thread.cumulative_cached_input_cost} expected=${expected.cachedInputCost}`);
      if (Math.abs(Number(thread.cumulative_output_cost || 0) - expected.outputCost) > 1e-9) errors.push(`cumulative output cost ${threadId}: stored=${thread.cumulative_output_cost} expected=${expected.outputCost}`);
      if (Math.abs(Number(thread.cumulative_cost || 0) - expected.cost) > 1e-9) errors.push(`cumulative cost ${threadId}: stored=${thread.cumulative_cost} expected=${expected.cost}`);
    }

    const integrity = tableRows(db, "PRAGMA integrity_check")[0]?.integrity_check;
    const fk = tableRows(db, "PRAGMA foreign_key_check");
    if (integrity !== "ok") errors.push(`PRAGMA integrity_check=${integrity}`);
    if (fk.length) errors.push(`PRAGMA foreign_key_check rows=${fk.length}`);
    return { ok: errors.length === 0, errors, counts: { threads: threads.length, messages: messages.length, attachments: attachments.length, fts: ftsRows.length, locks: locks.length } };
  } finally {
    db.close();
  }
}

function assertInvariants(dbPath, dataDir = "") {
  const result = auditDatabase(dbPath, dataDir);
  if (!result.ok) throw new Error("invariant audit failed: " + result.errors.join("; "));
  return result;
}

module.exports = { auditDatabase, assertInvariants };
