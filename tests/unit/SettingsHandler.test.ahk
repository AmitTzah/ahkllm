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
                          "submenuOrder", "threadTitles", "ui", "theme", "icons",
                          "hotkeys", "apiLogs", "trash", "menuItems"]
        for _, k in expectedKeys {
            if !defaults.Has(k)
                throw Error("GetDefaults() missing key: " k)
        }
    }

    Merge_FillsMissingKeys() {
        existing := Map()
        existing["theme"] := Map("darkMode", true)
        defaults := Map()
        defaults["theme"] := Map("darkMode", false)
        defaults["version"] := 1

        merged := SettingsHandler.Merge(existing, defaults)
        if !merged.Has("version") || merged["version"] != 1
            throw Error("Merge should fill missing key 'version'")
        if !merged.Has("theme") || !merged["theme"].Has("darkMode") || merged["theme"]["darkMode"] != true
            throw Error("Merge should keep existing value for 'theme.darkMode'")
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
