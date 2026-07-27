; ======================================================
; SettingsHandler.ahk — JSON settings persistence
;
; Load/Save settings.json from AppData.
; Provides fallback to UserConfig.ahk defaults.
; Merges loaded settings with defaults for missing keys.
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
            ; Convert jsongo object to AHK Map recursively
            return SettingsHandler._ToMap(parsed)
        } catch Error as e {
            debugLog("[SETTINGS] Failed to load settings.json: " e.Message)
            return Map()
        }
    }

    ; Convert jsongo object/array to AHK Map/Array
    static _ToMap(obj) {
        if obj is jsongo.Integer
            return Integer(obj)
        if obj is jsongo.Float
            return Float(obj)
        if obj is jsongo.String
            return String(obj)
        if obj is jsongo.Boolean
            return obj ? true : false
        if obj is jsongo.Null
            return ""
        if obj is jsongo.Array {
            result := []
            for item in obj
                result.Push(SettingsHandler._ToMap(item))
            return result
        }
        ; Object
        result := Map()
        for k, v in obj.OwnProps()
            result[k] := SettingsHandler._ToMap(v)
        return result
    }

    ; Save settings Map to JSON file. Returns true on success, false on failure.
    static Save(settingsMap) {
        path := SettingsHandler._Path()
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

    ; Build complete defaults Map from current UserConfig.ahk globals.
    ; Called when settings.json is missing or malformed.
    static GetDefaults() {
        d := Map()
        d["version"] := 1

        ; Providers — read from global 'providers' Map. Add prefixes from providerMap.
        provMap := Map()
        for providerKey, p in providers {
            provEntry := Map(
                "displayName", p.displayName,
                "endpoint", p.endpoint,
                "fimEndpoint", p.HasOwnProp("fimEndpoint") ? p.fimEndpoint : "",
                "authMode", "env",
                "authEnvVar", p.authEnvVar,
                "apiKey", "",
                "icon", p.HasOwnProp("icon") ? p.icon : "",
                "collapseThinking", p.HasOwnProp("collapseThinking") ? p.collapseThinking : false,
                "prefixes", []
            )
            provMap[providerKey] := provEntry
        }
        ; Fill prefixes from global providerMap
        if IsSet(providerMap) {
            for prefix, prov in providerMap {
                if provMap.Has(prov) {
                    prefixes := provMap[prov]["prefixes"]
                    if !IsObject(prefixes)
                        prefixes := []
                    found := false
                    for _, p in prefixes {
                        if p = prefix {
                            found := true
                            break
                        }
                    }
                    if !found
                        prefixes.Push(prefix)
                    provMap[prov]["prefixes"] := prefixes
                }
            }
        }
        d["providers"] := provMap

        ; Models — read from global 'models' Map
        modelMap := Map()
        for modelId, m in models {
            modelMap[modelId] := Map(
                "provider", m.HasOwnProp("provider") ? m.provider : "",
                "input", m.HasOwnProp("input") ? m.input : 0,
                "cachedInput", m.HasOwnProp("cachedInput") ? m.cachedInput : "",
                "output", m.HasOwnProp("output") ? m.output : 0,
                "context", m.HasOwnProp("context") ? m.context : 0,
                "reasoning", m.HasOwnProp("reasoning") ? m.reasoning : false,
                "vision", m.HasOwnProp("vision") ? m.vision : false
            )
        }
        d["models"] := modelMap

        ; Assistants — read from global 'assistants' array, generate UUIDs
        asstList := []
        for a in assistants {
            asstList.Push(Map(
                "id", SettingsHandler._UUID(),
                "name", a.name,
                "baseModel", a.baseModel,
                "systemMessage", a.HasOwnProp("systemMessage") ? a.systemMessage : "",
                "systemMessageFile", a.HasOwnProp("systemMessageFile") ? a.systemMessageFile : "",
                "description", a.HasOwnProp("description") ? a.description : "",
                "reasoning", a.HasOwnProp("reasoning") ? a.reasoning : "",
                "temperature", a.HasOwnProp("temperature") ? a.temperature : "",
                "isDefault", a.HasOwnProp("isDefault") ? a.isDefault : false
            ))
        }
        d["assistants"] := asstList

        ; Commands — read from global 'commands' array
        cmdList := []
        for c in commands {
            cmdList.Push(SettingsHandler._CommandToMap(c))
        }
        d["commands"] := cmdList

        ; Submenu order
        if IsSet(submenuOrder) {
            soList := []
            for _, tag in submenuOrder
                soList.Push(tag)
            d["submenuOrder"] := soList
        } else {
            d["submenuOrder"] := []
        }

        ; Thread Titles
        d["threadTitles"] := Map(
            "enabled", IsSet(autoTitleGenerationEnabled) ? autoTitleGenerationEnabled : true,
            "model", IsSet(titleGenModel) ? titleGenModel : "deepseek/deepseek-v4-flash",
            "prompt", IsSet(titleGenSystemPrompt) ? titleGenSystemPrompt : "",
            "maxTokens", IsSet(titleGenMaxTokens) ? titleGenMaxTokens : 50
        )

        ; UI
        d["ui"] := Map(
            "chatDefaultModel", IsSet(chatDefaultModel) ? chatDefaultModel : "deepseek/deepseek-v4-flash",
            "responseFont", IsSet(responseWindowFontFace) ? responseWindowFontFace : "Arial, Segoe UI, Helvetica, Verdana, Tahoma, sans-serif",
            "inputWindow", Map(
                "background", IsSet(inputWindowBackground) ? inputWindowBackground : "0x212529",
                "fontSize", IsSet(inputWindowFontSize) ? inputWindowFontSize : "s14",
                "fontColor", IsSet(inputWindowFontColor) ? inputWindowFontColor : "cWhite",
                "fontFace", IsSet(inputWindowFontFace) ? inputWindowFontFace : "Arial",
                "width", IsSet(inputWindowWidth) ? inputWindowWidth : 500,
                "height", IsSet(inputWindowHeight) ? inputWindowHeight : 250
            ),
            "suspendBanner", Map(
                "text", IsSet(suspendBannerText) ? suspendBannerText : "LLM AutoHotkey Assistant Suspended",
                "fontSize", IsSet(suspendBannerFontSize) ? suspendBannerFontSize : "s10",
                "fontFace", IsSet(suspendBannerFontFace) ? suspendBannerFontFace : "Arial",
                "textColor", IsSet(suspendBannerTextColor) ? suspendBannerTextColor : "cBlack",
                "background", IsSet(suspendBannerBackground) ? suspendBannerBackground : "0xFFDF00"
            )
        )

        ; Theme
        d["theme"] := Map("darkMode", false)

        ; Icons
        d["icons"] := Map(
            "iconOn", IsSet(iconOn) ? iconOn : "icons\IconOn.ico",
            "iconOff", IsSet(iconOff) ? iconOff : "icons\IconOff.ico"
        )

        ; Hotkeys
        d["hotkeys"] := Map(
            "main", IsSet(mainHotkey) ? mainHotkey : "``",
            "saveReload", IsSet(saveReloadHotkey) ? saveReloadHotkey : "~^s",
            "closeWindows", IsSet(closeWindowsHotkey) ? closeWindowsHotkey : "~^w",
            "suspend", IsSet(suspendHotkey) ? suspendHotkey : "CapsLock & ``"
        )

        ; API Logs
        d["apiLogs"] := Map(
            "maxEntries", IsSet(apiLogMaxEntries) ? apiLogMaxEntries : 20
        )

        ; Trash
        d["trash"] := Map(
            "retentionDays", IsSet(trashRetentionDays) ? trashRetentionDays : 30
        )

        ; Menu Items
        qaList := []
        if IsSet(quickAccessMenuItems) {
            for _, item in quickAccessMenuItems {
                qaList.Push(Map(
                    "menuText", item.menuText,
                    "command", item.command
                ))
            }
        }
        trayList := []
        if IsSet(trayMenuItems) {
            for _, item in trayMenuItems {
                trayList.Push(Map(
                    "menuText", item.menuText,
                    "action", item.action
                ))
            }
        }
        d["menuItems"] := Map(
            "quickAccess", qaList,
            "tray", trayList
        )

        return d
    }

    ; Convert a command object to a Map for serialization
    static _CommandToMap(c) {
        m := Map()
        m["commandName"] := c.HasOwnProp("commandName") ? c.commandName : ""
        m["menuText"] := c.HasOwnProp("menuText") ? c.menuText : ""
        m["APIModels"] := c.HasOwnProp("APIModels") ? c.APIModels : ""
        m["pasteMode"] := c.HasOwnProp("pasteMode") ? c.pasteMode : "chat"
        m["stream"] := c.HasOwnProp("stream") ? c.stream : false
        m["isFIM"] := c.HasOwnProp("isFIM") ? c.isFIM : false
        m["showInputBox"] := c.HasOwnProp("showInputBox") ? c.showInputBox : false
        m["userMessage"] := c.HasOwnProp("userMessage") ? c.userMessage : ""
        m["systemMessage"] := c.HasOwnProp("systemMessage") ? c.systemMessage : ""
        m["systemMessageFile"] := c.HasOwnProp("systemMessageFile") ? c.systemMessageFile : ""
        m["inputBoxDefault"] := c.HasOwnProp("inputBoxDefault") ? c.inputBoxDefault : ""
        m["temperature"] := c.HasOwnProp("temperature") ? (c.temperature = "" ? "" : c.temperature) : ""
        m["maxTokens"] := c.HasOwnProp("maxTokens") ? c.maxTokens : ""
        m["stop"] := c.HasOwnProp("stop") ? c.stop : ""
        m["tags"] := c.HasOwnProp("tags") ? c.tags : []
        m["directAccelerator"] := c.HasOwnProp("directAccelerator") ? c.directAccelerator : ""
        m["expandNewlines"] := c.HasOwnProp("expandNewlines") ? c.expandNewlines : false
        m["maxContextWords"] := c.HasOwnProp("maxContextWords") ? c.maxContextWords : 0
        m["includeImageContext"] := c.HasOwnProp("includeImageContext") ? c.includeImageContext : false
        if c.HasOwnProp("thinking") {
            m["thinking"] := c.thinking
        }
        return m
    }

    ; Merge loaded settings with defaults. For each top-level key in defaults,
    ; if loaded has the key, use loaded value; otherwise use default.
    ; For nested Maps, merge recursively.
    static Merge(existing, defaults) {
        result := Map()
        for k, defaultVal in defaults {
            if existing.Has(k) {
                existingVal := existing[k]
                if IsObject(existingVal) && existingVal is Map && IsObject(defaultVal) && defaultVal is Map {
                    result[k] := SettingsHandler.Merge(existingVal, defaultVal)
                } else {
                    result[k] := existingVal
                }
            } else {
                result[k] := defaultVal
            }
        }
        ; Also include any keys in existing that are NOT in defaults
        for k, existingVal in existing {
            if !result.Has(k)
                result[k] := existingVal
        }
        return result
    }

    ; Apply settings Map to global variables.
    ; Called on startup and when settings are updated via IPC.
    static ApplyToGlobals(settings) {
        global providers, models, assistants, commands, submenuOrder
        global autoTitleGenerationEnabled, titleGenModel, titleGenSystemPrompt, titleGenMaxTokens
        global chatDefaultModel, responseWindowFontFace
        global inputWindowBackground, inputWindowFontSize, inputWindowFontColor, inputWindowFontFace, inputWindowWidth, inputWindowHeight
        global suspendBannerText, suspendBannerFontSize, suspendBannerFontFace, suspendBannerTextColor, suspendBannerBackground
        global iconOn, iconOff
        global mainHotkey, saveReloadHotkey, closeWindowsHotkey, suspendHotkey
        global apiLogMaxEntries, trashRetentionDays
        global quickAccessMenuItems, trayMenuItems

        ; Providers
        if settings.Has("providers") {
            newProviders := Map()
            for k, p in settings["providers"] {
                provObj := { 
                    displayName: p.Has("displayName") ? p["displayName"] : k,
                    endpoint: p.Has("endpoint") ? p["endpoint"] : "",
                    fimEndpoint: p.Has("fimEndpoint") ? p["fimEndpoint"] : "",
                    authEnvVar: p.Has("authEnvVar") ? p["authEnvVar"] : "",
                    authMode: p.Has("authMode") ? p["authMode"] : "env",
                    apiKey: p.Has("apiKey") ? p["apiKey"] : "",
                    icon: p.Has("icon") ? p["icon"] : "",
                    collapseThinking: p.Has("collapseThinking") ? p["collapseThinking"] : false
                }
                newProviders[k] := provObj
            }
            providers := newProviders
        }

        ; Models
        if settings.Has("models") {
            newModels := Map()
            for k, m in settings["models"] {
                newModels[k] := {
                    provider: m.Has("provider") ? m["provider"] : "",
                    input: m.Has("input") ? m["input"] : 0,
                    cachedInput: m.Has("cachedInput") ? m["cachedInput"] : "",
                    output: m.Has("output") ? m["output"] : 0,
                    context: m.Has("context") ? m["context"] : 0,
                    reasoning: m.Has("reasoning") ? m["reasoning"] : false,
                    vision: m.Has("vision") ? m["vision"] : false
                }
            }
            models := newModels
        }

        ; Assistants
        if settings.Has("assistants") {
            newAssistants := []
            for _, a in settings["assistants"] {
                newAssistants.Push({
                    id: a.Has("id") ? a["id"] : "",
                    name: a.Has("name") ? a["name"] : "",
                    baseModel: a.Has("baseModel") ? a["baseModel"] : "",
                    systemMessage: a.Has("systemMessage") ? a["systemMessage"] : "",
                    systemMessageFile: a.Has("systemMessageFile") ? a["systemMessageFile"] : "",
                    description: a.Has("description") ? a["description"] : "",
                    reasoning: a.Has("reasoning") ? a["reasoning"] : "",
                    temperature: a.Has("temperature") ? a["temperature"] : "",
                    isDefault: a.Has("isDefault") ? a["isDefault"] : false
                })
            }
            assistants := newAssistants
        }

        ; Commands
        if settings.Has("commands") {
            newCommands := []
            for _, c in settings["commands"] {
                cmd := {}
                if c.Has("commandName") && c["commandName"] != ""
                    cmd.commandName := c["commandName"]
                if c.Has("menuText") && c["menuText"] != ""
                    cmd.menuText := c["menuText"]
                if c.Has("APIModels") && c["APIModels"] != ""
                    cmd.APIModels := c["APIModels"]
                if c.Has("pasteMode") && c["pasteMode"] != ""
                    cmd.pasteMode := c["pasteMode"]
                if c.Has("stream") && c["stream"]
                    cmd.stream := c["stream"]
                if c.Has("isFIM") && c["isFIM"]
                    cmd.isFIM := c["isFIM"]
                if c.Has("showInputBox") && c["showInputBox"]
                    cmd.showInputBox := c["showInputBox"]
                if c.Has("userMessage") && c["userMessage"] != ""
                    cmd.userMessage := c["userMessage"]
                if c.Has("systemMessage") && c["systemMessage"] != ""
                    cmd.systemMessage := c["systemMessage"]
                if c.Has("systemMessageFile") && c["systemMessageFile"] != ""
                    cmd.systemMessageFile := c["systemMessageFile"]
                if c.Has("inputBoxDefault") && c["inputBoxDefault"] != ""
                    cmd.inputBoxDefault := c["inputBoxDefault"]
                if c.Has("temperature") && c["temperature"] != ""
                    cmd.temperature := c["temperature"]
                if c.Has("maxTokens") && c["maxTokens"] != ""
                    cmd.maxTokens := c["maxTokens"]
                if c.Has("stop") && c["stop"] != ""
                    cmd.stop := c["stop"]
                if c.Has("tags") && IsObject(c["tags"]) && c["tags"].Length > 0
                    cmd.tags := c["tags"]
                if c.Has("directAccelerator") && c["directAccelerator"] != ""
                    cmd.directAccelerator := c["directAccelerator"]
                if c.Has("expandNewlines") && c["expandNewlines"]
                    cmd.expandNewlines := c["expandNewlines"]
                if c.Has("maxContextWords") && c["maxContextWords"] != 0
                    cmd.maxContextWords := c["maxContextWords"]
                if c.Has("includeImageContext") && c["includeImageContext"]
                    cmd.includeImageContext := c["includeImageContext"]
                if c.Has("thinking")
                    cmd.thinking := c["thinking"]
                newCommands.Push(cmd)
            }
            commands := newCommands
        }

        ; Submenu order
        if settings.Has("submenuOrder") {
            newSO := []
            for _, tag in settings["submenuOrder"]
                newSO.Push(tag)
            submenuOrder := newSO
        }

        ; Thread titles
        if settings.Has("threadTitles") {
            tt := settings["threadTitles"]
            autoTitleGenerationEnabled := tt.Has("enabled") ? tt["enabled"] : true
            if tt.Has("model") && tt["model"] != ""
                titleGenModel := tt["model"]
            if tt.Has("prompt") && tt["prompt"] != ""
                titleGenSystemPrompt := tt["prompt"]
            if tt.Has("maxTokens") && tt["maxTokens"] != ""
                titleGenMaxTokens := tt["maxTokens"]
        }

        ; UI
        if settings.Has("ui") {
            u := settings["ui"]
            if u.Has("chatDefaultModel") && u["chatDefaultModel"] != ""
                chatDefaultModel := u["chatDefaultModel"]
            if u.Has("responseFont") && u["responseFont"] != ""
                responseWindowFontFace := u["responseFont"]
            if u.Has("inputWindow") {
                iw := u["inputWindow"]
                if iw.Has("background") && iw["background"] != ""
                    inputWindowBackground := iw["background"]
                if iw.Has("fontSize") && iw["fontSize"] != ""
                    inputWindowFontSize := iw["fontSize"]
                if iw.Has("fontColor") && iw["fontColor"] != ""
                    inputWindowFontColor := iw["fontColor"]
                if iw.Has("fontFace") && iw["fontFace"] != ""
                    inputWindowFontFace := iw["fontFace"]
                if iw.Has("width") && iw["width"] != ""
                    inputWindowWidth := iw["width"]
                if iw.Has("height") && iw["height"] != ""
                    inputWindowHeight := iw["height"]
            }
            if u.Has("suspendBanner") {
                sb := u["suspendBanner"]
                if sb.Has("text") && sb["text"] != ""
                    suspendBannerText := sb["text"]
                if sb.Has("fontSize") && sb["fontSize"] != ""
                    suspendBannerFontSize := sb["fontSize"]
                if sb.Has("fontFace") && sb["fontFace"] != ""
                    suspendBannerFontFace := sb["fontFace"]
                if sb.Has("textColor") && sb["textColor"] != ""
                    suspendBannerTextColor := sb["textColor"]
                if sb.Has("background") && sb["background"] != ""
                    suspendBannerBackground := sb["background"]
            }
        }

        ; Icons
        if settings.Has("icons") {
            ic := settings["icons"]
            if ic.Has("iconOn") && ic["iconOn"] != ""
                iconOn := ic["iconOn"]
            if ic.Has("iconOff") && ic["iconOff"] != ""
                iconOff := ic["iconOff"]
        }

        ; Hotkeys
        if settings.Has("hotkeys") {
            hk := settings["hotkeys"]
            if hk.Has("main") && hk["main"] != ""
                mainHotkey := hk["main"]
            if hk.Has("saveReload") && hk["saveReload"] != ""
                saveReloadHotkey := hk["saveReload"]
            if hk.Has("closeWindows") && hk["closeWindows"] != ""
                closeWindowsHotkey := hk["closeWindows"]
            if hk.Has("suspend") && hk["suspend"] != ""
                suspendHotkey := hk["suspend"]
        }

        ; API Logs
        if settings.Has("apiLogs") {
            al := settings["apiLogs"]
            if al.Has("maxEntries")
                apiLogMaxEntries := al["maxEntries"]
        }

        ; Trash
        if settings.Has("trash") {
            tr := settings["trash"]
            if tr.Has("retentionDays")
                trashRetentionDays := tr["retentionDays"]
        }

        ; Menu items
        if settings.Has("menuItems") {
            mi := settings["menuItems"]
            if mi.Has("quickAccess") {
                newQA := []
                for _, item in mi["quickAccess"] {
                    newQA.Push({ menuText: item.Has("menuText") ? item["menuText"] : "", command: item.Has("command") ? item["command"] : "" })
                }
                quickAccessMenuItems := newQA
            }
            if mi.Has("tray") {
                newTray := []
                for _, item in mi["tray"] {
                    newTray.Push({ menuText: item.Has("menuText") ? item["menuText"] : "", action: item.Has("action") ? item["action"] : "" })
                }
                trayMenuItems := newTray
            }
        }
    }

    static _UUID() {
        return Format("{1:08x}-{2:04x}-{3:04x}-{4:04x}-{5:012x}",
            A_TickCount, Random(0, 0xFFFF), Random(0, 0xFFFF),
            Random(0, 0xFFFF), Random(0, 0xFFFFFFFF))
    }
}
