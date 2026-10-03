; Generic external-session metadata. All applications share these tables.
#Include ApplicationWire.ahk
class ApplicationRepo {
    static CreateSchema() {
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS application_sessions (thread_id TEXT PRIMARY KEY REFERENCES chat_threads(id) ON DELETE CASCADE, application_id TEXT NOT NULL, initial_state TEXT NOT NULL, request_id TEXT UNIQUE NOT NULL);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS application_nodes (message_id TEXT PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE, state_json TEXT NOT NULL, replay_json TEXT NOT NULL DEFAULT '[]', kind TEXT NOT NULL DEFAULT 'turn', base_replay_json TEXT NOT NULL DEFAULT '[]');")
        hasReplayBaseColumn := false
        for column in ChatDB.db.Query("PRAGMA table_info(application_nodes);").rows
            if column.name = "base_replay_json"
                hasReplayBaseColumn := true
        if !hasReplayBaseColumn
            ChatDB.db.Exec("ALTER TABLE application_nodes ADD COLUMN base_replay_json TEXT NOT NULL DEFAULT '[]';")
        hasInitialInputColumn := false
        for column in ChatDB.db.Query("PRAGMA table_info(application_sessions);").rows
            if column.name = "initial_input"
                hasInitialInputColumn := true
        if !hasInitialInputColumn
            ChatDB.db.Exec("ALTER TABLE application_sessions ADD COLUMN initial_input TEXT NOT NULL DEFAULT '';")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS application_release_queue (application_id TEXT NOT NULL, state_json TEXT NOT NULL, PRIMARY KEY(application_id,state_json));")
    }

    static Session(threadId) {
        rows := ChatDB.db.Query("SELECT * FROM application_sessions WHERE thread_id=?;", threadId)
        return rows.count ? rows.rows[1] : ""
    }

    static State(threadId, path := "") {
        session := this.Session(threadId)
        if !session
            return ""
        state := jsongo.Parse(session.initial_state)
        if !IsObject(path)
            path := ChatDB.Msg_GetActivePath(threadId)
        for msg in path {
            rows := ChatDB.db.Query("SELECT state_json FROM application_nodes WHERE message_id=?;", msg.id)
            if rows.count
                state := jsongo.Parse(rows[1, "state_json"])
        }
        return state
    }

    static SaveNode(messageId, state, replay := "", kind := "turn") {
        if !IsObject(replay)
            replay := []
        ChatDB.db.Query("INSERT OR REPLACE INTO application_nodes(message_id,state_json,replay_json,kind) VALUES(?,?,?,?);", messageId, jsongo.Stringify(state), jsongo.Stringify(replay), kind)
    }

    static Replay(path, processedMessages := "") {
        items := []
        processed := Map()
        if IsObject(processedMessages)
            for message in processedMessages
                if message.HasOwnProp("_msgId")
                    processed[message._msgId] := message.content
        for msg in path {
            if msg.role = "system"
                continue
            rows := ChatDB.db.Query("SELECT * FROM application_nodes WHERE message_id=?;", msg.id)
            saved := rows.count ? jsongo.Parse(rows[1, "replay_json"]) : []
            if !rows.count && msg.role = "user" && !msg.parent_id {
                session := this.Session(msg.thread_id)
                if session && session.initial_input != "" {
                    saved := [Map("role", "user", "content", ApplicationWire.InputParts(session.initial_input "`n`nUSER MESSAGE:`n" msg.content))]
                    this.SaveNode(msg.id, jsongo.Parse(session.initial_state), saved)
                    rows := ChatDB.db.Query("SELECT * FROM application_nodes WHERE message_id=?;", msg.id)
                }
            }
            if msg.role = "user" && processed.Has(msg.id) {
                base := rows.count ? jsongo.Parse(rows[1, "base_replay_json"]) : []
                if !base.Length
                    base := saved.Length ? saved : [Map("role", "user", "content", ApplicationWire.InputParts(msg.content))]
                native := ChatGptResponsesTransport._MessageInput("user", IsObject(processed[msg.id]) ? jsongo.Parse(ImagePayloadSerializer.Stringify(processed[msg.id])) : processed[msg.id])
                saved := jsongo.Parse(jsongo.Stringify(base))
                extras := 0
                for part in native["content"] {
                    if part.Get("type", "") = "input_text" && part.Get("text", "") = msg.content
                        continue
                    if part.Get("type", "") = "input_text" {
                        for segment in ApplicationWire.InputParts(part["text"])
                            saved[1]["content"].Push(segment)
                    } else {
                        saved[1]["content"].Push(part)
                    }
                    extras++
                }
                if rows.count
                    ChatDB.db.Query("UPDATE application_nodes SET replay_json=?,base_replay_json=? WHERE message_id=?;", jsongo.Stringify(saved), extras ? jsongo.Stringify(base) : "[]", msg.id)
            }
            if saved.Length {
                for item in saved
                    items.Push(item)
            } else {
                items.Push(Map("role", msg.role, "content", [Map("type", msg.role = "assistant" ? "output_text" : "input_text", "text", msg.content)]))
            }
        }
        return items
    }

