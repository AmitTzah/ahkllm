; ======================================================
; SettingsHandler.test.ahk — Unit tests for SettingsHandler persistence
; ======================================================

class SettingsHandlerTest {

    static __New() {
        RegisterTestClass("SettingsHandlerTest")
    }

    _tempPath() {
        return A_Temp "\test_settings_" A_TickCount ".json"
    }

    Load_MissingFile_ReturnsEmptyMap() {
        oldPath := SettingsHandler.settingsPath
        SettingsHandler.settingsPath := this._tempPath()
        ; Ensure file doesn't exist
        try FileDelete(SettingsHandler.settingsPath)

        result := SettingsHandler.Load()
        if !IsObject(result) || !(result is Map)
            throw Error("Expected Map from Load() with missing file, got: " Type(result))
        if result.Count > 0
            throw Error("Expected empty Map from Load() with missing file, got " result.Count " keys")

        SettingsHandler.settingsPath := oldPath
    }

    ; Regression (bug #79): a UTF-8 BOM before the JSON must not break loading.
    Load_BomPrefix_StillParses() {
        oldPath := SettingsHandler.settingsPath
        SettingsHandler.settingsPath := this._tempPath()
        FileAppend(Chr(0xFEFF) . '{"version":1,"trash":{"retentionDays":30}}', SettingsHandler.settingsPath, "UTF-8-RAW")
        try {
            result := SettingsHandler.Load()
            if !result.Has("trash")
                throw Error("BOM-prefixed settings should parse, got " Type(result))
            if result["trash"]["retentionDays"] != 30
                throw Error("expected retentionDays=30, got " result["trash"]["retentionDays"])
        } finally {
            SettingsHandler.settingsPath := oldPath
            try FileDelete(SettingsHandler.settingsPath)
        }
    }

    ; Regression (bug #97): Save must be atomic - write a temp file in the same
    ; directory, then rename it over settings.json, so a failure mid-write never
    ; leaves the original deleted or half-written.
    Save_IsAtomic() {
        oldPath := SettingsHandler.settingsPath
        target := A_Temp "\test_settings_atomic_" A_TickCount ".json"
        tmp := target ".tmp"
        SettingsHandler.settingsPath := target
        try {
            try FileDelete(target)
            try FileDelete(tmp)
            s := Map("version", 1, "trash", Map("retentionDays", 30))
            if !SettingsHandler.Save(s)
                throw Error("Save() should return true on success")
            if !FileExist(target)
                throw Error("settings.json should exist after Save()")
            if FileExist(tmp)
                throw Error("temp file should be renamed away after a successful Save()")
            loaded := SettingsHandler.Load()
            if !loaded.Has("trash") || loaded["trash"]["retentionDays"] != 30
                throw Error("saved settings should load back with the expected values")
            ; A second save must replace, not append to, the file.
            s2 := Map("version", 2)
            if !SettingsHandler.Save(s2)
                throw Error("second Save() should return true")
            loaded2 := SettingsHandler.Load()
            if loaded2.Has("trash")
                throw Error("second Save() should replace the file content (got leftover 'trash')")
            if !loaded2.Has("version") || loaded2["version"] != 2
                throw Error("second Save() should persist the new content")
        } finally {
            SettingsHandler.settingsPath := oldPath
            try FileDelete(target)
            try FileDelete(tmp)
        }
    }

    ; Regression (bug #97): when the write/move fails, Save returns false,
    ; leaves no temp behind, and does not throw.
    Save_FailureCleansTempAndReturnsFalse() {
        oldPath := SettingsHandler.settingsPath
        ; ':' is invalid in a Windows filename, so the temp write must fail.
        target := A_Temp "\test_settings_bad:name.json"
        SettingsHandler.settingsPath := target
        try {
            result := SettingsHandler.Save(Map("version", 1))
            if result
                throw Error("Save() should return false when the write fails")
            if FileExist(target ".tmp")
                throw Error("failed Save() should clean up its temp file")
        } finally {
            SettingsHandler.settingsPath := oldPath
            try FileDelete(target)
            try FileDelete(target ".tmp")
        }
    }

    GetDefaults_HasAllTopLevelKeys() {
        defaults := SettingsHandler.GetDefaults()
        expectedKeys := ["version", "providers", "models", "assistants", "commands",
                          "submenuOrder", "threadTitles", "ui", "icons",
                          "hotkeys", "apiLogs", "trash", "menuItems"]
        for _, k in expectedKeys {
            if !defaults.Has(k)
                throw Error("GetDefaults() missing key: " k)
        }
    }

    ; Regression (bug #93, hardening): GetDefaults must return an independent
    ; copy - mutating the returned models Map must not corrupt future calls.
    GetDefaults_ReturnsIndependentCopy() {
        first := SettingsHandler.GetDefaults()
        second := SettingsHandler.GetDefaults()
        first["models"]["__test_poison__"] := Map("input", 1)
        third := SettingsHandler.GetDefaults()
        if third["models"].Has("__test_poison__")
            throw Error("mutating a GetDefaults() snapshot corrupted the pristine defaults (bug #93)")
        if second["models"].Has("__test_poison__")
            throw Error("second snapshot shares the mutated map (bug #93)")
    }

    ; Regression (bug #61): clearing a UI field (empty string) must replace the
    ; global instead of being skipped - otherwise the stale value survives
    ; (banner text, input window background, response font).
    ApplyUI_ClearedFieldsResetGlobals() {
        global suspendBannerText, inputWindowBackground, responseWindowFontFace

        oldSbText := suspendBannerText
        oldIwBg := inputWindowBackground
        oldFont := responseWindowFontFace

        try {
            SettingsApply._ApplyUI(Map(
                "ui", Map(
                    "responseFont", "",
                    "responseFontSize", "",
                    "inputWindow", Map("background", ""),
                    "suspendBanner", Map("text", "")
                )
            ))
            if suspendBannerText != ""
                throw Error("clearing suspend banner text should empty the global, got '" suspendBannerText "'")
            if inputWindowBackground != ""
                throw Error("clearing input window background should empty the global, got '" inputWindowBackground "'")
            if responseWindowFontFace != ""
                throw Error("clearing response font should empty the global, got '" responseWindowFontFace "'")
        } finally {
            suspendBannerText := oldSbText
            inputWindowBackground := oldIwBg
            responseWindowFontFace := oldFont
        }
    }

    ; Regression (bug #71, family #61): clearing Thread Title Generation fields
    ; must reset the stale globals.
    ApplyThreadTitles_ClearedFieldsResetGlobals() {
        global titleGenModel, titleGenSystemPrompt, titleGenMaxTokens
        oldModel := titleGenModel
        oldPrompt := titleGenSystemPrompt
        oldMax := titleGenMaxTokens
        try {
            SettingsApply._ApplyThreadTitles(Map(
                "threadTitles", Map("model", "", "prompt", "", "maxTokens", "")
            ))
            if titleGenModel != ""
                throw Error("clearing title-gen model should empty the global, got '" titleGenModel "'")
            if titleGenSystemPrompt != ""
                throw Error("clearing title-gen prompt should empty the global, got '" titleGenSystemPrompt "'")
            if titleGenMaxTokens != ""
                throw Error("clearing title-gen maxTokens should empty the global, got '" titleGenMaxTokens "'")
        } finally {
            titleGenModel := oldModel
            titleGenSystemPrompt := oldPrompt
            titleGenMaxTokens := oldMax
        }
    }

    ; Regression (bug #74): explicitly clearing all provider prefixes must clear
    ; providerMap (the old Count>0 guard kept the stale map).
    ApplyProviders_ClearedPrefixesClearMap() {
        global providers, providerMap
        oldProviders := providers
        oldMap := providerMap
        try {
            SettingsApply._ApplyProviders(Map(
                "providers", Map(
                    "openai", Map("displayName", "OpenAI", "endpoint", "https://x", "prefixes", []),
                    "deepseek", Map("displayName", "DeepSeek", "endpoint", "https://y", "prefixes", [])
                )
            ))
            if providerMap.Count != 0
                throw Error("providerMap should be empty after all prefixes are cleared, got " providerMap.Count " entries")
        } finally {
            providers := oldProviders
            providerMap := oldMap
        }
    }

    ; Regression (bug #90): Override must ignore non-object incoming payloads.
    Override_NonObjectIncoming_Ignored() {
        result := SettingsMerge.Override("", Map("version", 1, "trash", Map("retentionDays", 30)))
        if result.Has("1") || result.Has("2")
            throw Error("non-object incoming must not iterate characters into the result")
        if !result.Has("trash") || result["trash"]["retentionDays"] != 30
            throw Error("base values should survive a non-object incoming")
    }

    ; Regression (bug #101): clearing a command toggle must persist - the copy
    ; helpers must assign false/0/empty values, not skip them.
    ApplyCommands_FalseAndZeroValuesPersist() {
        global commands
        oldCommands := commands
        try {
            cmdSettings := Map(
                "commands", [
                    Map(
                        "commandName", "Test", "menuText", "Test",
                        "stream", false, "isFIM", false, "showInputBox", false,
                        "expandNewlines", false, "includeImageContext", false,
                        "maxContextWords", 0, "tags", []
                    )
                ]
            )
            SettingsHandler.ApplyToGlobals(cmdSettings)
            if commands.Length != 1
                throw Error("expected 1 command, got " commands.Length)
            cmd := commands[1]
            if !cmd.HasOwnProp("stream") || cmd.stream != false
                throw Error("stream=false should persist, got " (cmd.HasOwnProp("stream") ? cmd.stream : "(absent)"))
            if !cmd.HasOwnProp("isFIM") || cmd.isFIM != false
                throw Error("isFIM=false should persist, got " (cmd.HasOwnProp("isFIM") ? cmd.isFIM : "(absent)"))
            if !cmd.HasOwnProp("showInputBox") || cmd.showInputBox != false
                throw Error("showInputBox=false should persist, got " (cmd.HasOwnProp("showInputBox") ? cmd.showInputBox : "(absent)"))
            if !cmd.HasOwnProp("expandNewlines") || cmd.expandNewlines != false
                throw Error("expandNewlines=false should persist, got " (cmd.HasOwnProp("expandNewlines") ? cmd.expandNewlines : "(absent)"))
            if !cmd.HasOwnProp("includeImageContext") || cmd.includeImageContext != false
                throw Error("includeImageContext=false should persist, got " (cmd.HasOwnProp("includeImageContext") ? cmd.includeImageContext : "(absent)"))
            if !cmd.HasOwnProp("maxContextWords") || cmd.maxContextWords != 0
                throw Error("maxContextWords=0 should persist, got " (cmd.HasOwnProp("maxContextWords") ? cmd.maxContextWords : "(absent)"))
            if !cmd.HasOwnProp("tags") || !IsObject(cmd.tags) || cmd.tags.Length != 0
                throw Error("empty tags should persist, got " (cmd.HasOwnProp("tags") ? "non-empty/array" : "(absent)"))
        } finally {
            commands := oldCommands
        }
    }

    ; Regression: "Reset to Defaults" must restore TRUE defaults, not the
    ; values that ApplyToGlobals() wrote into the section globals. GetDefaults()
    ; must return the pristine snapshot captured by CacheInitialDefaults().
    GetDefaults_ReturnsPristineAfterApplyToGlobals() {
        global chatShortcut
        chatShortcut := "1"
        SettingsHandler.CacheInitialDefaults()

        settings := Map()
        settings["chatShortcut"] := "b"
        SettingsHandler.ApplyToGlobals(settings)
        if chatShortcut != "b"
            throw Error("test setup: ApplyToGlobals should set global chatShortcut to 'b'")

        defaults := SettingsHandler.GetDefaults()
        if !defaults.Has("chatShortcut") || defaults["chatShortcut"] != "1"
            throw Error("GetDefaults() should return pristine chatShortcut='1' after ApplyToGlobals set it to 'b', got: "
                (defaults.Has("chatShortcut") ? defaults["chatShortcut"] : "missing"))
    }

    Merge_FillsMissingKeys() {
        existing := Map()
        existing["newChatStartsWith"] := "my-model"
        defaults := Map()
        defaults["newChatStartsWith"] := "default-model"
        defaults["version"] := 1

        merged := SettingsHandler.Merge(existing, defaults)
        if !merged.Has("version") || merged["version"] != 1
            throw Error("Merge should fill missing key 'version'")
        if !merged.Has("newChatStartsWith") || merged["newChatStartsWith"] != "my-model"
            throw Error("Merge should keep existing value for 'newChatStartsWith'")
    }

    Merge_KeepsExistingValues() {
        existing := Map()
        existing["version"] := 99
        defaults := Map()
        defaults["version"] := 1

        merged := SettingsHandler.Merge(existing, defaults)
        if merged["version"] != 99
            throw Error("Merge should keep existing value, got: " merged["version"])
    }

    ; Regression: the saved file is authoritative for WHICH models/providers
    ; exist, so a default entry removed from the file must not come back via
    ; the load merge. Entries that still exist must still fill missing metadata
    ; (api/compat/thinkingLevelMap) from the matching default entry.
    Merge_DoesNotResurrectRemovedDefaultModels() {
        existing := Map()
        existingModels := Map()
        existingModels["openai/gpt-5-mini"] := Map("provider", "openai", "input", 2)
        existing["models"] := existingModels
        existingProviders := Map()
        existingProviders["openai"] := Map("displayName", "OpenAI", "endpoint", "")
        existing["providers"] := existingProviders

        defaults := Map()
        defaultsModels := Map()
        defaultsModels["openai/gpt-5-mini"] := Map(
            "provider", "openai", "input", 2,
            "api", "openai-completions",
            "compat", Map("thinkingFormat", "openai"),
            "thinkingLevelMap", Map("high", true)
        )
        defaultsModels["deepseek/deepseek-chat"] := Map("provider", "deepseek", "input", 1)
        defaults["models"] := defaultsModels
        defaultsProviders := Map()
        defaultsProviders["openai"] := Map("displayName", "OpenAI", "endpoint", "")
        defaultsProviders["deepseek"] := Map("displayName", "DeepSeek", "endpoint", "")
        defaults["providers"] := defaultsProviders

        merged := SettingsHandler.Merge(existing, defaults)
        mergedModels := merged["models"]
        if mergedModels.Has("deepseek/deepseek-chat")
            throw Error("Merge resurrected removed default model deepseek/deepseek-chat")
        if merged["providers"].Has("deepseek")
            throw Error("Merge resurrected removed default provider deepseek")
        if !mergedModels.Has("openai/gpt-5-mini")
            throw Error("Merge should keep a model that is present in the saved file")
        retained := mergedModels["openai/gpt-5-mini"]
        if !retained.Has("api") || retained["api"] != "openai-completions"
            throw Error("Merge should fill api metadata for a retained model from defaults")
        if !retained.Has("thinkingLevelMap") || !retained["thinkingLevelMap"].Has("high")
            throw Error("Merge should fill thinkingLevelMap for a retained model from defaults")
    }

    ; Regression: a save payload is authoritative per top-level key. Removed
    ; models/providers must NOT be resurrected by a deep merge, while top-level
    ; keys the UI did not send keep their saved/default values.
    Override_ReplacesIncomingSectionsWithoutResurrectingRemovedEntries() {
        base := Map()
        baseModels := Map()
        baseModels["deepseek/deepseek-chat"] := Map("provider", "deepseek", "input", 1)
        baseModels["openai/gpt-5-mini"] := Map("provider", "openai", "input", 2)
        base["models"] := baseModels
        base["trash"] := Map("retentionDays", 30)
        base["version"] := 1

        incoming := Map()
        incomingModels := Map()
        incomingModels["openai/gpt-5-mini"] := Map("provider", "openai", "input", 2)
        incoming["models"] := incomingModels
        incoming["newChatStartsWith"] := "deepseek/deepseek-v4-flash"

        result := SettingsHandler.Override(incoming, base)
        if result.Has("models") && result["models"].Has("deepseek/deepseek-chat")
            throw Error("Override resurrected a removed model that was absent from the incoming payload")
        if !result.Has("models") || !result["models"].Has("openai/gpt-5-mini")
            throw Error("Override should keep models present in the incoming payload")
        if !result.Has("trash") || result["trash"]["retentionDays"] != 30
            throw Error("Override should keep base values for top-level keys the UI did not send")
        if !result.Has("version") || result["version"] != 1
            throw Error("Override should keep untouched base keys")
        if !result.Has("newChatStartsWith") || result["newChatStartsWith"] != "deepseek/deepseek-v4-flash"
            throw Error("Override should add new top-level keys from the incoming payload")
    }

    ApplyToGlobals_RebuildsProviderMap() {
        global providerMap

        settings := Map()
        provMap := Map()
        provMap["deepseek"] := Map(
            "displayName", "DeepSeek",
            "endpoint", "https://api.deepseek.com/chat/completions",
            "fimEndpoint", "",
            "authMode", "env",
            "authEnvVar", "DEEPSEEK_API_KEY",
            "apiKey", "",
            "icon", "",
            "collapseThinking", false,
            "prefixes", ["ds"]
        )
        settings["providers"] := provMap

        SettingsHandler.ApplyToGlobals(settings)
        if !providerMap.Has("ds") || providerMap["ds"] != "deepseek"
            throw Error("ApplyToGlobals should rebuild providerMap prefix 'ds' -> 'deepseek'")
    }

    ApplyToGlobals_UpdatesHotkeyGlobals() {
        global mainHotkey, reloadHotkey, closeWindowsHotkey, suspendHotkey

        settings := Map()
        hk := Map(
            "main", "t",
            "reload", "~^!r",
            "closeWindows", "^F4",
            "suspend", "!s"
        )
        settings["hotkeys"] := hk

        oldMain := mainHotkey
        oldReload := reloadHotkey
        oldClose := closeWindowsHotkey
        oldSuspend := suspendHotkey

        SettingsHandler.ApplyToGlobals(settings)

        if mainHotkey != "t"
            throw Error("Expected mainHotkey='t', got: " mainHotkey)
        if reloadHotkey != "~^!r"
            throw Error("Expected reloadHotkey='~^!r', got: " reloadHotkey)
        if closeWindowsHotkey != "^F4"
            throw Error("Expected closeWindowsHotkey='^F4', got: " closeWindowsHotkey)
        if suspendHotkey != "!s"
            throw Error("Expected suspendHotkey='!s', got: " suspendHotkey)

        ; Restore originals so other tests aren't affected
        mainHotkey := oldMain
        reloadHotkey := oldReload
        closeWindowsHotkey := oldClose
        suspendHotkey := oldSuspend
    }

    ; Regression: clearing a hotkey field saves "" and must DISABLE the hotkey,
    ; not silently keep the previous binding. ApplyToGlobals must apply the
    ; empty value instead of skipping it.
    ApplyToGlobals_EmptyHotkeyClearsGlobal() {
        global mainHotkey, reloadHotkey, closeWindowsHotkey, suspendHotkey

        oldMain := mainHotkey
        oldReload := reloadHotkey
        oldClose := closeWindowsHotkey
        oldSuspend := suspendHotkey
        mainHotkey := "t"
        reloadHotkey := "~^!r"
        closeWindowsHotkey := "^F4"
        suspendHotkey := "!s"

        settings := Map()
        hk := Map(
            "main", "",
            "reload", "~^!r",
            "closeWindows", "^F4",
            "suspend", "!s"
        )
        settings["hotkeys"] := hk

        SettingsHandler.ApplyToGlobals(settings)

        if mainHotkey != ""
            throw Error("Expected mainHotkey='' after clearing the field, got: " mainHotkey)
        if reloadHotkey != "~^!r" || closeWindowsHotkey != "^F4" || suspendHotkey != "!s"
            throw Error("Non-cleared hotkeys should keep their saved values")

        ; Restore originals so other tests aren't affected
        mainHotkey := oldMain
        reloadHotkey := oldReload
        closeWindowsHotkey := oldClose
        suspendHotkey := oldSuspend
    }
    ; Regression: clearing an icon field saves "" and must clear the global,
    ; not keep the previous custom/default icon (bug #33).
    ApplyToGlobals_EmptyIconClearsGlobal() {
        global iconOn, iconOff
        oldOn := iconOn
        oldOff := iconOff
        iconOn := "icons\\IconOn.ico"
        iconOff := "icons\\IconOff.ico"
        settings := Map()
        ic := Map("iconOn", "", "iconOff", "")
        settings["icons"] := ic
        SettingsHandler.ApplyToGlobals(settings)
        if iconOn != ""
            throw Error("Expected iconOn='' after clearing, got: " iconOn)
        if iconOff != ""
            throw Error("Expected iconOff='' after clearing, got: " iconOff)
        iconOn := oldOn
        iconOff := oldOff
    }

    ; Regression (bug #120): SettingsService invokes update hooks via fn.Call(),
    ; which throws "Missing a required parameter" for a bare static-method
    ; reference (probe-verified - even .Bind() throws). Main.ahk must register a
    ; plain zero-arg function (TrashRetentionPurge), so lowering Trash Retention
    ; purges expired trash immediately. Assert that a registered zero-arg
    ; function hook is actually invoked by _RunHooks.
    Hooks_InvokePlainFunctionReference() {
        oldHooks := SettingsService._hooks
        SettingsService._hooks := Map()
        ran := 0
        SettingsService.RegisterHook("testZeroArg", () => (ran := ran + 1))
        SettingsService._RunHooks()
        if ran != 1
            throw Error("registered zero-arg hook was not invoked (ran=" ran ")")
        SettingsService._hooks := oldHooks
    }

}
