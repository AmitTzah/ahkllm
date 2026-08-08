; ======================================================
; AttachmentRepo.ahk - Attachment CRUD operations
;
; Insert, select, delete, copy. File cleanup on disk.
; ======================================================

#Include ..\..\shared\AppInfo.ahk

class AttachmentRepo {

    ; Extract fields from a JS attachment object, save base64 to disk,
    ; and insert a DB row. Returns the attachment ID, or "" on failure.
    ; The att object uses JS camelCase keys: type, filename, base64, mimeType, size, extractedText, contentHash.
    static SaveAttachment(msgId, att) {
        if !IsObject(att)
            return ""
        attType := att.Has("type") ? att["type"] : "text_file"
        attBase64 := att.Has("base64") ? att["base64"] : ""
        if !attBase64
            return ""
        attFilename := att.Has("filename") ? att["filename"] : "unknown"
        attHash := att.Has("contentHash") ? att["contentHash"] : ""
        filePath := ImageUtils.SaveBase64ToFile(attBase64, msgId, attFilename, attHash)
        if !filePath {
            debugLog("[ATTACH] Save failed - file=" attFilename)
            return ""
        }
        return AttachmentRepo.Insert(msgId, {
            attachment_type: attType,
            file_path: filePath,
            mime_type: att.Has("mimeType") ? att["mimeType"] : "",
            original_filename: attFilename,
            file_size: att.Has("size") ? att["size"] : 0,
            extracted_text: att.Has("extractedText") ? att["extractedText"] : ""
        })
    }

