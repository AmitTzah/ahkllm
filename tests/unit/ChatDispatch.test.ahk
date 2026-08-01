; ======================================================
; ChatDispatch.test.ahk — Unit tests for chat/callbacks/Dispatch.ahk
;
; Dispatch.ahk is only #Included by ChatWindow.ahk, so the test harness
; never loaded it before. These tests exercise OnWebMessageReceived's
; action switch (every case) plus the _Handle* settings handlers,
; _OnWebViewReady and _SurfaceError. PostMessage/FileSelect/RunWait
; built-ins are mocked at script level; the webview sink is captured via
; the global responseWindow override.
; ======================================================

#Include ..\..\chat\callbacks\Dispatch.ahk

; --- Script-level mocks for built-ins the module calls ---
RunWait(cmd := "", workDir := "", options := "", &outPID := 0) {
    global _mockRunWaitCalls, _mockRunWaitExitCode
    _mockRunWaitCalls.Push(cmd)
    return _mockRunWaitExitCode
}

FileSelect(options := "", root := "", prompt := "", filter := "") {
    global _mockFileSelectResult
    return _mockFileSelectResult
}

_mockHideWindow(args*) {
    global _mockHideWindowCalls
    _mockHideWindowCalls += 1
}
global chatWindow := { Hide: _mockHideWindow }

class ChatDispatchTest {

    static __New() {
        RegisterTestClass("ChatDispatchTest")
    }

    _args(jsonStr) {
        return { TryGetWebMessageAsString: (*) => jsonStr }
    }

    _captureWebView() {
        global responseWindow
        this._ensureRequestParams()
        captured := []
        oldResponseWindow := responseWindow
        ; AHK v2 passes the receiver object as the first argument when calling
        ; a function stored in an object property, hence the leading param.
        responseWindow := { PostWebMessageAsJSON: (obj, json) => captured.Push(json) }
        return { captured: captured, restore: (obj) => (responseWindow := oldResponseWindow) }
    }

    ; Earlier test classes replace the global requestParams with their own
    ; map; make sure the keys the dispatch handlers read exist.
    _ensureRequestParams() {
        global requestParams
        if !IsSet(requestParams) || !IsObject(requestParams)
            requestParams := Map()
        if !requestParams.Has("uniqueID")
            requestParams["uniqueID"] := "test-unique-id"
        if !requestParams.Has("mainScriptHiddenHwnd")
            requestParams["mainScriptHiddenHwnd"] := "0x0"
        if !requestParams.Has("singleAPIModelName")
            requestParams["singleAPIModelName"] := "deepseek-v4-flash"
    }

    _findCaptured(captured, target) {
        for _, json in captured {
            if InStr(json, '"target":"' target '"')
                return true
        }
        return false
    }

