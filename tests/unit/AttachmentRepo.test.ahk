; ======================================================
; AttachmentRepo.test.ahk — Unit tests for attachment CRUD
;
; Tests: Insert, GetByMessage, GetByThread, DeleteOne,
;        CopyForMessage, DeleteByMessage, content-addressable storage
; ======================================================

class AttachmentRepoTest {

    static __New() {
        RegisterTestClass("AttachmentRepoTest")
    }

    _openDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        tempPath := A_Temp "\test_chatdb_" A_TickCount ".db"
        ChatDB.Open(tempPath)
        return ChatDB.db
    }

    _setup() {
        this._openDb()
        return ChatDB.Thread_Create("Test Thread")
    }

    _teardown() {
 ChatDB.Close()
 }

    ; ----------------------------------------------------
    ; Attachment CRUD tests
    ; ----------------------------------------------------

    Attachment_InsertAndGetByMessage() {
        threadId := this._setup()
        msgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "test with attachment"})
        attId := ChatDB.Attachment_Insert(msgId, {
            attachment_type: "image",
            file_path: "attachments\msg_test_screenshot.png",
            mime_type: "image/png",
            original_filename: "screenshot.png",
            file_size: 245000,
            extracted_text: ""
        })
        if !attId
            throw Error("Expected non-empty attachment id")
        atts := ChatDB.Attachment_GetByMessage(msgId)
        if atts.Length != 1
            throw Error("Expected 1 attachment, got " atts.Length)
        if atts[1].attachment_type != "image"
            throw Error("Expected attachment_type 'image', got '" atts[1].attachment_type "'")
        this._teardown()
    }

    Attachment_GetByThread() {
        threadId := this._setup()
        msgId1 := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "msg1"})
        msgId2 := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "msg2", parent_id: msgId1})
        ChatDB.Attachment_Insert(msgId1, {attachment_type: "image", file_path: "attachments\a1.png", mime_type: "image/png", original_filename: "a1.png", file_size: 1000, extracted_text: ""})
        ChatDB.Attachment_Insert(msgId2, {attachment_type: "pdf", file_path: "attachments\a2.pdf", mime_type: "application/pdf", original_filename: "a2.pdf", file_size: 2000, extracted_text: "PDF content"})
        atts := ChatDB.Attachment_GetByThread(threadId)
        if atts.Length != 2
            throw Error("Expected 2 attachments for thread, got " atts.Length)
        this._teardown()
    }

    Attachment_DeleteOne() {
        threadId := this._setup()
        msgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "test"})
        attId := ChatDB.Attachment_Insert(msgId, {
            attachment_type: "text_file",
            file_path: "attachments\msg_test_config.ini",
            mime_type: "text/plain",
            original_filename: "config.ini",
            file_size: 512,
            extracted_text: "[section]\nkey=value"
        })
        ChatDB.Attachment_DeleteOne(attId)
        atts := ChatDB.Attachment_GetByMessage(msgId)
        if atts.Length != 0
            throw Error("Expected 0 attachments after DeleteOne, got " atts.Length)
        this._teardown()
    }

    Attachment_CopyForMessage() {
        threadId := this._setup()
        srcMsgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "source"})
        dstMsgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "destination", parent_id: srcMsgId})
        ChatDB.Attachment_Insert(srcMsgId, {
            attachment_type: "image",
            file_path: "attachments\msg_" srcMsgId "_shot.png",
            mime_type: "image/png",
            original_filename: "shot.png",
            file_size: 1000,
            extracted_text: ""
        })
        ChatDB.Attachment_CopyForMessage(srcMsgId, dstMsgId)
        srcAtts := ChatDB.Attachment_GetByMessage(srcMsgId)
        dstAtts := ChatDB.Attachment_GetByMessage(dstMsgId)
        if srcAtts.Length != 1
            throw Error("Source should still have 1 attachment, got " srcAtts.Length)
        if dstAtts.Length != 1
            throw Error("Destination should have 1 copied attachment, got " dstAtts.Length)
        if dstAtts[1].attachment_type != "image"
            throw Error("Copied attachment should be type 'image', got '" dstAtts[1].attachment_type "'")
        this._teardown()
    }

    Attachment_DeleteByMessage_BeforeHardDelete() {
        threadId := this._setup()
        msgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "will be deleted"})
        ; Insert an attachment
        ChatDB.Attachment_Insert(msgId, {
            attachment_type: "pdf",
            file_path: "attachments\msg_will_delete.pdf",
            mime_type: "application/pdf",
            original_filename: "doc.pdf",
            file_size: 5000,
            extracted_text: "test"
        })
        ; HardDelete should clean up attachments
        ChatDB.Msg_HardDelete(msgId)
        atts := ChatDB.Attachment_GetByMessage(msgId)
        if atts.Length != 0
            throw Error("Expected 0 attachments after HardDelete, got " atts.Length)
        ; Verify message row is also gone
        check := ChatDB.db.Exec("SELECT id FROM messages WHERE id='" msgId "';")
        if check.count > 0
            throw Error("Message row should be hard-deleted")
        this._teardown()
    }

    ; ---- Regression: Bug #7 â€” extracted_text with quotes survives DB roundtrip ----

    Attachment_TextWithQuotes_Roundtrip() {
        dq := Chr(34)
        threadId := this._setup()
        msgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "test"})
        testText := "He said " dq "hello" dq " and she replied " dq "goodbye" dq "."
        ChatDB.Attachment_Insert(msgId, {
            attachment_type: "docx",
            file_path: "attachments\msg_test.docx",
            mime_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            original_filename: "test.docx",
            file_size: 1000,
            extracted_text: testText
        })
        atts := ChatDB.Attachment_GetByMessage(msgId)
        if atts.Length != 1
            throw Error("Expected 1 attachment, got " atts.Length)
        if atts[1].extracted_text != testText
            throw Error("Text with quotes corrupted! Expected '" testText "', got '" atts[1].extracted_text "'")
        this._teardown()
    }

    Attachment_LargeTextWithQuotes_Roundtrip() {
        threadId := this._setup()
        msgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "test"})
        ; Build ~10KB text with many " characters
        parts := []
        dq := Chr(34)
        Loop 100 {
            parts.Push("Line " A_Index ": " dq "quoted text" dq " and more " dq "quotes" dq ".")
        }
        testText := ""
        for part in parts
            testText .= part "`n"
        testText := RTrim(testText, "`n")
        ChatDB.Attachment_Insert(msgId, {
            attachment_type: "docx",
            file_path: "attachments\msg_test_large.docx",
            mime_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            original_filename: "large.docx",
            file_size: 5000,
            extracted_text: testText
        })
        atts := ChatDB.Attachment_GetByMessage(msgId)
        if atts.Length != 1
            throw Error("Expected 1 attachment, got " atts.Length)
        if atts[1].extracted_text != testText
            throw Error("Large text with quotes corrupted!")
        this._teardown()
    }

    ; ---- Regression: Bug #8 â€” text_file content stored and retrieved ----

    Attachment_TextFile_ContentRoundtrip() {
        threadId := this._setup()
        msgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "test"})
        testContent := "# Markdown Test`n`nThis is a **markdown** file with `code`."
        ChatDB.Attachment_Insert(msgId, {
            attachment_type: "text_file",
            file_path: "attachments\msg_test.md",
            mime_type: "text/markdown",
            original_filename: "test.md",
            file_size: 50,
            extracted_text: testContent
        })
        atts := ChatDB.Attachment_GetByMessage(msgId)
        if atts.Length != 1
            throw Error("Expected 1 attachment, got " atts.Length)
        if atts[1].extracted_text != testContent
            throw Error("Text file content corrupted!")
        if atts[1].attachment_type != "text_file"
            throw Error("Expected type 'text_file', got '" atts[1].attachment_type "'")
        this._teardown()
    }

    ; ---- Content-addressable storage: CopyForMessage shares file_path ----

    CopyForMessage_SharesFilePath() {
        threadId := this._setup()
        srcMsgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "source"})
        dstMsgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "dest", parent_id: srcMsgId})
        sharedPath := "attachments\shared_file.png"
        ChatDB.Attachment_Insert(srcMsgId, {
            attachment_type: "image",
            file_path: sharedPath,
            mime_type: "image/png",
            original_filename: "test.png",
            file_size: 1000,
            extracted_text: ""
        })
        ChatDB.Attachment_CopyForMessage(srcMsgId, dstMsgId)
        dstAtts := ChatDB.Attachment_GetByMessage(dstMsgId)
        if dstAtts.Length != 1
            throw Error("Expected 1 copied attachment, got " dstAtts.Length)
        if dstAtts[1].file_path != sharedPath
            throw Error("CopyForMessage should share file_path, got '" dstAtts[1].file_path "' expected '" sharedPath "'")
        this._teardown()
    }

    ; ---- Reference-counted delete: file survives while other rows reference it ----

    DeleteByMessage_KeepsSharedFile() {
        threadId := this._setup()
        msgId1 := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "msg1"})
        msgId2 := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "msg2", parent_id: msgId1})
        sharedPath := "attachments\shared_refcount.png"
        ; Insert same file_path for both messages (simulating shared content)
        ChatDB.Attachment_Insert(msgId1, {
            attachment_type: "image",
            file_path: sharedPath,
            mime_type: "image/png",
            original_filename: "test.png",
            file_size: 1000,
            extracted_text: ""
        })
        ChatDB.Attachment_Insert(msgId2, {
            attachment_type: "image",
            file_path: sharedPath,
            mime_type: "image/png",
            original_filename: "test.png",
            file_size: 1000,
            extracted_text: ""
        })
        ; Delete msg1's attachments â€” file should survive (msg2 still references it)
        ChatDB.Attachment_DeleteByMessage(msgId1)
        atts1 := ChatDB.Attachment_GetByMessage(msgId1)
        if atts1.Length != 0
            throw Error("msg1 attachments should be deleted")
        atts2 := ChatDB.Attachment_GetByMessage(msgId2)
        if atts2.Length != 1
            throw Error("msg2 attachment should survive, got " atts2.Length)
        this._teardown()
    }

    DeleteOne_KeepsSharedFile() {
        threadId := this._setup()
        msgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "test"})
        sharedPath := "attachments\shared_deleteone.png"
        attId1 := ChatDB.Attachment_Insert(msgId, {
            attachment_type: "image",
            file_path: sharedPath,
            mime_type: "image/png",
            original_filename: "test.png",
            file_size: 1000,
            extracted_text: ""
        })
        attId2 := ChatDB.Attachment_Insert(msgId, {
            attachment_type: "image",
            file_path: sharedPath,
            mime_type: "image/png",
            original_filename: "test2.png",
            file_size: 1000,
            extracted_text: ""
        })
        ; Delete one â€” file should survive (other row still references it)
        ChatDB.Attachment_DeleteOne(attId1)
        atts := ChatDB.Attachment_GetByMessage(msgId)
        if atts.Length != 1
            throw Error("Expected 1 remaining attachment, got " atts.Length)
        if atts[1].file_path != sharedPath
            throw Error("File path should be preserved")
        this._teardown()
    }

}
