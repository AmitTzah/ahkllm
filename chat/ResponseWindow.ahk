#Include ..\lib\Config.ahk
#SingleInstance Off
#NoTrayIcon

; ----------------------------------------------------
; Hotkeys
; ----------------------------------------------------

~Esc:: subScriptHotkeyActions("Esc")
~^w:: subScriptHotkeyActions("closeWindows")

subScriptHotkeyActions(action) {
    switch action {

        ; Handles request cancellation based on Response Window state:
        ;
        ; Background window: Stop request, keep window open
        ; Active window: Stop request, keep window open
        ; Hidden window: Stop request only
        case "Esc":
            switch {
                case WinExist(responseWindow.hWnd) && !(WinActive(responseWindow.hWnd))
                && ProcessExist(manageState("cURL", "get")):
                    manageState("cURL", "close")
                    postWebMessage("setChatButtonsEnabled", true)

                case WinActive(responseWindow.hWnd):
                    switch {
                        case ProcessExist(manageState("cURL", "get")):
                            manageState("cURL", "close")
                            postWebMessage("setChatButtonsEnabled", true)

                        Default:
                            buttonClickAction("Close")
                    }

                case ProcessExist(manageState("cURL", "get")):
                    manageState("cURL", "close")
            }

        case "closeWindows":
            switch WinActive("A") {
                case responseWindow.hWnd: buttonClickAction("Close")
            }
    }
}

; ----------------------------------------------------
; Read data from main script and start loading cursor
; ----------------------------------------------------

requestParams := jsongo.Parse(FileOpen(A_Args[1], "r", "UTF-8").Read())
startLoadingCursor(true)

; ----------------------------------------------------
; Change icon based on providerName
; ----------------------------------------------------

