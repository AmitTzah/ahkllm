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
}
