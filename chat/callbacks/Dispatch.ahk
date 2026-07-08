; ======================================================
; ChatDispatch.ahk — WebMessage dispatch + callback includes
;
; Handles OnWebMessageReceived and includes all callback modules.
; Extracted from ChatWindow.ahk for cleaner separation.
; ======================================================

OnWebMessageReceived(sender, args) {
    try {
        msg := args.TryGetWebMessageAsString()
        if !msg
            return
        parsed := jsongo.Parse(msg)
        action := parsed.Get("action", "")
        switch action {
            case "chatSend":
                handleChatSend(parsed.Get("message", ""))
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
    }
}

#Include Message.ahk
#Include Edit.ahk
#Include Branch.ahk
#Include Sidebar.ahk
