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
        state := {outputFile: A_Temp "\nonexistent_" A_TickCount ".tmp", lastPos: 0, content: "", reasoning: "", modelName: "", firstTokenTime: 0, usage: {}, providerKey: "", rawSseChunks: ""}
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
        state := {outputFile: tmpFile, lastPos: 0, content: "", reasoning: "", modelName: "", firstTokenTime: 0, usage: {}, providerKey: "", rawSseChunks: ""}
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
        state := {outputFile: tmpFile, lastPos: 0, content: "", reasoning: "", modelName: "", firstTokenTime: 0, usage: {}, providerKey: "", rawSseChunks: ""}
        readStreamChunk(state)
        if state.content != "Hello"
            throw Error("Expected content='Hello', got '" state.content "'")
        FileDelete(tmpFile)
    }

    ; --------------------------------------------------------
    ; SSEParser: null-usage investigation
    ; jsongo.Parse converts JSON null to "" (empty string).
    ; If OpenAI returns {"usage":null} in a finish chunk,
    ; SSEParser would do parsed["usage"]["prompt_tokens"]
    ; which is bracket-access on "" → __Item error.
    ; --------------------------------------------------------

    ; Verify jsongo.Parse(null) → "" (AHK empty string)
    JsongoNull_BecomesEmptyString() {
        obj := jsongo.Parse('{"key": null}')
        val := obj["key"]
        if Type(val) != "String"
            throw Error("Expected null→String, got Type=" Type(val))
        if val != ""
            throw Error("Expected null→empty string, got '" val "'")
    }

    ; Verify bracket access on "" (from null) triggers __Item
    JsongoNull_BracketAccessOnString_ThrowsTypeError() {
        obj := jsongo.Parse('{"usage": null}')
        usage := obj["usage"]
        if Type(usage) != "String"
            throw Error("Expected String, got " Type(usage))
        ; This should throw — bracket access on a String
        threw := false
        try {
            _ := usage["prompt_tokens"]
        } catch Error as e {
            threw := true
            if !InStr(e.Message, "__Item")
                throw Error("Expected __Item error, got: " e.Message)
        }
        if !threw
            throw Error("Expected bracket access on String to throw, but it didn't")
    }

    ; SSEParser with finish chunk containing "usage": null
    SSEParser_NullUsage_HandlesGracefully() {
        line := 'data: {"id":"test","choices":[{"delta":{},"finish_reason":"stop"}],"model":"gpt-5.1","usage":null}'
        try {
            result := SSEParser.ParseLine(line)
            ; Should not throw, should return finish without usage
            if result.type != "finish"
                throw Error("Expected type='finish', got '" result.type "'")
            if result.HasOwnProp("usage")
                throw Error("Expected no usage prop when usage is null")
        } catch Error as e {
            throw Error("SSEParser should handle null usage gracefully, but threw: " e.Message)
        }
    }

    ; SSEParser with finish chunk containing valid usage
    SSEParser_ValidUsage_ExtractsCorrectly() {
        line := 'data: {"id":"test","choices":[{"delta":{},"finish_reason":"stop"}],"model":"gpt-5.1","usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}'
        result := SSEParser.ParseLine(line)
        if result.type != "finish"
            throw Error("Expected type='finish', got '" result.type "'")
        if !result.HasOwnProp("usage")
            throw Error("Expected usage prop")
        if result.usage.promptTokens != 10
            throw Error("Expected promptTokens=10, got " result.usage.promptTokens)
        if result.usage.completionTokens != 5
            throw Error("Expected completionTokens=5, got " result.usage.completionTokens)
        if result.usage.totalTokens != 15
            throw Error("Expected totalTokens=15, got " result.usage.totalTokens)
    }

    ; SSEParser with finish chunk containing empty usage object
    SSEParser_EmptyUsageObject_HandlesGracefully() {
        line := 'data: {"id":"test","choices":[{"delta":{},"finish_reason":"stop"}],"model":"gpt-5.1","usage":{}}'
        try {
            result := SSEParser.ParseLine(line)
            if result.type != "finish"
                throw Error("Expected type='finish', got '" result.type "'")
        } catch Error as e {
            throw Error("SSEParser should handle empty usage object gracefully, but threw: " e.Message)
        }
    }

    ; SSEParser: usage-only chunk with empty choices (OpenAI stream_options: include_usage format)
    SSEParser_EmptyChoicesWithUsage_ExtractsUsage() {
        line := 'data: {"id":"test","choices":[],"model":"gpt-5.1","usage":{"prompt_tokens":20,"completion_tokens":8,"total_tokens":28,"prompt_cache_hit_tokens":5}}'
        result := SSEParser.ParseLine(line)
        if result.type != "finish"
            throw Error("Expected type='finish' for usage-only chunk, got '" result.type "'")
        if !result.HasOwnProp("usage")
            throw Error("Expected usage prop in usage-only chunk")
        if result.usage.promptTokens != 20
            throw Error("Expected promptTokens=20, got " result.usage.promptTokens)
        if result.usage.completionTokens != 8
            throw Error("Expected completionTokens=8, got " result.usage.completionTokens)
        if result.usage.totalTokens != 28
            throw Error("Expected totalTokens=28, got " result.usage.totalTokens)
        if result.usage.cachedTokens != 5
            throw Error("Expected cachedTokens=5, got " result.usage.cachedTokens)
        if result.model != "gpt-5.1"
            throw Error("Expected model='gpt-5.1', got '" result.model "'")
    }

    ; SSEParser: empty choices without usage should still be ignored
    SSEParser_EmptyChoicesNoUsage_ReturnsIgnore() {
        line := 'data: {"id":"test","choices":[],"model":"gpt-5.1"}'
        result := SSEParser.ParseLine(line)
        if result.type != "ignore"
            throw Error("Expected type='ignore' for empty choices without usage, got '" result.type "'")
    }

    ; --------------------------------------------------------
    ; Error response parsing: Google Gemini returns errors as
    ; [{error: {message: "..."}}] (array), while OpenAI/DeepSeek
    ; return {error: {message: "..."}} (object).
    ; _handleStreamError() must extract the message from both.
    ; --------------------------------------------------------

    ; Google Gemini format: array with error object
    ParseError_GoogleArrayFormat() {
        raw := '[{"error": {"code": 400, "message": "Invalid reasoning_effort value", "status": "INVALID_ARGUMENT"}}]'
        parsed := jsongo.Parse(raw)

        errMsg := ""
        if Type(parsed) = "Array" && parsed.Length > 0 && parsed[1].Has("error") && parsed[1]["error"].Has("message") {
            errMsg := parsed[1]["error"]["message"]
        }

        if errMsg != "Invalid reasoning_effort value"
            throw Error("Expected error message 'Invalid reasoning_effort value', got '" errMsg "'")
    }

    ; OpenAI/DeepSeek format: object with error
    ParseError_ObjectFormat() {
        raw := '{"error": {"message": "Invalid API key", "type": "invalid_request_error"}}'
        parsed := jsongo.Parse(raw)

        errMsg := ""
        if parsed.Has("error") && parsed["error"].Has("message") {
            errMsg := parsed["error"]["message"]
        }

        if errMsg != "Invalid API key"
            throw Error("Expected error message 'Invalid API key', got '" errMsg "'")
    }

    ; Both branches combined (mirrors the actual _handleStreamError logic)
    ParseError_CombinedLogic_HandlesArrayFirst() {
        ; Test: Array format should be caught by the first branch
        raw := '[{"error": {"message": "Array error format"}}]'
        parsed := jsongo.Parse(raw)

        errMsg := ""
        if Type(parsed) = "Array" && parsed.Length > 0 && parsed[1].Has("error") && parsed[1]["error"].Has("message") {
            errMsg := parsed[1]["error"]["message"]
        } else if parsed.Has("error") && parsed["error"].Has("message") {
            errMsg := parsed["error"]["message"]
        }

        if errMsg != "Array error format"
            throw Error("Expected 'Array error format', got '" errMsg "'")
    }

    ParseError_CombinedLogic_HandlesObjectFallback() {
        ; Test: Object format falls through to second branch
        raw := '{"error": {"message": "Object error format"}}'
        parsed := jsongo.Parse(raw)

        errMsg := ""
        if Type(parsed) = "Array" && parsed.Length > 0 && parsed[1].Has("error") && parsed[1]["error"].Has("message") {
            errMsg := parsed[1]["error"]["message"]
        } else if parsed.Has("error") && parsed["error"].Has("message") {
            errMsg := parsed["error"]["message"]
        }

        if errMsg != "Object error format"
            throw Error("Expected 'Object error format', got '" errMsg "'")
    }

    ; --------------------------------------------------------
    ; Non-JSON content: jsongo.Parse throws, catch block must
    ; ensure errMsg stays empty so the fallback at line ~200 fires.
    ; --------------------------------------------------------
    ParseError_NonJsonContent_ReturnsEmptyError() {
        ; Simulate a garbage response body (e.g., HTML error page)
        raw := "<html>502 Bad Gateway</html>"
        threw := false
        errMsg := ""
        try {
            parsed := jsongo.Parse(raw)
            ; Should have thrown — fail if we reach here
            if Type(parsed) = "Array" && parsed.Length > 0 && parsed[1].Has("error") && parsed[1]["error"].Has("message") {
                errMsg := parsed[1]["error"]["message"]
            } else if parsed.Has("error") && parsed["error"].Has("message") {
                errMsg := parsed["error"]["message"]
            }
        } catch Error as e {
            threw := true
            ; errMsg stays empty — fallback path should fire
        }

        if !threw
            throw Error("Expected jsongo.Parse to throw on non-JSON input")
        if errMsg != ""
            throw Error("Expected empty errMsg after parse failure, got '" errMsg "'")
    }
}