    static Insert(msgId, attObj) {
        id := ChatDB._UUID()
        mimeType := attObj.HasProp("mime_type") && attObj.mime_type ? attObj.mime_type : ""
        filename := attObj.HasProp("original_filename") && attObj.original_filename ? attObj.original_filename : ""
        fileSize := attObj.HasProp("file_size") ? attObj.file_size : 0
        ; Base64-encode extracted_text to avoid SQL string escaping issues (e.g. " -> "" corruption)
        if attObj.HasProp("extracted_text") && attObj.extracted_text {
            encodedExtracted := AttachmentRepo._StrToBase64(attObj.extracted_text)
        } else {
            encodedExtracted := ""
        }

        ChatDB.db.Query("INSERT INTO message_attachments (id, message_id, attachment_type, file_path, mime_type, original_filename, file_size, extracted_text) VALUES(?, ?, ?, ?, ?, ?, ?, ?);", id, msgId, attObj.attachment_type, attObj.file_path, mimeType, filename, fileSize, encodedExtracted)
        return id
    }

    static GetByMessage(msgId) {
        table := ChatDB.db.Query("SELECT id, message_id, attachment_type, file_path, mime_type, original_filename, file_size, extracted_text, created_at FROM message_attachments WHERE message_id=? ORDER BY created_at;", msgId)
        result := []
        for row in table.rows {
            result.Push({
                id: row.id,
                message_id: row.message_id,
                attachment_type: row.attachment_type,
                file_path: row.file_path,
                mime_type: row.Has("mime_type") ? row.mime_type : "",
                original_filename: row.Has("original_filename") ? row.original_filename : "",
                file_size: row.Has("file_size") ? Integer(row.file_size) : 0,
                extracted_text: row.Has("extracted_text") && row.extracted_text ? AttachmentRepo._Base64ToStr(row.extracted_text) : "",
                created_at: row.created_at
            })
        }
        return result
    }

    static GetByThread(threadId) {
        table := ChatDB.db.Query("SELECT a.id, a.message_id, a.attachment_type, a.file_path, a.mime_type, a.original_filename, a.file_size, a.extracted_text, a.created_at FROM message_attachments a JOIN messages m ON a.message_id = m.id WHERE m.thread_id=? ORDER BY a.created_at;", threadId)
        result := []
        for row in table.rows {
            result.Push({
                id: row.id,
                message_id: row.message_id,
                attachment_type: row.attachment_type,
                file_path: row.file_path,
                mime_type: row.Has("mime_type") ? row.mime_type : "",
                original_filename: row.Has("original_filename") ? row.original_filename : "",
                file_size: row.Has("file_size") ? Integer(row.file_size) : 0,
                extracted_text: row.Has("extracted_text") && row.extracted_text ? AttachmentRepo._Base64ToStr(row.extracted_text) : "",
                created_at: row.created_at
            })
        }
        return result
    }

    ; Delete all attachments for a message - DB rows + disk files (reference-counted).
    ; MUST be called BEFORE DELETE FROM messages to read file_path before CASCADE.
    static DeleteByMessage(msgId) {
        table := ChatDB.db.Query("SELECT DISTINCT file_path FROM message_attachments WHERE message_id=?;", msgId)
        ChatDB.db.Query("DELETE FROM message_attachments WHERE message_id=?;", msgId)
        ; Bug #117: check the refcount AFTER the batch delete. Checking per-row
        ; before the delete left a file held by 2 rows on the same message (or
        ; by rows about to be deleted) looking referenced, so it was never
        ; removed even though no rows survive.
        for row in table.rows {
            AttachmentRepo._DeleteFileIfOrphaned(row.file_path)
        }
    }

    ; Delete all attachments for a thread - DB rows + disk files (reference-counted).
    ; MUST be called BEFORE raw DELETE FROM messages that triggers CASCADE.
    static DeleteByThread(threadId) {
        table := ChatDB.db.Query("SELECT DISTINCT a.file_path FROM message_attachments a JOIN messages m ON a.message_id = m.id WHERE m.thread_id=?;", threadId)
        ChatDB.db.Query("DELETE FROM message_attachments WHERE message_id IN (SELECT id FROM messages WHERE thread_id=?);", threadId)
        ; Bug #117: refcount check runs AFTER the batch delete (see DeleteByMessage).
        for row in table.rows {
            AttachmentRepo._DeleteFileIfOrphaned(row.file_path)
        }
    }

    ; Delete a single attachment by ID - DB row + disk file (reference-counted).
    static DeleteOne(attachmentId) {
        table := ChatDB.db.Query("SELECT DISTINCT file_path FROM message_attachments WHERE id=?;", attachmentId)
        ChatDB.db.Query("DELETE FROM message_attachments WHERE id=?;", attachmentId)
        ; Bug #117: refcount check runs AFTER the row delete (see DeleteByMessage).
        for row in table.rows {
            AttachmentRepo._DeleteFileIfOrphaned(row.file_path)
        }
    }

    ; Copy all attachments from one message to another.
    ; Shares the same physical file (content-addressable storage) - only copies DB rows.
    static CopyForMessage(sourceMsgId, targetMsgId) {
        table := ChatDB.db.Query("SELECT attachment_type, file_path, mime_type, original_filename, file_size, extracted_text FROM message_attachments WHERE message_id=?;", sourceMsgId)
        for row in table.rows {
            newId := ChatDB._UUID()
            mimeType := row.Has("mime_type") && row.mime_type ? row.mime_type : ""
            filename := row.Has("original_filename") && row.original_filename ? row.original_filename : ""
            extracted := row.Has("extracted_text") && row.extracted_text ? row.extracted_text : ""
            fileSize := row.Has("file_size") ? row.file_size : 0

            ChatDB.db.Query("INSERT INTO message_attachments (id, message_id, attachment_type, file_path, mime_type, original_filename, file_size, extracted_text) VALUES(?, ?, ?, ?, ?, ?, ?, ?);", newId, targetMsgId, row.attachment_type, row.file_path, mimeType, filename, fileSize, extracted)
        }
    }

    ; Delete physical file only if no DB rows reference it (reference counting).
    ; Callers invoke this AFTER the batch row delete (bug #117), so refs counts
    ; SURVIVING rows: delete the file only when refs = 0. (The old pre-delete
    ; pattern used refs <= 1, counting the row about to be deleted.)
    static _DeleteFileIfOrphaned(filePath) {
        count := ChatDB.db.Query("SELECT COUNT(*) AS cnt FROM message_attachments WHERE file_path=?;", filePath)
        refs := count.count ? count[1, "cnt"] : 0
        if refs = 0 {
            fullPath := AppInfo.DataDir "\" filePath
            try FileDelete(fullPath)
        }
    }

    ; Base64-encode a string for safe SQL storage (avoids " -> "" corruption")
    static _StrToBase64(str) {
        size := StrPut(str, "UTF-8") - 1
        buf := Buffer(size)
        StrPut(str, buf, size, "UTF-8")
        ; Get required base64 size
        requiredSize := 0
        DllCall("Crypt32.dll\CryptBinaryToStringA", "Ptr", buf, "UInt", size, "UInt", 0x1, "Ptr", 0, "UIntP", &requiredSize)
        if requiredSize <= 0
            return ""
        b64Buf := Buffer(requiredSize)
        DllCall("Crypt32.dll\CryptBinaryToStringA", "Ptr", buf, "UInt", size, "UInt", 0x1, "Ptr", b64Buf, "UIntP", &requiredSize)
        result := StrGet(b64Buf, requiredSize, "UTF-8")
        result := StrReplace(result, "`r`n", "")
        result := StrReplace(result, "`n", "")
        return result
    }

    ; Decode a base64-encoded string from SQL storage back to original
    static _Base64ToStr(b64) {
        ; Use W variant - AHK strings are UTF-16 (StrPtr gives wide-char pointer)
        requiredSize := 0
        DllCall("Crypt32.dll\CryptStringToBinaryW", "Ptr", StrPtr(b64), "UInt", StrLen(b64),
            "UInt", 0x1, "Ptr", 0, "UIntP", &requiredSize, "Ptr", 0, "Ptr", 0)
        if requiredSize <= 0
            return ""
        buf := Buffer(requiredSize)
        DllCall("Crypt32.dll\CryptStringToBinaryW", "Ptr", StrPtr(b64), "UInt", StrLen(b64),
            "UInt", 0x1, "Ptr", buf, "UIntP", &requiredSize, "Ptr", 0, "Ptr", 0)
        return StrGet(buf, requiredSize, "UTF-8")
    }
}
