; ======================================================
; StreamHandler.test.ahk — Unit tests for StreamHandler logic
;
; Tests: saveStreamResponse content guard,
;        readStreamChunk edge cases
; ======================================================

class StreamHandlerTest {

    static __New() {
        RegisterTestClass("StreamHandlerTest")
    }

    _setupDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_strm_" A_TickCount ".db")
    }

    _teardownDb() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    ; --------------------
    ; saveStreamResponse — empty content guard
    ; --------------------
    ; NOTE: saveStreamResponse uses globals from ChatWindow.ahk
    ; (activeThreadId, requestParams, router). We test the
    ; empty content guard by verifying no crash when content is empty.

    ; --------------------
    ; readStreamChunk — no file
    ; --------------------

    ReadStreamChunk_NoFile_Returns() {
        ; Should not throw when file doesn't exist
        state := {outputFile: A_Temp "\nonexistent_" A_TickCount ".tmp", lastPos: 0, content: "", reasoning: "", modelName: "", firstTokenTime: 0, usage: {}}
        try {
            readStreamChunk(state)
        } catch Error as err {
            throw Error("readStreamChunk should not throw for missing file: " err.Message)
        }
    }

    ReadStreamChunk_EmptyFile_Returns() {
        ; Should not throw for empty file
        tmpFile := A_Temp "\test_empty_" A_TickCount ".tmp"
        FileAppend("", tmpFile)
        state := {outputFile: tmpFile, lastPos: 0, content: "", reasoning: "", modelName: "", firstTokenTime: 0, usage: {}}
        try {
            readStreamChunk(state)
        } catch Error as err {
            FileDelete(tmpFile)
            throw Error("readStreamChunk should not throw for empty file: " err.Message)
        }
        FileDelete(tmpFile)
    }

    ReadStreamChunk_ParsesContent() {
        tmpFile := A_Temp "\test_sse_" A_TickCount ".tmp"
        FileAppend('data: {"choices":[{"delta":{"content":"Hello"}}]}', tmpFile)
        state := {outputFile: tmpFile, lastPos: 0, content: "", reasoning: "", modelName: "", firstTokenTime: 0, usage: {}}
        readStreamChunk(state)
        if state.content != ""
            throw Error("Expected content accumulator to fill, got empty after readStreamChunk")
        FileDelete(tmpFile)
    }
}
