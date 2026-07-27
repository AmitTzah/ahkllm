; ======================================================
; SettingsHandler.ahk — JSON settings persistence
;
; Load/Save settings.json from AppData.
; Provides fallback to UserConfig.ahk defaults.
; ======================================================

class SettingsHandler {
    static settingsPath := ""

    ; Returns the full path to settings.json
    static _Path() {
        if SettingsHandler.settingsPath
            return SettingsHandler.settingsPath
        SettingsHandler.settingsPath := A_AppData "\LLM-AutoHotkey-Assistant\settings.json"
        return SettingsHandler.settingsPath
    }

    ; Load settings from JSON file. Returns Map on success, empty Map on failure.
    static Load() {
        path := SettingsHandler._Path()
        if !FileExist(path)
            return Map()
        try {
            raw := FileRead(path, "UTF-8")
            parsed := jsongo.Parse(raw)
            if !IsObject(parsed)
                return Map()
            ; Convert jsongo object to AHK Map for consistent access
            result := Map()
            for k, v in parsed.OwnProps()
                result[k] := v
            return result
        } catch Error as e {
            debugLog("[SETTINGS] Failed to load settings.json: " e.Message)
            return Map()
        }
    }

    ; Save settings Map to JSON file.
    ; Returns true on success, false on failure.
    static Save(settingsMap) {
        path := SettingsHandler._Path()
        ; Ensure directory exists
        dirPath := SubStr(path, 1, InStr(path, "\", , -1))
        if !DirExist(dirPath)
            DirCreate(dirPath)
        ; Create user system-messages directory
        userSysMsgDir := A_AppData "\LLM-AutoHotkey-Assistant\system-messages"
        if !DirExist(userSysMsgDir)
            DirCreate(userSysMsgDir)
        try {
            jsonStr := jsongo.Stringify(settingsMap, , 2)
            FileDelete(path)
            FileAppend(jsonStr, path, "UTF-8")
            debugLog("[SETTINGS] Saved to " path)
            return true
        } catch Error as e {
            debugLog("[SETTINGS] Failed to save settings.json: " e.Message)
            return false
        }
    }

    ; Placeholder — will be fully implemented in Step 1
    static GetDefaults() {
        return Map()
    }

    ; Placeholder — will be fully implemented in Step 1
    static Merge(existing, defaults) {
        return existing
    }
}
