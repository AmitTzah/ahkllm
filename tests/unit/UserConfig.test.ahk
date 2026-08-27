; ======================================================
; UserConfig.test.ahk — Tests for new code from UserConfig restructure
;
; Tests: _resolveSystemMessage, _LookupPricing,
;        CostCalculator zero-price edge case,
;        buildCommandMenu submenu ordering
; ======================================================

class UserConfigTest {

    static __New() {
        RegisterTestClass("UserConfigTest")
    }

    ; --------------------------------------------------------
    ; _resolveSystemMessage — inline text
    ; --------------------------------------------------------

    ResolveSystemMessage_InlineText() {
        cmd := { systemMessage: "Hello world" }
        result := _resolveSystemMessage(cmd)
        if result != "Hello world"
            throw Error("Expected 'Hello world', got '" result "'")
    }

    ResolveSystemMessage_NoSystemMessage() {
        cmd := { menuText: "Test" }
        result := _resolveSystemMessage(cmd)
        if result != ""
            throw Error("Expected empty string, got '" result "'")
    }

    ; Regression (bug #72): UNC paths (\\server\share) are absolute and must be
    ; used as-is - a candidate file with the same bare name in
    ; default-settings/system-messages/ must NOT be picked up instead.
    ResolveSystemMessage_UncPathUsedAsIs() {
        candidate := A_ScriptDir "\..\default-settings\system-messages\unc-test-72.txt"
        oldText := ""
        if FileExist(candidate) {
            oldText := FileRead(candidate, "UTF-8")
        } else {
            FileAppend("SHOULD NOT BE READ", candidate, "UTF-8")
        }
        try {
            r := SystemMessageResolver.Resolve({ systemMessageFile: "\\server\share\unc-test-72.txt", systemMessage: "inline fallback" })
            ; With the fix the UNC path is used as-is -> the candidate is not read.
            if r.error = ""
                throw Error("expected an error for a non-existent UNC file (candidate must not be used)")
            if r.text != "inline fallback"
                throw Error("expected the inline fallback, got '" r.text "'")
        } finally {
            if oldText = "" && FileExist(candidate)
                FileDelete(candidate)
            else if oldText != ""
                FileOpen(candidate, "w", "UTF-8-RAW").Write(oldText)
        }
    }

    ResolveSystemMessage_FileTakesPrecedence() {
        ; Write a temp file and test that systemMessageFile overrides systemMessage
        tmpFile := A_Temp "\__test_system_message.txt"
        try FileDelete(tmpFile)
        FileAppend("From file", tmpFile)

        cmd := { systemMessage: "From inline", systemMessageFile: tmpFile }
        result := _resolveSystemMessage(cmd)
        try FileDelete(tmpFile)

        if result != "From file"
            throw Error("Expected 'From file', got '" result "'")
    }

    ResolveSystemMessage_FileNotFound_FallsBackToInline() {
        cmd := { systemMessage: "Fallback", systemMessageFile: A_Temp "\__nonexistent__.txt" }
        result := _resolveSystemMessage(cmd)
        ; Should show MsgBox (mocked in test mode) and fall back to inline
        if result != "Fallback"
            throw Error("Expected 'Fallback' on missing file, got '" result "'")
    }

    ResolveSystemMessage_BareDefaultSettingsFile() {
        ; Bug #50: the settings modal saves bare filenames, so the command path
        ; must resolve them under default-settings/system-messages/ (like the
        ; assistant path) instead of only A_ScriptDir.
        file := A_ScriptDir "\..\default-settings\system-messages\refine.txt"
        if !FileExist(file)
            throw Error("Expected shipped default system message at " file)
        cmd := { systemMessage: "Inline fallback", systemMessageFile: "refine.txt" }
        result := _resolveSystemMessage(cmd)
        if result = "Inline fallback" || result = ""
            throw Error("Bare filename did not resolve under default-settings/system-messages/ (bug #50)")
        expected := StrReplace(StrReplace(FileRead(file, "UTF-8"), "`r`n", "`n"), "`r", "`n")
        if result != expected
            throw Error("Expected file content, got '" SubStr(result, 1, 80) "'")
    }

    ; --------------------------------------------------------
    ; _LookupPricing — TreeRepo helper
    ; --------------------------------------------------------

    LookupPricing_FullKey() {
        ; deepseek/deepseek-v4-flash is in test models map
        pricing := TreeRepo._LookupPricing("deepseek/deepseek-v4-flash")
        if !pricing || !pricing.HasOwnProp("input")
            throw Error("Expected pricing for full key")
        if pricing.input != 0.14
            throw Error("Expected input=0.14, got " pricing.input)
    }

    LookupPricing_ShortName() {
        ; "deepseek-v4-flash" matches via short name fallback
        pricing := TreeRepo._LookupPricing("deepseek-v4-flash")
        if !pricing || !pricing.HasOwnProp("input")
            throw Error("Expected pricing for short name")
        if pricing.input != 0.14
            throw Error("Expected input=0.14, got " pricing.input)
    }

    LookupPricing_Unknown() {
        pricing := TreeRepo._LookupPricing("nonexistent-model")
        if pricing != ""
            throw Error("Expected empty string for unknown model")
    }

    ; --------------------------------------------------------
    ; CostCalculator — zero-price model edge case
    ; --------------------------------------------------------

    CostCalculator_ZeroPriceModel() {
        ; google/gemma-4-31b-it has input:0, output:0 in test models
        ; Verify it doesn't trigger a fallback lookup (would be a bug)
        usage := { promptTokens: 100, completionTokens: 50, totalTokens: 150, cachedTokens: 0 }
        costs := CostCalculator.ComputeTokenCosts("google/gemma-4-31b-it", usage)
        ; Zero-price model: costs should be empty (no cost to calculate)
        if costs.inputCost != "" || costs.outputCost != ""
            throw Error("Zero-price model should have empty costs")
        ; contextWindow should still be returned
        if costs.contextWindow = ""
            throw Error("Zero-price model should still return contextWindow")
    }

    CostCalculator_ShortNameFallback() {
        ; "deepseek-v4-flash" — not a full key in models, should fall back via short name
        usage := { promptTokens: 100, completionTokens: 50, totalTokens: 150, cachedTokens: 0 }
        costs := CostCalculator.ComputeTokenCosts("deepseek-v4-flash", usage)
        if costs.inputCost = "" || costs.inputCost <= 0
            throw Error("Short name fallback should find pricing")
        if costs.totalCost = "" || costs.totalCost <= 0
            throw Error("Short name fallback should calculate total cost")
    }

    ; --------------------------------------------------------
    ; buildCommandMenu — submenu ordering
    ; --------------------------------------------------------

    SubmenuOrder_UsesConfiguredOrder() {
        global submenuOrder
        saved := submenuOrder.Clone()
        global submenuOrder := ["&Z", "&A"]  ; reverse alphabetical

        tagsMap := Map()
        tagOrder := []

        testCommands := [
            { menuText: "A cmd", tags: ["&A"] },
            { menuText: "Z cmd", tags: ["&Z"] }
        ]
        for index, cmd in testCommands {
            for tag in cmd.tags {
                normalizedTag := StrLower(Trim(tag))
                if !tagsMap.Has(normalizedTag) {
                    tagsMap[normalizedTag] := { menu: Menu(), displayName: tag, commands: [] }
                    tagOrder.Push(normalizedTag)
                }
                tagsMap[normalizedTag].commands.Push({menuText: cmd.menuText, index: index})
            }
        }

        orderedTags := []
        seenTags := Map()
        for tag in submenuOrder {
            normalizedTag := StrLower(Trim(tag))
            if tagsMap.Has(normalizedTag) && !seenTags.Has(normalizedTag) {
                orderedTags.Push(normalizedTag)
                seenTags[normalizedTag] := true
            }
        }
        for normalizedTag in tagOrder {
            if !seenTags.Has(normalizedTag) {
                orderedTags.Push(normalizedTag)
                seenTags[normalizedTag] := true
            }
        }

        global submenuOrder := saved

        if orderedTags[1] != "&z"
            throw Error("Expected &z first, got '" orderedTags[1] "'")
        if orderedTags[2] != "&a"
            throw Error("Expected &a second, got '" orderedTags[2] "'")
    }

    SubmenuOrder_WithoutConfig_UsesCommandOrder() {
        global submenuOrder
        saved := submenuOrder.Clone()
        global submenuOrder := []

        tagsMap := Map()
        tagOrder := []

        testCommands := [
            { menuText: "A cmd", tags: ["&A"] },
            { menuText: "Z cmd", tags: ["&Z"] }
        ]
        for index, cmd in testCommands {
            for tag in cmd.tags {
                normalizedTag := StrLower(Trim(tag))
                if !tagsMap.Has(normalizedTag) {
                    tagsMap[normalizedTag] := { menu: Menu(), displayName: tag, commands: [] }
                    tagOrder.Push(normalizedTag)
                }
                tagsMap[normalizedTag].commands.Push({menuText: cmd.menuText, index: index})
            }
        }

        orderedTags := []
        seenTags := Map()
        for normalizedTag in tagOrder {
            if !seenTags.Has(normalizedTag) {
                orderedTags.Push(normalizedTag)
                seenTags[normalizedTag] := true
            }
        }

        global submenuOrder := saved

        if orderedTags[1] != "&a"
            throw Error("Expected &a first (command order), got '" orderedTags[1] "'")
        if orderedTags[2] != "&z"
            throw Error("Expected &z second (command order), got '" orderedTags[2] "'")
    }

    ; Regression (bug #1): the native menu must use the saved per-group order
    ; instead of deriving tagged groups from the flat commands array.
    CommandGroupOrder_UsesSavedOrder() {
        global commands, commandGroupOrders
        oldCommands := commands
        oldOrders := IsSet(commandGroupOrders) ? commandGroupOrders.Clone() : Map()
        try {
            commands := [
                { commandName: "Direct A", directAccelerator: "&a", tags: ["&Work"] },
                { commandName: "Tagged B", tags: ["&Work"] },
                { commandName: "Direct C", directAccelerator: "&c", tags: ["&Work"] }
            ]
            commandGroupOrders := Map("__main__", [3, 1], "&Work", [3, 1, 2])
            workOrder := _CommandIndexesForGroup("&Work")
            mainOrder := _CommandIndexesForGroup("__main__")
            if workOrder.Length != 3 || workOrder[1] != 3 || workOrder[2] != 1 || workOrder[3] != 2
                throw Error("saved tagged order was not used")
            if mainOrder.Length != 2 || mainOrder[1] != 3 || mainOrder[2] != 1
                throw Error("saved main-menu order was not used")
        } finally {
            commands := oldCommands
            commandGroupOrders := oldOrders
        }
    }

    ; --------------------------------------------------------
    ; UTF-8 encoding regression — em dash should survive
    ; --------------------------------------------------------

    ResolveSystemMessage_UTF8_Encoding() {
        tmpFile := A_Temp "\__test_utf8_sysmsg.txt"
        try FileDelete(tmpFile)
        ; Write UTF-8 file with em dash (U+2014)
        FileOpen(tmpFile, "w", "UTF-8").Write("Rule 1`r`nRule 2`r`nRule 3")
        cmd := { systemMessageFile: tmpFile }
        result := _resolveSystemMessage(cmd)
        try FileDelete(tmpFile)
        if !InStr(result, "Rule 1")
            throw Error("UTF-8 file should be readable, got: " SubStr(result, 1, 50))
        if InStr(result, "â")
            throw Error("UTF-8 encoding broken — got garbled chars: " SubStr(result, 1, 50))
    }

    ResolveSystemMessage_UTF8_EmDash() {
        tmpFile := A_Temp "\__test_utf8_emdash.txt"
        try FileDelete(tmpFile)
        FileOpen(tmpFile, "w", "UTF-8").Write("No em dashes`r`nUse commas instead")
        cmd := { systemMessageFile: tmpFile }
        result := _resolveSystemMessage(cmd)
        try FileDelete(tmpFile)
        if InStr(result, "â")
            throw Error("UTF-8 char corrupted to ANSI: " SubStr(result, 1, 80))
    }

    ; --------------------------------------------------------
    ; Google token computation regression
    ; --------------------------------------------------------

    GoogleTokens_TotalIncludesThinking() {
        ; Simulate Google-style usage where total > prompt + completion
        raw := '{"choices":[{"message":{"content":"x"}}],"model":"test","usage":{"prompt_tokens":6,"completion_tokens":2,"total_tokens":121}}'
        var := jsongo.Parse(raw)
        result := ResponseParser.ParseChatResponse(var)
        if result.usage.completionTokens != 115
            throw Error("Google completion should be 121-6=115, got " result.usage.completionTokens)
        if result.usage.totalTokens != 121
            throw Error("Google total should be 121, got " result.usage.totalTokens)
        ; thinking = total - prompt - visible_completion = 121 - 6 - 2 = 113
        if result.usage.thinkingTokens != 113
            throw Error("Google thinking should be 121-6-2=113, got " result.usage.thinkingTokens)
    }

    GoogleTokens_NormalResponse() {
        raw := '{"choices":[{"message":{"content":"x"}}],"model":"test","usage":{"prompt_tokens":23,"completion_tokens":627,"total_tokens":650}}'
        var := jsongo.Parse(raw)
        result := ResponseParser.ParseChatResponse(var)
        if result.usage.completionTokens != 627
            throw Error("Normal completion should be 627, got " result.usage.completionTokens)
        if result.usage.totalTokens != 650
            throw Error("Normal total should be 650, got " result.usage.totalTokens)
    }
}
