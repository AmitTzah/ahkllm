#Include ..\applications\ApplicationChat.ahk

postApplicationState(*) {
    global activeThreadId
    if !activeThreadId || !ApplicationRepo.Session(activeThreadId) {
        postWebMessage("applicationState", {connected: false})
        return
    }
    if ApplicationChat.active.Has(activeThreadId) {
        context := ApplicationChat.active[activeThreadId]
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("applicationState", {connected: true, threadId: activeThreadId, leafId: path.Length ? path[path.Length].id : "", label: context["label"], phase: context["phase"], running: true, actions: [], pending: false, complete: false})
        return
    }
    if !ApplicationChat.active.Count
        try ExternalApplications.FlushReleases()
    state := ApplicationRepo.State(activeThreadId)
    try {
        description := ExternalApplications.Call(activeThreadId, "session.describe", state)
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("applicationState", {connected: true, threadId: activeThreadId, leafId: path.Length ? path[path.Length].id : "", label: description.Get("label", "Application"), phase: description.Get("phase", ""), actions: description.Get("actions", []), pending: path.Length && path[path.Length].role = "user" && description.Get("can_run", true), complete: description.Get("complete", false), blocked: !description.Get("can_run", true) && !description.Get("complete", false), notice: description.Get("notice", "")})
    } catch Error as e {
        postWebMessage("applicationState", {connected: true, threadId: activeThreadId, label: "Application unavailable", error: e.Message, actions: []})
    }
}

handleApplicationAction(parsed) {
    global activeThreadId
    _RequireApplicationActionOrigin(parsed)
    if _HasActiveOperationForUi(activeThreadId)
        throw Error("Wait for the current model turn before changing application state.")
    action := parsed.Get("id", "")
    if action = "__run" {
        postWebMessage("setChatButtonsEnabled", {enabled: false, threadId: activeThreadId})
        _BuildAndFireRequest()
        postApplicationState()
        return
    }
    state := ApplicationRepo.State(activeThreadId)
    if !IsObject(state)
        throw Error("This chat is not application-connected.")
    description := ExternalApplications.Call(activeThreadId, "session.describe", state)
    label := "", available := false
    for item in description["actions"] {
        if item["id"] = action {
            available := true
            label := item["label"]
            break
        }
    }
    if !available
        throw Error("Application action is unavailable on this branch.")
    result := ExternalApplications.Call(activeThreadId, "action.perform", state, Map("action", action))
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    parent := path.Length ? path[path.Length].id : ""
    ChatDB.BeginTransaction()
    try {
        messageId := ChatDB.Msg_Insert({thread_id: activeThreadId, role: "user", content: label, parent_id: parent})
        replay := [Map("role", "user", "content", ApplicationWire.InputParts(result.Get("message", label)))]
        ApplicationRepo.SaveNode(messageId, result["state"], replay, "action")
        ChatDB.CommitTransaction()
    } catch Error as e {
        ChatDB.RollbackTransaction()
        throw e
    }
    _LoadThreadAndRefreshUI(activeThreadId)
    description := ExternalApplications.Call(activeThreadId, "session.describe", result["state"])
    if !description.Get("complete", false) && action != "recover"
        _BuildAndFireRequest()
    postApplicationState()
}

handleApplicationDisconnect(parsed) {
    global activeThreadId
    _RequireApplicationActionOrigin(parsed)
    if _HasActiveOperationForUi(activeThreadId)
        throw Error("Finish the active application turn before disconnecting.")
    session := ApplicationRepo.Session(activeThreadId)
    if !session
        return
    ExternalApplications.Disconnect(session.application_id)
    postApplicationState()
}

_RequireApplicationActionOrigin(parsed) {
    global activeThreadId
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    if parsed.Get("threadId", "") != activeThreadId || !path.Length || parsed.Get("leafId", "") != path[path.Length].id
        throw Error("The selected chat or branch changed. Use its current application actions.")
}
