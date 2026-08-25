; ----------------------------------------------------
; Custom messages
; ----------------------------------------------------

class CustomMessages {
    ; Loading cursor notifications (main script → tooltip + cursor)
    static WM_LOADING_START := 0x400 + 123
    static WM_LOADING_FINISH := 0x400 + 124

    ; Single-window chat model messages
    ; NOTE: Must use 0x500+ range — WebView2 uses 0x400-0x4FF for internal messages.
    ; Collision with WebView2 internal messages causes access-violation crashes.
    static WM_CHAT_WINDOW_OPENED := 0x500 + 0
    static WM_LOAD_THREAD := 0x500 + 2
    static WM_TRIGGER_LLM := 0x500 + 4
    static WM_SHOW_DASHBOARD := 0x500 + 6
    static WM_SHOW_API_LOGS := 0x500 + 7
    static WM_SETTINGS_UPDATED := 0x500 + 8
    static WM_RELOAD_MAIN := 0x500 + 9
    static WM_BACKUP_DIRTY := 0x500 + 10
    static WM_BACKUP_NOW := 0x500 + 11
    static WM_BACKUP_STATUS := 0x500 + 12
    static WM_BACKUP_STATUS_REQUEST := 0x500 + 13

    static registerHandlers(origin, handle) {
        switch origin {
            case "mainScript":
                for msg in [this.WM_LOADING_START,
                    this.WM_LOADING_FINISH,
                    this.WM_CHAT_WINDOW_OPENED,
                    this.WM_SHOW_API_LOGS]
                    OnMessage(msg, handle)

            case "subScript":
                for msg in [this.WM_LOAD_THREAD]
                    OnMessage(msg, handle)
        }
    }

    static notifyLoadingState(state, uniqueID, responseWindowhWnd := unset, mainScriptHiddenHwnd := unset) {
        try {
            switch state {
                case this.WM_CHAT_WINDOW_OPENED:
                    PostMessage(state, uniqueID, responseWindowhWnd, , "ahk_id " mainScriptHiddenHwnd)
                case this.WM_LOADING_START, this.WM_LOADING_FINISH:
                    PostMessage(state, uniqueID, 0, , "ahk_id " mainScriptHiddenHwnd)
            }
        }
    }

    ; --- Single-window chat IPC helpers ---

    ; Main → ChatWindow: tell it to load a different thread
    ; Uses PostMessage (async) via a temp file — avoids blocking the main script
    ; on slow WebView2 ExecuteScript calls in the ChatWindow process.
    static notifyLoadThread(threadId, chatWindowhWnd) {
        try {
            FileOpen(A_Temp "\chat_load_thread.txt", "w", "UTF-8-RAW").Write(threadId)
            PostMessage(this.WM_LOAD_THREAD, 0, 0, , "ahk_id " chatWindowhWnd)
        }
    }

    ; Main → ChatWindow: trigger LLM for the current thread (command-triggered chats).
    ; The wParam carries the command's stream flag (bug #203) - 1 = stream,
    ; 0 = single-shot JSON response.
    static notifyTriggerLLM(chatWindowhWnd, stream := true) {
        try PostMessage(this.WM_TRIGGER_LLM, stream ? 1 : 0, 0, , "ahk_id " chatWindowhWnd)
    }

    ; Main → ChatWindow: show inline dashboard
    static notifyShowDashboard(chatWindowhWnd) {
        try PostMessage(this.WM_SHOW_DASHBOARD, 0, 0, , "ahk_id " chatWindowhWnd)
    }

    ; ChatWindow → Main: open API logs viewer
    static notifyShowApiLogs(mainScriptHiddenHwnd) {
        try PostMessage(this.WM_SHOW_API_LOGS, 0, 0, , "ahk_id " mainScriptHiddenHwnd)
    }

    ; ChatWindow → Main: notify that settings were saved, reload settings
    static notifySettingsUpdated(mainScriptHiddenHwnd) {
        try PostMessage(this.WM_SETTINGS_UPDATED, 0, 0, , "ahk_id " mainScriptHiddenHwnd)
    }

    ; ChatWindow -> Main: durable data changed; increment Main's generation.
    static notifyBackupDirty(mainScriptHiddenHwnd) {
        try PostMessage(this.WM_BACKUP_DIRTY, 0, 0, , "ahk_id " mainScriptHiddenHwnd)
    }

    ; ChatWindow -> Main: request the same BackupManager implementation used
    ; by the automatic timer, without creating a second backup lifecycle.
    static notifyBackupNow(mainScriptHiddenHwnd, backupConfig := "") {
        try {
            requestPath := A_Temp "\AhkLLM_Backup_Request.json"
            try FileDelete(requestPath)
            if IsObject(backupConfig) {
                f := FileOpen(requestPath, "w", "UTF-8")
                f.Write(jsongo.Stringify(backupConfig))
                f.Close()
            }
            PostMessage(this.WM_BACKUP_NOW, 0, 0, , "ahk_id " mainScriptHiddenHwnd)
            return true
        } catch {
            return false
        }
    }

    static consumeBackupNowConfig() {
        requestPath := A_Temp "\AhkLLM_Backup_Request.json"
        if !FileExist(requestPath)
            return ""
        try {
            raw := FileRead(requestPath, "UTF-8")
            FileDelete(requestPath)
            return jsongo.Parse(raw)
        } catch {
            try FileDelete(requestPath)
            return ""
        }
    }

    static notifyBackupStatus(chatWindowhWnd) {
        try PostMessage(this.WM_BACKUP_STATUS, 0, 0, , "ahk_id " chatWindowhWnd)
    }

    static notifyBackupStatusRequest(mainScriptHiddenHwnd) {
        try PostMessage(this.WM_BACKUP_STATUS_REQUEST, 0, 0, , "ahk_id " mainScriptHiddenHwnd)
    }

    ; ChatWindow → Main: request full script reload (e.g. after hotkey changes)
    static notifyReloadMain(mainScriptHiddenHwnd) {
        try PostMessage(this.WM_RELOAD_MAIN, 0, 0, , "ahk_id " mainScriptHiddenHwnd)
    }
}
