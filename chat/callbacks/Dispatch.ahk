; ======================================================
; ChatDispatch.ahk — WebMessage dispatch + callback includes
;
; Handles OnWebMessageReceived and includes all callback modules.
; Extracted from ChatWindow.ahk for cleaner separation.
; ======================================================

; Surface an error to both the debug log AND the chat UI.
; Callable from any callback — re-enables buttons and shows red banner.
_SurfaceError(context, err) {
    errorMsg := "[" context "] " err.Message
    debugLog("ERROR: " errorMsg "`nStack: " (err.HasProp("Stack") ? err.Stack : "none"), "ErrorHandler")
    postWebMessage("showError", { message: errorMsg })
    postWebMessage("setChatButtonsEnabled", true)
    startLoadingCursor(false)
}

OnWebMessageReceived(sender, args) {
    try {
        msg := args.TryGetWebMessageAsString()
        if !msg
            return
        parsed := jsongo.Parse(msg)
        action := parsed.Get("action", "")
        if action = "chatSend" || action = "deleteAttachment"
            debugLog("[DISPATCH] Received " action " action, msgLen=" StrLen(msg), "AttachPipeline")
        switch action {
            case "chatSend":
                handleChatSend(parsed)
            case "deleteAttachment":
                handleDeleteAttachment(parsed)
            case "retry":
                handleRetry(parsed)
            case "editMessage":
                handleEdit(parsed)
            case "deleteMessage":
                handleDelete(parsed.Get("id", ""))
            case "switchBranch":
                handleBranchSwitch(parsed)
            case "forkChat":
                handleFork(parsed.Get("id", ""))
            case "setFeedback":
                handleFeedback(parsed)
            case "sidebarAction":
                handleSidebarAction(parsed)
            case "requestAssistantList":
                postAssistantsToWebView()
            case "updateModelSettings":
                handleModelSettingsUpdate(parsed)
            case "switchAssistant":
                handleSwitchAssistant(parsed)
            case "cancelStream":
                handleCancelStream()
            case "requestCurrentSettings":
                postCurrentSettingsToWebView()
        }
    } catch Error as e {
        _SurfaceError("Dispatch." (IsSet(action) ? action : "unknown"), e)
    }
}

#Include Message.ahk
#Include Edit.ahk
#Include Branch.ahk
#Include Sidebar.ahk