    static CopyThread(sourceThread, targetThread, idMap) {
        session := this.Session(sourceThread)
        if !session
            return
        ChatDB.db.Query("INSERT INTO application_sessions(thread_id,application_id,initial_state,request_id,initial_input) VALUES(?,?,?,?,?);", targetThread, session.application_id, session.initial_state, ChatDB._UUID(), session.initial_input)
        for oldId, newId in idMap {
            rows := ChatDB.db.Query("SELECT * FROM application_nodes WHERE message_id=?;", oldId)
            if rows.count
                ChatDB.db.Query("INSERT INTO application_nodes(message_id,state_json,replay_json,kind,base_replay_json) VALUES(?,?,?,?,?);", newId, rows[1, "state_json"], rows[1, "replay_json"], rows[1, "kind"], rows[1, "base_replay_json"])
        }
    }

    static CopyEditedNode(sourceId, targetId, content, role) {
        rows := ChatDB.db.Query("SELECT * FROM application_nodes WHERE message_id=?;", sourceId)
        if !rows.count
            return
        base := jsongo.Parse(rows[1, "base_replay_json"])
        items := base.Length ? base : jsongo.Parse(rows[1, "replay_json"])
        state := jsongo.Parse(rows[1, "state_json"])
        if role = "user" {
            if rows[1, "kind"] = "action" {
                owner := ChatDB.db.Query("SELECT thread_id,parent_id FROM messages WHERE id=?;", sourceId)
                state := this.State(owner[1, "thread_id"], ChatDB.Msg_GetPathToLeaf(owner[1, "thread_id"], owner[1, "parent_id"]))
                items := []
                this.SaveNode(targetId, state, items)
                return
            }
            original := items.Length ? items[1] : ""
            if original && original.Has("content") {
                oldText := ApplicationWire.Text(original["content"])
                items := [Map("role", "user", "content", ApplicationWire.InputParts(oldText "`n`nAUTHOR REVISED REQUEST:`n" content))]
            }
        } else {
            ; Preserve reasoning and immutable tool records; replace only the final visible message.
            loop items.Length {
                index := items.Length - A_Index + 1
                item := items[index]
                if item.Get("type", "") = "message" || item.Get("role", "") = "assistant" {
                    item["content"] := [Map("type", "output_text", "text", content)]
                    break
                }
            }
        }
        this.SaveNode(targetId, state, items)
    }

    static QueueRelease(threadId, messageId := "") {
        session := this.Session(threadId)
        if !session
            return
        states := Map()
        if messageId = "" {
            states[session.initial_state] := true
            rows := ChatDB.db.Query("SELECT n.state_json FROM application_nodes n JOIN messages m ON m.id=n.message_id WHERE m.thread_id=?;", threadId)
        } else {
            rows := ChatDB.db.Query("SELECT state_json FROM application_nodes WHERE message_id=?;", messageId)
        }
        for row in rows.rows
            states[row.state_json] := true
        for state, unused in states {
            if messageId = ""
                refs := ChatDB.db.Query("SELECT COUNT(*) AS c FROM application_nodes n JOIN messages m ON m.id=n.message_id JOIN application_sessions s ON s.thread_id=m.thread_id WHERE s.application_id=? AND n.state_json=? AND m.thread_id<>?;", session.application_id, state, threadId)
            else
                refs := ChatDB.db.Query("SELECT COUNT(*) AS c FROM application_nodes n JOIN messages m ON m.id=n.message_id JOIN application_sessions s ON s.thread_id=m.thread_id WHERE s.application_id=? AND n.state_json=? AND n.message_id<>?;", session.application_id, state, messageId)
            initialRefs := ChatDB.db.Query("SELECT COUNT(*) AS c FROM application_sessions WHERE application_id=? AND initial_state=? AND thread_id<>?;", session.application_id, state, messageId = "" ? threadId : "")
            if !Integer(refs[1, "c"]) && !Integer(initialRefs[1, "c"])
                ChatDB.db.Query("INSERT OR IGNORE INTO application_release_queue(application_id,state_json) VALUES(?,?);", session.application_id, state)
        }
    }
}
