; ======================================================
; SettingsPersistence.ahk — JSON settings persistence
;
; Load/Save settings.json from AppData.
; Provides fallback to DefaultSettings.ahk defaults.
; ======================================================

class SettingsPersistence {
    static settingsPath := ""

    ; Returns the full path to settings.json
    static _Path() {
        if SettingsPersistence.settingsPath
            return SettingsPersistence.settingsPath
        SettingsPersistence.settingsPath := AppInfo.DataDir "\settings.json"
        return SettingsPersistence.settingsPath
    }

    ; Load settings from JSON file. Returns Map on success, empty Map on failure.
    static Load() {
        path := SettingsPersistence._Path()
        if !FileExist(path)
            return Map()
        try {
            raw := FileRead(path, "UTF-8")
            ; Strip an optional UTF-8 BOM before parsing.
            ; (jsongo chokes on the leading \uFEFF and settings were silently
            ; reset to defaults).
            if SubStr(raw, 1, 1) = Chr(0xFEFF)
                raw := SubStr(raw, 2)
            parsed := jsongo.Parse(raw)
            if !IsObject(parsed)
                return Map()
            ; Convert jsongo object to AHK Map recursively
            return SettingsPersistence._ToMap(parsed)
        } catch Error as e {
            debugLog("[SETTINGS] Failed to load settings.json: " e.Message)
            return Map()
        }
    }

    ; Convert jsongo object/array to AHK Map/Array recursively.
    ; jsongo.Parse returns: AHK Maps for JSON objects, AHK Arrays for JSON arrays,
    ; AHK primitives (String, Integer, Float) for scalars, and true/false for booleans.
    static _ToMap(obj) {
        if !IsObject(obj)
            return obj
        ; AHK Map — iterate key-value pairs directly
        if Type(obj) = "Map" {
            result := Map()
            for k, v in obj
                result[k] := SettingsPersistence._ToMap(v)
            return result
        }
        ; AHK Array — iterate items by index
        if Type(obj) = "Array" {
            result := []
            for item in obj
                result.Push(SettingsPersistence._ToMap(item))
            return result
        }
        ; jsongo wrapper objects have OwnProps() method
        if obj.HasMethod("OwnProps") {
            result := Map()
            for k, v in obj.OwnProps()
                result[k] := SettingsPersistence._ToMap(v)
            return result
        }
        return obj
    }

    ; Save settings Map to JSON file. Returns true on success, false on failure.
    static Save(settingsMap) {
        path := SettingsPersistence._Path()
        dirPath := SubStr(path, 1, InStr(path, "\", , -1))
        if !DirExist(dirPath)
            DirCreate(dirPath)
        ; Create user system-messages directory
        userSysMsgDir := AppInfo.DataDir "\system-messages"
        if !DirExist(userSysMsgDir)
            DirCreate(userSysMsgDir)
        ; Write atomically via a temp file in the same directory,
        ; then rename it over the target, preserving the existing settings file
        ; until the replacement is ready.
        tmpPath := path ".tmp"
        try {
            jsonStr := jsongo.Stringify(settingsMap, , 2)
            f := FileOpen(tmpPath, "w", "UTF-8")
            f.Write(jsonStr)
            f.Close()
            ; FileMove's return value is unreliable in this AHK build (it can
            ; be empty even on success), so verify success by file state:
            ; the temp must be gone and the target must exist.
            FileMove(tmpPath, path, 1)
            if FileExist(tmpPath) || !FileExist(path)
                throw Error("FileMove failed: " tmpPath " -> " path)
            debugLog("[SETTINGS] Saved to " path)
            return true
        } catch Error as e {
            debugLog("[SETTINGS] Failed to save settings.json: " e.Message)
            return false
        } finally {
            try FileDelete(tmpPath)
        }
    }

    static _UUID() {
        return Format("{1:08x}-{2:04x}-{3:04x}-{4:04x}-{5:012x}",
            A_TickCount, Random(0, 0xFFFF), Random(0, 0xFFFF),
            Random(0, 0xFFFF), Random(0, 0xFFFFFFFF))
    }
}