    _setupDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_dispatch_" A_TickCount ".db")
    }

    _teardownDb() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    _withTempSettingsPath() {
        oldPath := SettingsHandler.settingsPath
        tempPath := A_Temp "\test_dispatch_settings_" A_TickCount ".json"
        SettingsHandler.settingsPath := tempPath
        try FileDelete(tempPath)
        return { tempPath: tempPath, restore: (obj) => (SettingsHandler.settingsPath := oldPath) }
    }

    SurfaceError_PostsShowErrorAndReEnables() {
        web := this._captureWebView()
        try {
            _SurfaceError("ctx", { Message: "boom", Stack: "stack-line" })
        } finally {
            web.restore()
        }
        if !this._findCaptured(web.captured, "showError")
            throw Error("Expected showError post")
        if !this._findCaptured(web.captured, "setChatButtonsEnabled")
            throw Error("Expected setChatButtonsEnabled post")
    }

    Dispatch_EmptyMessage_Returns() {
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args(""))
        } finally {
            web.restore()
        }
        if web.captured.Length != 0
            throw Error("Empty message must not post anything")
    }

    Dispatch_ReadOnlyActions_PostExpected() {
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"requestAssistantList"}'))
            OnWebMessageReceived("", this._args('{"action":"requestCurrentSettings"}'))
            OnWebMessageReceived("", this._args('{"action":"debugLog","message":"hi"}'))
            OnWebMessageReceived("", this._args('{"action":"webViewReady"}'))
        } finally {
            web.restore()
        }
        if !this._findCaptured(web.captured, "assistantList")
            throw Error("requestAssistantList should post assistantList")
        if !this._findCaptured(web.captured, "currentSettings")
            throw Error("requestCurrentSettings should post currentSettings")
    }

    Dispatch_RequestAllSettings_PostsMerged() {
        sp := this._withTempSettingsPath()
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"requestAllSettings"}'))
        } finally {
            web.restore()
            sp.restore()
        }
        if !this._findCaptured(web.captured, "currentSettings")
            throw Error("requestAllSettings should post currentSettings")
    }

    Dispatch_RequestDefaultSettings_PostsAndSaves() {
        sp := this._withTempSettingsPath()
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"requestDefaultSettings"}'))
        } finally {
            web.restore()
        }
        if !this._findCaptured(web.captured, "defaultSettings")
            throw Error("requestDefaultSettings should post defaultSettings")
        if !FileExist(sp.tempPath)
            throw Error("requestDefaultSettings should write defaults to settings.json")
        sp.restore()
        try FileDelete(sp.tempPath)
    }

    Dispatch_SaveSettings_Success() {
        sp := this._withTempSettingsPath()
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"saveSettings","data":{"hotkeys":{"main":"`"}}}'))
        } finally {
            web.restore()
        }
        found := false
        for _, json in web.captured {
            ; jsongo serializes booleans as 1/0, not true/false.
            if InStr(json, '"target":"settingsSaved"') && InStr(json, '"success":1')
                found := true
        }
        if !found
            throw Error("saveSettings success should post settingsSaved success:true")
        if !FileExist(sp.tempPath)
            throw Error("saveSettings should write the settings file")
        sp.restore()
        try FileDelete(sp.tempPath)
    }

    Dispatch_SaveSettings_NoData() {
        sp := this._withTempSettingsPath()
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"saveSettings"}'))
        } finally {
            web.restore()
            sp.restore()
        }
        found := false
        for _, json in web.captured {
            if InStr(json, '"target":"settingsSaved"') && InStr(json, "No data received")
                found := true
        }
        if !found
            throw Error("saveSettings without data should post the no-data error")
    }

    Dispatch_RefreshModelPricing_Success() {
        global _mockRunWaitExitCode
        _mockRunWaitExitCode := 0
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"refreshModelPricing"}'))
        } finally {
            web.restore()
        }
        found := false
        for _, json in web.captured {
            if InStr(json, '"target":"modelPricingRefresh"') && InStr(json, '"success":1')
                found := true
        }
        if !found
            throw Error("refreshModelPricing should post a success result")
    }

    Dispatch_RefreshModelPricing_RunFailed() {
        global _mockRunWaitExitCode
        _mockRunWaitExitCode := 7
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"refreshModelPricing"}'))
        } finally {
            web.restore()
        }
        found := false
        for _, json in web.captured {
            if InStr(json, '"target":"modelPricingRefresh"') && InStr(json, "exited with code 7")
                found := true
        }
        if !found
            throw Error("refreshModelPricing should report the failing exit code")
    }

    Dispatch_BrowseIcon_StoresRelativePath() {
        global _mockFileSelectResult
        _mockFileSelectResult := A_ScriptDir "\..\icons\test.ico"
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"browseIcon","field":"iconOn"}'))
        } finally {
            web.restore()
        }
        found := false
        for _, json in web.captured {
            if InStr(json, '"target":"iconFileSelected"') {
                parsed := jsongo.Parse(json)
                if parsed["data"]["path"] = "icons\test.ico"
                    found := true
            }
        }
        if !found
            throw Error("Repo-relative icon path should be stripped of the repo root")
    }

    Dispatch_BrowseIcon_KeepsAbsolutePath() {
        global _mockFileSelectResult
        _mockFileSelectResult := "C:\elsewhere\icon.ico"
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"browseIcon","field":"iconOff"}'))
        } finally {
            web.restore()
        }
        found := false
        for _, json in web.captured {
            if InStr(json, '"target":"iconFileSelected"') {
                parsed := jsongo.Parse(json)
                if parsed["data"]["path"] = "C:\elsewhere\icon.ico"
                    found := true
            }
        }
        if !found
            throw Error("Absolute icon path should be passed through unchanged")
    }

    Dispatch_BrowseIcon_CancelPostsNothing() {
        global _mockFileSelectResult
        _mockFileSelectResult := ""
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"browseIcon","field":"iconOn"}'))
            OnWebMessageReceived("", this._args('{"action":"browseIcon","field":"other"}'))
        } finally {
            web.restore()
        }
        if this._findCaptured(web.captured, "iconFileSelected")
            throw Error("Cancelled/invalid icon browse must not post")
    }

    Dispatch_IpcActions_NoThrow() {
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"reloadScript"}'))
            OnWebMessageReceived("", this._args('{"action":"showApiLogs"}'))
        } finally {
            web.restore()
        }
    }

    Dispatch_WebViewReady_NoThread() {
        global activeThreadId
        old := activeThreadId
        activeThreadId := ""
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"webViewReady"}'))
        } finally {
            web.restore()
            activeThreadId := old
        }
    }

    Dispatch_WebViewReady_WithThread_LoadsUI() {
        global activeThreadId
        this._setupDb()
        threadId := ChatDB.Thread_Create("Dispatch Ready")
        old := activeThreadId
        activeThreadId := threadId
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"webViewReady"}'))
        } finally {
            web.restore()
            activeThreadId := old
            this._teardownDb()
        }
        if !this._findCaptured(web.captured, "initChatMode")
            throw Error("webViewReady with a thread should load the chat UI")
    }

    Dispatch_SidebarAction_NewChat_AppliesDefaultFontSize() {
        global activeThreadId, responseWindowFontSize
        this._setupDb()
        old := activeThreadId
        oldFont := responseWindowFontSize
        activeThreadId := ""
        responseWindowFontSize := "19"
        web := this._captureWebView()
        createdThreads := 0
        newThreadSettings := ""
        loaded := false
        try {
            OnWebMessageReceived("", this._args('{"action":"sidebarAction","subAction":"newChat"}'))
            createdThreads := ChatDB.Thread_List().Length
            if createdThreads > 0 {
                newThreadSettings := ChatDB.Thread_GetSettings(ChatDB.Thread_List()[1].id)
            }
            loaded := this._findCaptured(web.captured, "loadThread")
        } finally {
            web.restore()
            activeThreadId := old
            responseWindowFontSize := oldFont
            this._teardownDb()
        }
        if createdThreads = 0
            throw Error("newChat should create a thread")
        if newThreadSettings.fontSize != 19
            throw Error("New thread should inherit the default font size, got '" newThreadSettings.fontSize "'")
        if !loaded
            throw Error("newChat should load the new thread")
    }

    Dispatch_HideWindow() {
        global _mockHideWindowCalls
        _mockHideWindowCalls := 0
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"hideWindow"}'))
        } finally {
            web.restore()
        }
        if _mockHideWindowCalls != 1
            throw Error("hideWindow should hide the chat window")
    }

    Dispatch_GuardedActions_NoThrow() {
        global activeThreadId
        old := activeThreadId
        activeThreadId := ""
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":"chatSend"}'))
            OnWebMessageReceived("", this._args('{"action":"retry"}'))
            OnWebMessageReceived("", this._args('{"action":"editMessage"}'))
            OnWebMessageReceived("", this._args('{"action":"deleteMessage"}'))
            OnWebMessageReceived("", this._args('{"action":"deleteAttachment"}'))
            OnWebMessageReceived("", this._args('{"action":"switchBranch"}'))
            OnWebMessageReceived("", this._args('{"action":"forkChat"}'))
            OnWebMessageReceived("", this._args('{"action":"sidebarAction","subAction":"loadTree"}'))
            OnWebMessageReceived("", this._args('{"action":"searchMessages","query":"x"}'))
            OnWebMessageReceived("", this._args('{"action":"cancelStream"}'))
            OnWebMessageReceived("", this._args('{"action":"updateFontSize","size":"18"}'))
            OnWebMessageReceived("", this._args('{"action":"updateModelSettings","model":"deepseek/deepseek-v4-flash"}'))
            OnWebMessageReceived("", this._args('{"action":"switchAssistant","assistantName":"Test Assistant"}'))
        } finally {
            web.restore()
            activeThreadId := old
        }
        if !this._findCaptured(web.captured, "searchResults")
            throw Error("Short search query should post empty searchResults")
        if !this._findCaptured(web.captured, "setChatButtonsEnabled")
            throw Error("cancelStream should re-enable chat buttons")
    }

    Dispatch_InvalidJson_PostsShowError() {
        web := this._captureWebView()
        try {
            OnWebMessageReceived("", this._args('{"action":'))
        } finally {
            web.restore()
        }
        if !this._findCaptured(web.captured, "showError")
            throw Error("Invalid JSON should surface an error to the UI")
    }

}
