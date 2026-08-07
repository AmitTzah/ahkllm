; ======================================================
; SettingsApply.ahk — apply a settings Map to the global variables
; ======================================================

class SettingsApply {
    ; Apply settings Map to global variables.
    ; Called on startup and when settings are updated via IPC.
    static ApplyToGlobals(settings) {
        SettingsApply._ApplyProviders(settings)
        SettingsApply._ApplyModels(settings)
        SettingsApply._ApplyAssistants(settings)
        SettingsApply._ApplyCommands(settings)
        SettingsApply._ApplySubmenuOrder(settings)
        SettingsApply._ApplyThreadTitles(settings)
        SettingsApply._ApplyUI(settings)
        SettingsApply._ApplyIcons(settings)
        SettingsApply._ApplyHotkeys(settings)
        SettingsApply._ApplyApiLogs(settings)
        SettingsApply._ApplyTrash(settings)
        SettingsApply._ApplyMenuItems(settings)
        global chatShortcut
        if settings.Has("chatShortcut")
            chatShortcut := settings["chatShortcut"]
        global newChatStartsWith
        if settings.Has("newChatStartsWith")
            newChatStartsWith := settings["newChatStartsWith"]
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
            entry := {
                provider: m.Has("provider") ? m["provider"] : "",
                input: m.Has("input") ? m["input"] : 0,
                cachedInput: m.Has("cachedInput") ? m["cachedInput"] : "",
                output: m.Has("output") ? m["output"] : 0,
                context: m.Has("context") ? m["context"] : 0,
                reasoning: m.Has("reasoning") ? m["reasoning"] : false,
                vision: m.Has("vision") ? m["vision"] : false
            }
            ; Preserve new metadata fields (api, compat, thinkingLevelMap, thinkingOff)
            if m.Has("api")
                entry.api := m["api"]
            if m.Has("compat") && IsObject(m["compat"])
                entry.compat := SettingsPersistence._ToMap(m["compat"])
            if m.Has("thinkingLevelMap") && IsObject(m["thinkingLevelMap"])
                entry.thinkingLevelMap := SettingsPersistence._ToMap(m["thinkingLevelMap"])
            if m.Has("thinkingOff")
                entry.thinkingOff := m["thinkingOff"]
            newModels[k] := entry
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
                temperature: a.Has("temperature") ? a["temperature"] : ""
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
            SettingsApply._SetIfNonEmpty(cmd, c, "commandName")
            SettingsApply._SetIfNonEmpty(cmd, c, "menuText")
            SettingsApply._SetIfNonEmpty(cmd, c, "APIModels")
            SettingsApply._SetIfNonEmpty(cmd, c, "pasteMode")
            SettingsApply._SetIfTruthy(cmd, c, "stream")
            SettingsApply._SetIfTruthy(cmd, c, "isFIM")
            SettingsApply._SetIfTruthy(cmd, c, "showInputBox")
            if c.Has("userMessage") && c["userMessage"] != ""
                cmd.userMessage := StrReplace(c["userMessage"], "``n", "`n")
            SettingsApply._SetIfNonEmpty(cmd, c, "systemMessage")
            SettingsApply._SetIfNonEmpty(cmd, c, "systemMessageFile")
            SettingsApply._SetIfNonEmpty(cmd, c, "inputBoxDefault")
            SettingsApply._SetIfNonEmpty(cmd, c, "temperature")
            SettingsApply._SetIfNonEmpty(cmd, c, "maxTokens")
            SettingsApply._SetIfNonEmpty(cmd, c, "stop")
            SettingsApply._SetIfNonEmptyTags(cmd, c)
            SettingsApply._SetIfNonEmpty(cmd, c, "directAccelerator")
            SettingsApply._SetIfTruthy(cmd, c, "expandNewlines")
            SettingsApply._SetIfNonZero(cmd, c, "maxContextWords")
            SettingsApply._SetIfTruthy(cmd, c, "includeImageContext")
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
        global responseWindowFontFace, responseWindowFontSize

        if !settings.Has("ui")
            return
        u := settings["ui"]
        if u.Has("responseFont") && u["responseFont"] != ""
            responseWindowFontFace := u["responseFont"]
        if u.Has("responseFontSize") && u["responseFontSize"] != ""
            responseWindowFontSize := u["responseFontSize"]
        SettingsApply._ApplyInputWindow(u)
        SettingsApply._ApplySuspendBanner(u)
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
        if ic.Has("iconOn")
            iconOn := ic["iconOn"]
        if ic.Has("iconOff")
            iconOff := ic["iconOff"]
    }

    static _ApplyHotkeys(settings) {
        global mainHotkey, reloadHotkey, closeWindowsHotkey, suspendHotkey

        if !settings.Has("hotkeys")
            return
        hk := settings["hotkeys"]
        ; Apply the saved value even when empty — an empty field means the
        ; hotkey is disabled (nothing is registered for it). Skipping empty
        ; values kept the previous binding alive forever.
        if hk.Has("main")
            mainHotkey := hk["main"]
        if hk.Has("reload")
            reloadHotkey := hk["reload"]
        if hk.Has("closeWindows")
            closeWindowsHotkey := hk["closeWindows"]
        if hk.Has("suspend")
            suspendHotkey := hk["suspend"]
    }

    static _ApplyApiLogs(settings) {
        global apiLogMaxEntries

        if !settings.Has("apiLogs")
            return
        al := settings["apiLogs"]
        if al.Has("maxEntries") {
            apiLogMaxEntries := al["maxEntries"]
            ApiLogger.TrimToLimit()
        }
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
}
