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
}
