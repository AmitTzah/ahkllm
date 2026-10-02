; ChatGPT account actions and durable catalog refresh.
_HandleRequestChatGptPlanStatus(extra := "") {
    status := ChatGptPlanAuth.Status()
    if IsObject(extra) {
        for key, value in extra.OwnProps()
            status.%key% := value
    }
    postWebMessage("chatGptPlanStatus", status)
}

_HandleBeginChatGptSignIn(parsed) {
    global _chatGptSignInState
    if IsObject(_chatGptSignInState) {
        ChatGptPlanAuth.CancelSignIn(_chatGptSignInState)
        SetTimer(_PollChatGptSignIn, 0)
    }
    newAccount := parsed.Get("newAccount", false) = true || parsed.Get("newAccount", false) = 1
    clientId := parsed.Get("clientId", "")
    _chatGptSignInState := ChatGptPlanAuth.BeginSignIn(newAccount, clientId)
    _HandleRequestChatGptPlanStatus({ authenticating: true, message: "Complete ChatGPT sign-in in your browser." })
    SetTimer(_PollChatGptSignIn, 100)
}

_PollChatGptSignIn() {
    global _chatGptSignInState
    if !IsObject(_chatGptSignInState) {
        SetTimer(, 0)
        return
    }
    result := ChatGptPlanAuth.PollSignIn(_chatGptSignInState)
    if !IsObject(result)
        return
    SetTimer(, 0)
    _chatGptSignInState := ""
    if result.HasOwnProp("success") && result.success {
        try _HandleRefreshChatGptModels(false)
        catch Error as e
            debugLog("[CHATGPT] Model refresh after sign-in failed: " e.Message)
    }
    _HandleRequestChatGptPlanStatus(result)
}

_HandleSetChatGptAccount(parsed) {
    clientId := parsed.Get("clientId", "")
    if clientId = "" || !ChatGptPlanAuth.SetActiveAccount(clientId)
        throw Error("The selected ChatGPT account is no longer available.")
    try _HandleRefreshChatGptModels(false)
    catch Error as e
        debugLog("[CHATGPT] Model refresh after account switch failed: " e.Message)
    _HandleRequestChatGptPlanStatus()
}

_HandleSignOutChatGpt(parsed) {
    result := ChatGptPlanAuth.SignOut(parsed.Get("clientId", ""))
    statusExtra := { message: "Signed out of ChatGPT for AhkLLM." }
    if IsObject(result) && result.HasOwnProp("remoteRevoked") && !result.remoteRevoked
        statusExtra.message := "Signed out locally. Remote revocation could not be confirmed; you can also disconnect AhkLLM in ChatGPT Settings."
    _HandleRequestChatGptPlanStatus(statusExtra)
}

_HandleRefreshChatGptModels(postStatus := true) {
    try {
        if !ChatGptPlanAuth.Status().authenticated
            throw Error("Sign in with ChatGPT in Settings → Providers to refresh its models.")
        discovered := ChatGptPlanAuth.FetchModels()
        catalog := ChatGptModelCatalog.Save(discovered)
        postAssistantsToWebView()
        postWebMessage("chatGptModelsUpdated", { models: catalog })
        try CustomMessages.notifySettingsUpdated(requestParams["mainScriptHiddenHwnd"])
        catch Error as e
            debugLog("[CHATGPT] Could not notify Main of model catalog refresh: " e.Message)
        if postStatus
            _HandleRequestChatGptPlanStatus({ modelCount: discovered.Length, message: "ChatGPT model list refreshed." })
        return catalog
    } catch Error as e {
        if postStatus
            _HandleRequestChatGptPlanStatus({ message: "ChatGPT model refresh failed. " e.Message, error: e.Message })
        throw
    }
}