TraySetIcon(FileExist(icon := "..\icons\" requestParams["providerName"] ".ico") ? icon : "..\icons\IconOn.ico")

; ----------------------------------------------------
; Create new instance of LLMClient class
; ----------------------------------------------------

router := LLMClient(APIKey)

; ----------------------------------------------------
; Create Response Window
; ----------------------------------------------------

; Create the Webview Window
responseWindow := WebViewToo(, , ,)
responseWindow.OnEvent("Close", (*) => buttonClickAction("Close"))
responseWindow.Load("..\webui\index.html")

; Apply dark mode to title bar
; Reference: https://www.autohotkey.com/boards/viewtopic.php?p=422034#p422034
if (darkMode) {
    DllCall("Dwmapi\DwmSetWindowAttribute", "ptr", responseWindow.hWnd, "int", 20, "int*", true, "int", 4)
}

; ----------------------------------------------------
; Include chat module files
; ----------------------------------------------------

#Include ChatUtils.ahk
#Include ChatCallbacks.ahk
#Include StreamHandler.ahk

; Assign actions to click events
responseWindow.AddHostObjectToScript("ButtonClick", { func: buttonClickAction })
responseWindow.AddHostObjectToScript("ChatSend", { func: chatSendFromWebView })
responseWindow.AddHostObjectToScript("RetryAction", { func: retryFromWebView })

; ----------------------------------------------------
; Show the Response Window with the response content
; ----------------------------------------------------

showResponseWindow(responseWindowTextContent, initialRequest, noActivate := false) {
    postWebMessage("setTheme", [darkMode])
    postWebMessage("setFontFace", [responseWindowFontFace])

    ; For chat mode, the structured message array is already sent by sendRequestToLLM.
    ; For non-chat mode (FIM fallback), render markdown in the content area.
    if requestParams["pasteMode"] != "chat" {
        postWebMessage("renderMarkdown", [responseWindowTextContent])
    }

    if initialRequest {

        ; Response Window's width and height
        desiredW := 600
        desiredH := 600

        ; Calculate screen center
        screenW := A_ScreenWidth
        screenH := A_ScreenHeight

        ; Define an X and Y coordinate variables
        X := (screenW - desiredW) // 2
        Y := (screenH - desiredH) // 4

        ; Compute the arrangement of Response Windows based on the number of models
        switch requestParams["numberOfAPIModels"] {
            case 1:
                pos := Format("x{} y{} w{} h{}", X - 100, Y, desiredW, desiredH)

            case 2:
                X := (requestParams["APIModelsIndex"] = 1) ? (screenW // 2) - (desiredW * 1.3) : (screenW // 2)
                pos := Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH)

            case 3:
                switch requestParams["APIModelsIndex"] {
                    case 1: X := (screenW // 2) - (desiredW * 1.6)
                    case 2: X := (screenW - desiredW) // 2
                    default: X := (screenW // 2) + (desiredW * 0.4)
                }
                pos := Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH)

            default:
                if (requestParams["APIModelsIndex"] < 4) {
                    switch requestParams["APIModelsIndex"] {
                        case 1: X := (screenW // 2) - (desiredW * 1.6)
                        case 2: X := (screenW - desiredW) // 2
                        case 3: X := (screenW // 2) + (desiredW * 0.4)
                    }
                } else {
                    X := (screenW - desiredW) // 2
                    Y := Y + (requestParams["APIModelsIndex"] - 3) * 30
                }
                pos := Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH)
        }

        responseWindow.Show(pos, requestParams["responseWindowTitle"])
    }

    ; Flash the Response Window if it is minimized or not active
    (WinGetMinMax(responseWindow.hWnd) = -1) || noActivate ? responseWindow.Flash() : ""
}

; ----------------------------------------------------
; Custom messages for detecting Response Windows
; and their open/close state, as well as detecting
; the "Send message to all models" feature
; ----------------------------------------------------

CustomMessages.registerHandlers("subScript", responseWindowSendToAllModels)
CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_OPENED, requestParams["uniqueID"],
    responseWindow.hWnd, requestParams["mainScriptHiddenhWnd"])

responseWindowSendToAllModels(uniqueID, lParam, msg, responseWindowhWnd) {
    if (ProcessExist(manageState("cURL", "get"))) {
        manageState("cURL", "close")
    }

    ; Re-read the updated JSON file and call sendRequestToLLM() again
    chatHistoryJSONRequest := FileOpen(requestParams["chatHistoryJSONRequestFile"], "r", "UTF-8-RAW").Read()
    startLoadingCursor(true)
    manageChatHistoryJSON("set", chatHistoryJSONRequest)
    postWebMessage("setChatButtonsEnabled", false)
    sendRequestToLLM(&chatHistoryJSONRequest)
}

; ----------------------------------------------------
; Run cURL command and process response
; ----------------------------------------------------

chatHistoryJSONRequest := manageChatHistoryJSON("get")

; Show the window immediately for chat mode before cURL runs
; (replace/append modes paste and close immediately, no need to show a window)
if requestParams["pasteMode"] = "chat" {
    ; Wait for WebView to finish loading before posting messages
    Sleep 500
    structuredMessages := buildStructuredMessages(chatHistoryJSONRequest)
    postWebMessage("initChatMode", structuredMessages)
    showResponseWindow("", true)
}

sendRequestToLLM(&chatHistoryJSONRequest, true)

sendRequestToLLM(&chatHistoryJSONRequest, initialRequest := false) {
    debugLog("sendRequestToLLM entered. stream=" requestParams["stream"] " initialRequest=" initialRequest)

    ; For streaming requests, delegate to StreamHandler
    if requestParams["stream"] {
        debugLog("Delegating to sendStreamingRequest")
        sendStreamingRequest(&chatHistoryJSONRequest, initialRequest)
        return
    }

    ; Record start time for latency tracking
    requestStartTime := A_TickCount

    ; Run the non-streaming cURL command asynchronously
    cURLCommand := FileOpen(requestParams["cURLCommandFile"], "r", "UTF-8").Read()
    debugLog("cURL command file: " requestParams["cURLCommandFile"])
    debugLog("cURL command length: " StrLen(cURLCommand))
    debugLog("Running cURL command...")
    Run(cURLCommand, , "Hide", &cURLPID)
    manageState("cURL", "set", cURLPID)
    debugLog("cURL PID: " cURLPID)

    ; Waits for the process to complete or be aborted
    while (ProcessExist(cURLPID)) {
        Sleep 250
    }
    debugLog("cURL while loop exited. ProcessExist=" ProcessExist(cURLPID) " manageState(cURL,get)=" manageState("cURL", "get"))

    ; If user cancels the process, exit
    if !manageState("cURL", "get") {
        manageState("cURL", "close")
        startLoadingCursor(false)
        if initialRequest {
            deleteTempFiles()
            CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_CLOSED,
                requestParams["uniqueID"], responseWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
            ExitApp
        }
        Exit
    }

    ; Reset the PID as the process has completed
    cURLPID := 0
    manageState("cURL", "set", cURLPID)
    debugLog("cURL PID reset to 0, manageState(cURL,get)=" manageState("cURL", "get"))

    ; Read the output after the process has completed
    if !FileExist(requestParams["cURLOutputFile"]) {
        debugLog("ERROR: Output file NOT FOUND: " requestParams["cURLOutputFile"])
        responseFromLLM := "**⛔ Error: No response received**`n`nThe API did not return any output. This may indicate a network error, timeout, or invalid request. Check the API Logs viewer (Options → API Logs) for details."
        showResponseWindow(responseFromLLM, initialRequest)
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        Exit
    }
    JSONResponseFromLLM := FileOpen(requestParams["cURLOutputFile"], "r", "UTF-8").Read()
    debugLog("Output file read successfully. Length=" StrLen(JSONResponseFromLLM))

    ; Process the JSON response from the LLM API
    try {
        JSONResponseVar := jsongo.Parse(JSONResponseFromLLM)

        ; Use FIM or chat extraction based on request params
        if requestParams["isFIM"] {
            responseFromLLM := router.extractFIMResponse(JSONResponseVar)
        } else {
            responseFromLLM := router.extractJSONResponse(JSONResponseVar)
        }

        ; Get text after forward slash as responseFromLLM.model and replace colon (:) with dash (-)
        responseFromLLM.model := StrReplace(SubStr(responseFromLLM.model, InStr(responseFromLLM.model, "/") + 1), ":",
        "-")

        manageState("model", "add", responseFromLLM.model)

        ; Post token usage to WebView (non-streaming)
        if responseFromLLM.HasProp("usage") && responseFromLLM.usage.totalTokens > 0 {
            costs := LLMClient.ComputeTokenCosts(responseFromLLM.model, responseFromLLM.usage)
            tokenUsage := {
                promptTokens:     responseFromLLM.usage.promptTokens,
                completionTokens: responseFromLLM.usage.completionTokens,
                totalTokens:      responseFromLLM.usage.totalTokens,
                cachedTokens:     responseFromLLM.usage.HasProp("cachedTokens") ? responseFromLLM.usage.cachedTokens : 0,
                contextWindow:    costs.contextWindow,
                inputCost:        costs.inputCost,
                outputCost:       costs.outputCost,
                totalCost:        costs.totalCost
            }
            postWebMessage("updateTokenUsage", tokenUsage)
        }
        ; Snapshot the request BEFORE appending the response, so the log
        ; shows the actual request sent (not the request + response combined)
        requestBeforeAppend := chatHistoryJSONRequest
        if !requestParams["isFIM"] {
            ; Only append to chat history for chat completions (FIM has no chat history)
            router.appendToChatHistory("assistant",
                responseFromLLM.response, &chatHistoryJSONRequest, requestParams["chatHistoryJSONRequestFile"])
        }

        ; Calculate latency in milliseconds
        latencyMs := A_TickCount - requestStartTime

        ; Log the successful API interaction
        LLMClient.LogRequest({
            timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
            promptName: requestParams["responseWindowTitle"],
            provider: requestParams["providerName"],
            model: requestParams["singleAPIModelName"],
            isFIM: requestParams["isFIM"],
            endpoint: requestParams["isFIM"] ? FIMEndpoint : APIEndpoint,
            pasteMode: requestParams["pasteMode"],
            request: requestBeforeAppend,
            response: JSONResponseFromLLM,
            status: "success",
            latencyMs: latencyMs
        })
    } catch as e {
        ; Calculate latency in milliseconds
        latencyMs := A_TickCount - requestStartTime

        ; Log the failed API interaction
        LLMClient.LogRequest({
            timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
            promptName: requestParams["responseWindowTitle"],
            provider: requestParams["providerName"],
            model: requestParams["singleAPIModelName"],
            isFIM: requestParams["isFIM"],
            endpoint: requestParams["isFIM"] ? FIMEndpoint : APIEndpoint,
            pasteMode: requestParams["pasteMode"],
            request: chatHistoryJSONRequest,
            response: JSONResponseFromLLM,
            status: "error",
            latencyMs: latencyMs
        })
        JSONResponseFromLLM := router.extractErrorResponse(JSONResponseVar)
        responseFromLLM :=
            "**⛔ Error parsing response**`n`n" e.Message
            . "`n`n---`n`n**⚠️ Response from the API**`n`n"
            . JSONResponseFromLLM.error
            . "`n`n---`n`n"
        errorCodes := {
            400: "You may have specified an invalid API model. See [this guide](https://github.com/kdalanon/LLM-AutoHotkey-Assistant/blob/main/README.md#apimodels) on how to get the correct API models.",
            401: "Authentication failed. Your API key or session might be invalid or expired. Check your keys [here](https://openrouter.ai/settings/keys), re-add it to the app, and try again.",
            402: "Insufficient funds. Click [here](https://openrouter.ai/credits) to check your available credits.",
            403: "Content flagged as inappropriate. Your input triggered content moderation and was rejected. Please revise your request and try again with different content.",
            408: "Request timed out. The API request took too long to process. This might be due to network issues or server overload.",
            429: "You've hit the rate limit of **" requestParams["singleAPIModelName"] "**. Try again after some time.",
            502: "Service temporarily unavailable. The chosen model is either down or returned an invalid response. Please try again later or select a different model.",
            503: "No suitable model available. There are no providers currently meeting your request requirements. Please try again later or adjust your routing settings."
        }

        ; Only append an error code explanation for known numeric codes
        try {
            errorCodeValue := errorCodes.%JSONResponseFromLLM.code%
            if errorCodeValue != "" {
                responseFromLLM .= errorCodeValue
            }
        }

        if requestParams["pasteMode"] = "chat" {
            ; In chat mode, append the error as an assistant message
            postWebMessage("appendChatMessage", { role: "assistant", content: responseFromLLM, model: "Error" })
            showResponseWindow("", initialRequest)
        } else {
            showResponseWindow(responseFromLLM, initialRequest)
        }
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        Exit
    }

    ; Save updated chat history JSON
    if !requestParams["isFIM"] {
        manageChatHistoryJSON("set", chatHistoryJSONRequest)

        if requestParams["pasteMode"] = "chat" {
            ; --- Chat mode: Send structured message arrays to the WebView ---
            structuredMessages := buildStructuredMessages(chatHistoryJSONRequest)

            if initialRequest {
                ; On initial request, initialize the full chat
                postWebMessage("initChatMode", structuredMessages)
            } else {
                ; On subsequent requests, send just the new assistant message
                lastMsg := structuredMessages[structuredMessages.Length]
                postWebMessage("appendChatMessage", lastMsg)
            }
        }
    }

    if requestParams["pasteMode"] = "replace" || requestParams["pasteMode"] = "append" {
        A_Clipboard := responseFromLLM.response
        if requestParams["pasteMode"] = "append" {
            Send("{Right}")       ; Move cursor past the selection before pasting
        }
        Send("^v")
        Sleep 50
        ; Move cursor slightly within pasted text to force scroll-to-cursor
        Send("{Left}{Right}")
        startLoadingCursor(false)
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_CLOSED, requestParams["uniqueID"],
            responseWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
        deleteTempFiles()
        ExitApp
    } else {
        ; For chat mode or default display mode
        if requestParams["pasteMode"] != "chat" {
            ; Non-chat mode: show the response in the content area
            showResponseWindow(responseFromLLM.response, initialRequest, !initialRequest && !(WinActive(responseWindow.hWnd
            )))
        } else {
            ; Chat mode: ensure the window is shown/flashed
            if initialRequest {
                showResponseWindow("", initialRequest)
            } else {
                responseWindow.Flash()
            }
        }
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
    }
}