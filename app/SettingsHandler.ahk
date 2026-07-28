; ======================================================
; SettingsHandler.ahk — JSON settings persistence
;
; Load/Save settings.json from AppData.
; Provides fallback to UserConfig.ahk defaults.
; Merges loaded settings with defaults for missing keys.
; ======================================================

class SettingsHandler {
    static settingsPath := ""
    static _initialDefaults := unset

    ; Call once at startup before ApplyToGlobals to cache the true defaults.
    static CacheInitialDefaults() {
        SettingsHandler._initialDefaults := SettingsHandler.GetDefaults()
    }

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

    ; Convert jsongo object/array to AHK Map/Array.
    ; Converts jsongo/JSON objects to AHK Map/Array recursively.
    ; jsongo.Parse returns: AHK Maps for JSON objects, AHK Arrays for JSON arrays,
    ; AHK primitives (String, Integer, Float) for scalars, and true/false for booleans.
    static _ToMap(obj) {
        if !IsObject(obj)
            return obj
        ; AHK Map — iterate key-value pairs directly
        if Type(obj) = "Map" {
            result := Map()
            for k, v in obj
                result[k] := SettingsHandler._ToMap(v)
            return result
        }
        ; AHK Array — iterate items by index
        if Type(obj) = "Array" {
            result := []
            for item in obj
                result.Push(SettingsHandler._ToMap(item))
            return result
        }
        ; jsongo wrapper objects have OwnProps() method
        if obj.HasMethod("OwnProps") {
            result := Map()
            for k, v in obj.OwnProps()
                result[k] := SettingsHandler._ToMap(v)
            return result
        }
        return obj
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
            try FileDelete(path)
            FileAppend(jsonStr, path, "UTF-8")
            debugLog("[SETTINGS] Saved to " path)
            return true
        } catch Error as e {
            debugLog("[SETTINGS] Failed to save settings.json: " e.Message)
            return false
        }
    }

    ; Build complete defaults Map from current UserConfig.ahk globals.
    ; Delegates to section-specific helpers for readability.
    static GetDefaults() {
        d := Map()
        d["version"] := 1
        d["providers"] := SettingsHandler._DefaultsProviders()
        d["models"] := SettingsHandler._DefaultsModels()
        d["assistants"] := SettingsHandler._DefaultsAssistants()
        d["commands"] := SettingsHandler._DefaultsCommands()
        d["submenuOrder"] := SettingsHandler._DefaultsSubmenuOrder()
        d["threadTitles"] := SettingsHandler._DefaultsThreadTitles()
        d["ui"] := SettingsHandler._DefaultsUI()
        d["theme"] := Map("darkMode", false)
        d["icons"] := SettingsHandler._DefaultsIcons()
        d["hotkeys"] := SettingsHandler._DefaultsHotkeys()
        d["apiLogs"] := SettingsHandler._DefaultsApiLogs()
        d["trash"] := SettingsHandler._DefaultsTrash()
        d["menuItems"] := SettingsHandler._DefaultsMenuItems()
        return d
    }

    ; --- Defaults helpers (read from UserConfig globals) ---

    static _DefaultsProviders() {
        global providers, providerMap

        provMap := Map()
        for providerKey, p in providers {
            provMap[providerKey] := Map(
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
        }
        ; Fill prefixes from global providerMap
        if IsSet(providerMap)
            SettingsHandler._FillPrefixesFromProviderMap(provMap)
        return provMap
    }

    static _FillPrefixesFromProviderMap(provMap) {
        global providerMap
        for prefix, prov in providerMap {
            if !provMap.Has(prov)
                continue
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

    static _DefaultsModels() {
        global models

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
        return modelMap
    }

    static _DefaultsAssistants() {
        global assistants

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
        return asstList
    }

    static _DefaultsCommands() {
        global commands

        cmdList := []
        for c in commands
            cmdList.Push(SettingsHandler._CommandToMap(c))
        return cmdList
    }

    static _DefaultsSubmenuOrder() {
        global submenuOrder

        soList := []
        if IsSet(submenuOrder) {
            for _, tag in submenuOrder
                soList.Push(tag)
        }
        return soList
    }

    static _DefaultsThreadTitles() {
        global autoTitleGenerationEnabled, titleGenModel, titleGenSystemPrompt, titleGenMaxTokens

        return Map(
            "enabled", IsSet(autoTitleGenerationEnabled) ? autoTitleGenerationEnabled : true,
            "model", IsSet(titleGenModel) ? titleGenModel : "deepseek/deepseek-v4-flash",
            "prompt", IsSet(titleGenSystemPrompt) ? titleGenSystemPrompt : "",
            "maxTokens", IsSet(titleGenMaxTokens) ? titleGenMaxTokens : 50
        )
    }

    static _DefaultsUI() {
        global chatDefaultModel, responseWindowFontFace
        global inputWindowBackground, inputWindowFontSize, inputWindowFontColor, inputWindowFontFace, inputWindowWidth, inputWindowHeight
        global suspendBannerText, suspendBannerFontSize, suspendBannerFontFace, suspendBannerTextColor, suspendBannerBackground

        return Map(
            "chatDefaultModel", IsSet(chatDefaultModel) ? chatDefaultModel : "deepseek/deepseek-v4-flash",
            "responseFont", IsSet(responseWindowFontFace) ? responseWindowFontFace : "Inter",
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
    }

    static _DefaultsIcons() {
        global iconOn, iconOff

        return Map(
            "iconOn", IsSet(iconOn) ? iconOn : "icons\IconOn.ico",
            "iconOff", IsSet(iconOff) ? iconOff : "icons\IconOff.ico"
        )
    }

    static _DefaultsHotkeys() {
        global mainHotkey, saveReloadHotkey, closeWindowsHotkey, suspendHotkey

        return Map(
            "main", IsSet(mainHotkey) ? mainHotkey : "``",
            "saveReload", IsSet(saveReloadHotkey) ? saveReloadHotkey : "~^s",
            "closeWindows", IsSet(closeWindowsHotkey) ? closeWindowsHotkey : "~^w",
            "suspend", IsSet(suspendHotkey) ? suspendHotkey : "CapsLock & ``"
        )
    }

    static _DefaultsApiLogs() {
        global apiLogMaxEntries

        return Map(
            "maxEntries", IsSet(apiLogMaxEntries) ? apiLogMaxEntries : 20
        )
    }

    static _DefaultsTrash() {
        global trashRetentionDays

        return Map(
            "retentionDays", IsSet(trashRetentionDays) ? trashRetentionDays : 30
        )
    }

    static _DefaultsMenuItems() {
        global quickAccessMenuItems, trayMenuItems

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
        return Map(
            "quickAccess", qaList,
            "tray", trayList
        )
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
        SettingsHandler._ApplyProviders(settings)
        SettingsHandler._ApplyModels(settings)
        SettingsHandler._ApplyAssistants(settings)
        SettingsHandler._ApplyCommands(settings)
        SettingsHandler._ApplySubmenuOrder(settings)
        SettingsHandler._ApplyThreadTitles(settings)
        SettingsHandler._ApplyUI(settings)
        SettingsHandler._ApplyIcons(settings)
        SettingsHandler._ApplyHotkeys(settings)
        SettingsHandler._ApplyApiLogs(settings)
        SettingsHandler._ApplyTrash(settings)
        SettingsHandler._ApplyMenuItems(settings)
    }

    ; --- Apply helpers (write from settings Map to globals) ---

    static _ApplyProviders(settings) {
        global providers, providerMap

        if !settings.Has("providers")
            return
        newProviders := Map()
        newProviderMap := Map()
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
            if p.Has("prefixes") && IsObject(p["prefixes"]) {
                for _, prefix in p["prefixes"]
                    newProviderMap[prefix] := k
            }
        }
        providers := newProviders
        ; Only overwrite providerMap when prefixes were actually defined,
        ; otherwise keep the UserConfig mapping (e.g. older settings.json without prefixes)
        if newProviderMap.Count > 0
            providerMap := newProviderMap
    }

    static _ApplyModels(settings) {
        global models

        if !settings.Has("models")
            return
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

    static _ApplyAssistants(settings) {
        global assistants

        if !settings.Has("assistants")
            return
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

    static _ApplyCommands(settings) {
        global commands

        if !settings.Has("commands")
            return
        newCommands := []
        for _, c in settings["commands"] {
            cmd := {}
            SettingsHandler._SetIfNonEmpty(cmd, c, "commandName")
            SettingsHandler._SetIfNonEmpty(cmd, c, "menuText")
            SettingsHandler._SetIfNonEmpty(cmd, c, "APIModels")
            SettingsHandler._SetIfNonEmpty(cmd, c, "pasteMode")
            SettingsHandler._SetIfTruthy(cmd, c, "stream")
            SettingsHandler._SetIfTruthy(cmd, c, "isFIM")
            SettingsHandler._SetIfTruthy(cmd, c, "showInputBox")
            if c.Has("userMessage") && c["userMessage"] != ""
                cmd.userMessage := StrReplace(c["userMessage"], "``n", "`n")
            SettingsHandler._SetIfNonEmpty(cmd, c, "systemMessage")
            SettingsHandler._SetIfNonEmpty(cmd, c, "systemMessageFile")
            SettingsHandler._SetIfNonEmpty(cmd, c, "inputBoxDefault")
            SettingsHandler._SetIfNonEmpty(cmd, c, "temperature")
            SettingsHandler._SetIfNonEmpty(cmd, c, "maxTokens")
            SettingsHandler._SetIfNonEmpty(cmd, c, "stop")
            SettingsHandler._SetIfNonEmptyTags(cmd, c)
            SettingsHandler._SetIfNonEmpty(cmd, c, "directAccelerator")
            SettingsHandler._SetIfTruthy(cmd, c, "expandNewlines")
            SettingsHandler._SetIfNonZero(cmd, c, "maxContextWords")
            SettingsHandler._SetIfTruthy(cmd, c, "includeImageContext")
            if c.Has("thinking")
                cmd.thinking := c["thinking"]
            newCommands.Push(cmd)
        }
        commands := newCommands
    }

    static _SetIfNonEmpty(cmd, c, key) {
        if c.Has(key) && c[key] != ""
            cmd.%key% := c[key]
    }

    static _SetIfTruthy(cmd, c, key) {
        if c.Has(key) && c[key]
            cmd.%key% := c[key]
    }

    static _SetIfNonZero(cmd, c, key) {
        if c.Has(key) && c[key] != 0
            cmd.%key% := c[key]
    }

    static _SetIfNonEmptyTags(cmd, c) {
        if c.Has("tags") && IsObject(c["tags"]) && c["tags"].Length > 0
            cmd.tags := c["tags"]
    }

    static _ApplySubmenuOrder(settings) {
        global submenuOrder

        if !settings.Has("submenuOrder")
            return
        newSO := []
        for _, tag in settings["submenuOrder"]
            newSO.Push(tag)
        submenuOrder := newSO
    }

    static _ApplyThreadTitles(settings) {
        global autoTitleGenerationEnabled, titleGenModel, titleGenSystemPrompt, titleGenMaxTokens

        if !settings.Has("threadTitles")
            return
        tt := settings["threadTitles"]
        autoTitleGenerationEnabled := tt.Has("enabled") ? tt["enabled"] : true
        if tt.Has("model") && tt["model"] != ""
            titleGenModel := tt["model"]
        if tt.Has("prompt") && tt["prompt"] != ""
            titleGenSystemPrompt := tt["prompt"]
        if tt.Has("maxTokens") && tt["maxTokens"] != ""
            titleGenMaxTokens := tt["maxTokens"]
    }

    static _ApplyUI(settings) {
        global chatDefaultModel, responseWindowFontFace
        global inputWindowBackground, inputWindowFontSize, inputWindowFontColor, inputWindowFontFace, inputWindowWidth, inputWindowHeight
        global suspendBannerText, suspendBannerFontSize, suspendBannerFontFace, suspendBannerTextColor, suspendBannerBackground

        if !settings.Has("ui")
            return
        u := settings["ui"]
        if u.Has("chatDefaultModel") && u["chatDefaultModel"] != ""
            chatDefaultModel := u["chatDefaultModel"]
        if u.Has("responseFont") && u["responseFont"] != ""
            responseWindowFontFace := u["responseFont"]
        SettingsHandler._ApplyInputWindow(u)
        SettingsHandler._ApplySuspendBanner(u)
    }

    static _ApplyInputWindow(u) {
        global inputWindowBackground, inputWindowFontSize, inputWindowFontColor, inputWindowFontFace, inputWindowWidth, inputWindowHeight

        if !u.Has("inputWindow")
            return
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

    static _ApplySuspendBanner(u) {
        global suspendBannerText, suspendBannerFontSize, suspendBannerFontFace, suspendBannerTextColor, suspendBannerBackground

        if !u.Has("suspendBanner")
            return
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

    static _ApplyIcons(settings) {
        global iconOn, iconOff

        if !settings.Has("icons")
            return
        ic := settings["icons"]
        if ic.Has("iconOn") && ic["iconOn"] != ""
            iconOn := ic["iconOn"]
        if ic.Has("iconOff") && ic["iconOff"] != ""
            iconOff := ic["iconOff"]
    }

    static _ApplyHotkeys(settings) {
        global mainHotkey, saveReloadHotkey, closeWindowsHotkey, suspendHotkey

        if !settings.Has("hotkeys")
            return
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

    static _ApplyApiLogs(settings) {
        global apiLogMaxEntries

        if !settings.Has("apiLogs")
            return
        al := settings["apiLogs"]
        if al.Has("maxEntries")
            apiLogMaxEntries := al["maxEntries"]
    }

    static _ApplyTrash(settings) {
        global trashRetentionDays

        if !settings.Has("trash")
            return
        tr := settings["trash"]
        if tr.Has("retentionDays")
            trashRetentionDays := tr["retentionDays"]
    }

    static _ApplyMenuItems(settings) {
        global quickAccessMenuItems, trayMenuItems

        if !settings.Has("menuItems")
            return
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

    static _UUID() {
        return Format("{1:08x}-{2:04x}-{3:04x}-{4:04x}-{5:012x}",
            A_TickCount, Random(0, 0xFFFF), Random(0, 0xFFFF),
            Random(0, 0xFFFF), Random(0, 0xFFFFFFFF))
    }
}
