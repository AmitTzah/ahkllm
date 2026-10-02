; ======================================================
; ChatGptPlanAuth.ahk — Sign in with ChatGPT for local OSS plan usage
;
; Public-client OAuth/OIDC with dynamic registration, loopback PKCE,
; ID-token validation, DPAPI-protected multi-account credentials, rotating
; refresh tokens, and account-specific model discovery.
; ======================================================

class ChatGptPlanAuth {
    static ISSUER := "https://auth.openai.com"
    static AUTHORIZE_ENDPOINT := "https://auth.openai.com/api/accounts/authorize"
    static TOKEN_ENDPOINT := "https://auth.openai.com/api/accounts/oauth/token"
    static DISCOVERY_ENDPOINT := "https://auth.openai.com/.well-known/openid-configuration"
    static JWKS_ENDPOINT := "https://auth.openai.com/.well-known/jwks.json"
    static RESOURCE := "https://api.openai.com/v1"
    static MODELS_ENDPOINT := "https://api.openai.com/v1/models"
    static DYNAMIC_CLIENT_ID := "dynamic_agent_client"
    static SCOPE := "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static CALLBACK_PATH := "/auth/callback"
    static SIGNIN_TIMEOUT_MS := 600000
    static REFRESH_SKEW_SECONDS := 120
    static _winsockStarted := false
    static _jwks := ""
    static _jwksFetchedAt := 0

    static CredentialsPath() {
        return AppInfo.DataDir "\chatgpt-plan-credentials.dat"
    }

    static HostIdPath() {
        return AppInfo.DataDir "\chatgpt-plan-host-id.txt"
    }

    static Status() {
        if EnvGet("AHKLLM_E2E_WORKER") != "" && EnvGet("AHKLLM_E2E_DATA_DIR") != "" && EnvGet("AHKLLM_E2E_PLAN_AUTH") = "fixture" {
            return { authenticated: true, email: "e2e@example.invalid", clientId: "e2e", accountCount: 1, accounts: [], message: "Signed in with ChatGPT (E2E)." }
        }
        try {
            store := ChatGptPlanAuth._LoadStore()
            active := ChatGptPlanAuth._ActiveAccount(store)
            accounts := []
            if store.Has("accounts") && store["accounts"] is Array {
                for account in store["accounts"] {
                    if !IsObject(account)
                        continue
                    accounts.Push(Map(
                        "clientId", account.Has("client_id") ? account["client_id"] : "",
                        "subject", account.Has("subject") ? account["subject"] : "",
                        "email", account.Has("email") ? account["email"] : "",
                        "authenticated", ChatGptPlanAuth._AccountHasSession(account),
                        "planEnabled", ChatGptPlanAuth._AccountHasSession(account)
                            && ChatGptPlanAuth._HasScope(account, "chatgpt.tokens.use.direct"),
                        "active", IsObject(active) && active.Has("client_id")
                            && account.Has("client_id") && active["client_id"] = account["client_id"]
                    ))
                }
            }
            authenticated := IsObject(active) && ChatGptPlanAuth._AccountHasSession(active)
                && ChatGptPlanAuth._HasScope(active, "chatgpt.tokens.use.direct")
            permissionMissing := IsObject(active) && ChatGptPlanAuth._AccountHasSession(active)
                && !ChatGptPlanAuth._HasScope(active, "chatgpt.tokens.use.direct")
            return {
                authenticated: authenticated,
                permissionMissing: permissionMissing,
                email: IsObject(active) && active.Has("email") ? active["email"] : "",
                clientId: IsObject(active) && active.Has("client_id") ? active["client_id"] : "",
                accountCount: accounts.Length,
                accounts: accounts,
                message: authenticated
                    ? "Signed in with ChatGPT" (active.Has("email") && active["email"] != "" ? " as " active["email"] "." : ".")
                    : (permissionMissing
                        ? "Signed in with ChatGPT, but ChatGPT plan usage is not enabled."
                        : "Not signed in with ChatGPT.")
            }
        } catch Error as e {
            return {
                authenticated: false,
                email: "",
                permissionMissing: false,
                clientId: "",
                accountCount: 0,
                accounts: [],
                message: "ChatGPT sign-in state could not be read.",
                error: e.Message
            }
        }
    }

    static BeginSignIn(newAccount := false, clientId := "") {
        ChatGptPlanAuth._EnsureWinsock()
        hostId := ChatGptPlanAuth._EnsureHostId()
        store := ChatGptPlanAuth._LoadStore()
        selected := ""

        if clientId != ""
            selected := ChatGptPlanAuth._FindAccount(store, clientId)
        else if !newAccount
            selected := ChatGptPlanAuth._ActiveAccount(store)

        initialRegistration := !IsObject(selected) || !selected.Has("client_id") || selected["client_id"] = ""
        requestClientId := initialRegistration ? ChatGptPlanAuth.DYNAMIC_CLIENT_ID : selected["client_id"]

        listener := ChatGptPlanAuth._CreateLoopbackListener()
        stateValue := ChatGptPlanCrypto.RandomBase64Url(32)
        nonce := ChatGptPlanCrypto.RandomBase64Url(32)
        verifier := ChatGptPlanCrypto.RandomBase64Url(48)
        challenge := ChatGptPlanCrypto.Base64UrlEncode(ChatGptPlanCrypto.Sha256Utf8(verifier))
        redirectUri := "http://127.0.0.1:" listener.port ChatGptPlanAuth.CALLBACK_PATH

        pairs := [
            ["client_id", requestClientId],
            ["ext_agent_host_id", hostId],
            ["response_type", "code"],
            ["redirect_uri", redirectUri],
            ["scope", ChatGptPlanAuth.SCOPE],
            ["resource", ChatGptPlanAuth.RESOURCE],
            ["state", stateValue],
            ["nonce", nonce],
            ["code_challenge_method", "S256"],
            ["code_challenge", challenge]
        ]
        if initialRegistration {
            pairs.Push(["agent_name_hint", "AhkLLM"])
        } else {
            if selected.Has("id_token") && selected["id_token"] != ""
                pairs.Push(["id_token_hint", selected["id_token"]])
            if selected.Has("email") && selected["email"] != ""
                pairs.Push(["login_hint", selected["email"]])
            if !ChatGptPlanAuth._HasScope(selected, "chatgpt.tokens.use.direct")
                pairs.Push(["prompt", "consent"])
        }

        query := ""
        for pair in pairs
            query .= (query = "" ? "" : "&") ChatGptPlanCrypto.UrlEncode(pair[1]) "=" ChatGptPlanCrypto.UrlEncode(pair[2])
        authUrl := ChatGptPlanAuth.AUTHORIZE_ENDPOINT "?" query

        pending := {
            listener: listener.socket,
            clientSocket: 0,
            receiveBuffer: "",
            port: listener.port,
            state: stateValue,
            nonce: nonce,
            verifier: verifier,
            redirectUri: redirectUri,
            requestClientId: requestClientId,
            initialRegistration: initialRegistration,
            selectedClientId: initialRegistration ? "" : requestClientId,
            selectedSubject: IsObject(selected) && selected.Has("subject") ? selected["subject"] : "",
            hostId: hostId,
            startedAt: A_TickCount,
            done: false
        }

        try Run(authUrl)
        catch Error as e {
            ChatGptPlanAuth.CancelSignIn(pending)
            throw Error("Could not open the ChatGPT sign-in page: " e.Message)
        }
        return pending
    }

    ; Returns empty string while pending. Completed results have
    ; {done:true, success:true/false, ...}.
    static PollSignIn(pending) {
        if !IsObject(pending) || pending.done
            return { done: true, success: false, error: "The sign-in attempt is no longer active." }

        if A_TickCount - pending.startedAt > ChatGptPlanAuth.SIGNIN_TIMEOUT_MS {
            ChatGptPlanAuth.CancelSignIn(pending)
            return { done: true, success: false, error: "ChatGPT sign-in timed out. Try again." }
        }

        try {
            if !pending.clientSocket {
                client := DllCall("Ws2_32\accept", "Ptr", pending.listener, "Ptr", 0, "Ptr", 0, "Ptr")
                if client = -1 {
                    err := DllCall("Ws2_32\WSAGetLastError", "Int")
                    if err = 10035
                        return ""
                    throw Error("OAuth callback accept failed (Winsock " err ").")
                }
                pending.clientSocket := client
                ChatGptPlanAuth._SetNonBlocking(client)
            }

            buf := Buffer(16384, 0)
            received := DllCall("Ws2_32\recv", "Ptr", pending.clientSocket, "Ptr", buf.Ptr, "Int", buf.Size, "Int", 0, "Int")
            if received = -1 {
                err := DllCall("Ws2_32\WSAGetLastError", "Int")
                if err = 10035
                    return ""
                throw Error("OAuth callback read failed (Winsock " err ").")
            }
            if received = 0
                throw Error("OAuth callback connection closed before a request was received.")

            pending.receiveBuffer .= StrGet(buf, received, "UTF-8")
            delimiter := Chr(13) Chr(10) Chr(13) Chr(10)
            if !InStr(pending.receiveBuffer, delimiter)
                return ""

            lineBreak := Chr(13) Chr(10)
            firstLineEnd := InStr(pending.receiveBuffer, lineBreak)
            requestLine := firstLineEnd ? SubStr(pending.receiveBuffer, 1, firstLineEnd - 1) : pending.receiveBuffer
            if !RegExMatch(requestLine, "^GET\s+([^\s]+)\s+HTTP/", &m)
                throw Error("Unexpected OAuth callback request.")
            target := m[1]
            qpos := InStr(target, "?")
            path := qpos ? SubStr(target, 1, qpos - 1) : target
            if path != ChatGptPlanAuth.CALLBACK_PATH
                throw Error("Unexpected OAuth callback path: " path)
            query := qpos ? SubStr(target, qpos + 1) : ""
            params := ChatGptPlanAuth._ParseQuery(query)

            if !params.Has("state") || params["state"] != pending.state
                throw Error("ChatGPT sign-in state did not match this authorization attempt.")

            if params.Has("error") {
                message := params.Has("error_description") && params["error_description"] != ""
                    ? params["error_description"] : params["error"]
                ChatGptPlanAuth._SendBrowserResponse(pending.clientSocket, false, "Sign-in was not completed. You can close this tab.")
                ChatGptPlanAuth.CancelSignIn(pending)
                return { done: true, success: false, error: message }
            }
            if !params.Has("code") || params["code"] = ""
                throw Error("ChatGPT callback did not contain an authorization code.")

            issuedClientId := pending.requestClientId
            if pending.initialRegistration {
                if !params.Has("client_id") || params["client_id"] = "" || params["client_id"] = ChatGptPlanAuth.DYNAMIC_CLIENT_ID
                    throw Error("ChatGPT registration did not return an issued client ID.")
                issuedClientId := params["client_id"]
            } else if params.Has("client_id") && params["client_id"] != "" && params["client_id"] != pending.selectedClientId {
                throw Error("ChatGPT returned a different client ID than the selected account registration.")
            }

            tokenResponse := ChatGptPlanAuth._TokenRequest(Map(
                "grant_type", "authorization_code",
                "code", params["code"],
                "redirect_uri", pending.redirectUri,
                "client_id", issuedClientId,
                "code_verifier", pending.verifier,
                "resource", ChatGptPlanAuth.RESOURCE
            ))
            if !tokenResponse.Has("id_token") || tokenResponse["id_token"] = ""
                throw Error("ChatGPT token exchange did not return an ID token.")

            claims := ChatGptPlanAuth._ValidateIdToken(tokenResponse["id_token"], issuedClientId, pending.nonce)
            if pending.selectedSubject != "" && claims["sub"] != pending.selectedSubject
                throw Error("The returned ChatGPT identity does not match the selected saved account.")

            account := ChatGptPlanAuth._AccountFromTokenResponse(tokenResponse, claims, issuedClientId, pending.hostId)
            ; A valid identity without plan permission is still a valid saved
            ; ChatGPT account. Keep the registration/session so the user can
            ; re-authorize it later instead of forcing a new dynamic client.
            ChatGptPlanAuth._SaveOrReplaceAccount(account, true)
            hasPlanPermission := ChatGptPlanAuth._HasScope(account, "chatgpt.tokens.use.direct")
            ChatGptPlanAuth._SendBrowserResponse(
                pending.clientSocket,
                hasPlanPermission,
                hasPlanPermission
                    ? "AhkLLM is connected to ChatGPT. You can close this tab."
                    : "ChatGPT sign-in succeeded, but ChatGPT plan usage was not enabled. Return to AhkLLM to enable it or use another provider."
            )
            ChatGptPlanAuth.CancelSignIn(pending)
            status := ChatGptPlanAuth.Status()
            status.done := true
            status.success := hasPlanPermission
            if !hasPlanPermission {
                status.permissionMissing := true
                status.error := "ChatGPT plan usage was not enabled for this account."
            }
            return status
        } catch Error as e {
            try ChatGptPlanAuth._SendBrowserResponse(pending.clientSocket, false, "AhkLLM could not complete ChatGPT sign-in. You can close this tab and return to AhkLLM.")
            ChatGptPlanAuth.CancelSignIn(pending)
            return { done: true, success: false, error: e.Message }
        }
    }

    static CancelSignIn(pending) {
        if !IsObject(pending)
            return
        if pending.HasOwnProp("clientSocket") && pending.clientSocket {
            try DllCall("Ws2_32\closesocket", "Ptr", pending.clientSocket)
            pending.clientSocket := 0
        }
        if pending.HasOwnProp("listener") && pending.listener {
            try DllCall("Ws2_32\closesocket", "Ptr", pending.listener)
            pending.listener := 0
        }
        pending.done := true
    }

    static EnsureAccessToken() {
        if EnvGet("AHKLLM_E2E_WORKER") != "" && EnvGet("AHKLLM_E2E_DATA_DIR") != "" && EnvGet("AHKLLM_E2E_PLAN_AUTH") = "fixture"
            return "fixture"
        return ChatGptPlanAuth._WithCredentialMutex(() => ChatGptPlanAuth._EnsureAccessTokenLocked())
    }

    static _EnsureAccessTokenLocked() {
        store := ChatGptPlanAuth._LoadStore()
        account := ChatGptPlanAuth._ActiveAccount(store)
        if !IsObject(account)
            throw Error("Sign in with ChatGPT in Settings before using a ChatGPT-plan model.")
        if !ChatGptPlanAuth._HasScope(account, "chatgpt.tokens.use.direct")
            throw Error("The selected ChatGPT account has not granted ChatGPT plan usage to AhkLLM.")

        now := ChatGptPlanCrypto.UnixNow()
        expiresAt := account.Has("access_expires_at") ? Integer(account["access_expires_at"]) : 0
        if account.Has("access_token") && account["access_token"] != "" && expiresAt > now + ChatGptPlanAuth.REFRESH_SKEW_SECONDS
            return account["access_token"]

        if !account.Has("refresh_token") || account["refresh_token"] = ""
            throw Error("The ChatGPT session cannot be refreshed. Sign in again.")

        earliest := account.Has("earliest_refresh_at") && IsNumber(account["earliest_refresh_at"])
            ? Integer(account["earliest_refresh_at"]) : 0
        if earliest && now < earliest && account.Has("access_token") && account["access_token"] != "" && expiresAt > now
            return account["access_token"]
        if earliest && now < earliest
            throw Error("ChatGPT has not yet allowed this session to refresh. Try again shortly.")

        response := ChatGptPlanAuth._TokenRequest(Map(
            "grant_type", "refresh_token",
            "client_id", account["client_id"],
            "refresh_token", account["refresh_token"],
            "resource", ChatGptPlanAuth.RESOURCE
        ))
        if !response.Has("access_token") || response["access_token"] = ""
            throw Error("ChatGPT refresh did not return a new access token.")
        if !response.Has("refresh_token") || response["refresh_token"] = ""
            throw Error("ChatGPT refresh did not return the required rotating refresh token.")

        account["access_token"] := response["access_token"]
        account["refresh_token"] := response["refresh_token"]
        if response.Has("id_token") && response["id_token"] != "" {
            refreshedClaims := ChatGptPlanAuth._ValidateIdToken(response["id_token"], account["client_id"])
            if account.Has("subject") && account["subject"] != "" && refreshedClaims["sub"] != account["subject"]
                throw Error("The refreshed ChatGPT identity does not match the saved account.")
            account["id_token"] := response["id_token"]
        }
        account["token_type"] := response.Has("token_type") ? response["token_type"] : "Bearer"
        expiresIn := response.Has("expires_in") ? Integer(response["expires_in"]) : 3600
        account["expires_in"] := expiresIn
        account["saved_at_epoch"] := now
        account["access_expires_at"] := now + expiresIn
        if response.Has("earliest_refresh_at") && IsNumber(response["earliest_refresh_at"])
            account["earliest_refresh_at"] := Integer(response["earliest_refresh_at"])
        if response.Has("scope") && response["scope"] != ""
            account["scopes"] := ChatGptPlanAuth._Scopes(response["scope"])

        ; Refresh tokens rotate. Persist the replacement before reporting a
        ; lost permission, otherwise the previous token may already be invalid
        ; and the saved session becomes unrecoverable.
        ChatGptPlanAuth._SaveStore(store)
        if !ChatGptPlanAuth._HasScope(account, "chatgpt.tokens.use.direct")
            throw Error("The refreshed ChatGPT session no longer grants ChatGPT plan usage.")
        return account["access_token"]
    }

    static FetchModels() {
        token := ChatGptPlanAuth.EnsureAccessToken()
        endpoint := ChatGptPlanAuth.MODELS_ENDPOINT
        if EnvGet("AHKLLM_E2E_WORKER") != "" && EnvGet("AHKLLM_E2E_DATA_DIR") != "" {
            fixtureEndpoint := EnvGet("AHKLLM_E2E_CHATGPT_MODELS_ENDPOINT")
            if RegExMatch(fixtureEndpoint, "i)^http://127\.0\.0\.1:\d+/v1/models$")
                endpoint := fixtureEndpoint
        }
        response := ChatGptPlanAuth._HttpJson("GET", endpoint, "", token)
        if response.status != 200
            throw Error("ChatGPT model list failed with HTTP " response.status ".")
        body := jsongo.Parse(response.body)
        if !IsObject(body) || !body.Has("models") || !(body["models"] is Array)
            throw Error("ChatGPT model list returned an unexpected response.")
        result := []
        for item in body["models"] {
            if !IsObject(item) || !item.Has("slug") || item["slug"] = ""
                continue
            if !item.Has("visibility") || item["visibility"] != "list"
                continue
            result.Push({
                slug: String(item["slug"]),
                displayName: item.Has("display_name") && item["display_name"] != ""
                    ? String(item["display_name"]) : String(item["slug"])
            })
        }
        return result
    }

    static SetActiveAccount(clientId) {
        return ChatGptPlanAuth._WithCredentialMutex(() => ChatGptPlanAuth._SetActiveAccountLocked(clientId))
    }

    static _SetActiveAccountLocked(clientId) {
        store := ChatGptPlanAuth._LoadStore()
        account := ChatGptPlanAuth._FindAccount(store, clientId)
        if !IsObject(account)
            return false
        store["active_client_id"] := clientId
        ChatGptPlanAuth._SaveStore(store)
        return true
    }

    static SignOut(clientId := "") {
        return ChatGptPlanAuth._WithCredentialMutex(() => ChatGptPlanAuth._SignOutLocked(clientId))
    }

    static _SignOutLocked(clientId := "") {
        store := ChatGptPlanAuth._LoadStore()
        account := clientId != "" ? ChatGptPlanAuth._FindAccount(store, clientId) : ChatGptPlanAuth._ActiveAccount(store)
        if !IsObject(account)
            return { success: true, remoteRevoked: true }

        revoked := true
        if account.Has("refresh_token") && account["refresh_token"] != "" {
            revoked := false
            try {
                discovery := ChatGptPlanAuth._HttpJson("GET", ChatGptPlanAuth.DISCOVERY_ENDPOINT)
                if discovery.status = 200 {
                    meta := jsongo.Parse(discovery.body)
                    if IsObject(meta) && meta.Has("revocation_endpoint") && meta["revocation_endpoint"] != "" {
                        body := ChatGptPlanAuth._FormEncode(Map(
                            "token", account["refresh_token"],
                            "token_type_hint", "refresh_token",
                            "client_id", account["client_id"]
                        ))
                        http := ComObject("WinHttp.WinHttpRequest.5.1")
                        http.SetTimeouts(5000, 5000, 10000, 10000)
                        http.Open("POST", meta["revocation_endpoint"], false)
                        http.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded")
                        http.SetRequestHeader("Accept", "application/json")
                        http.Send(body)
                        revoked := http.Status = 200
                    }
                }
            } catch
                revoked := false
        }

        for key in ["access_token", "refresh_token", "id_token", "access_expires_at", "earliest_refresh_at", "expires_in", "saved_at_epoch"] {
            if account.Has(key)
                account.Delete(key)
        }
        ChatGptPlanAuth._SaveStore(store)
        return { success: true, remoteRevoked: revoked }
    }

    static _AccountFromTokenResponse(tokens, claims, clientId, hostId) {
        now := ChatGptPlanCrypto.UnixNow()
        expiresIn := tokens.Has("expires_in") ? Integer(tokens["expires_in"]) : 3600
        account := Map(
            "email", claims.Has("email") ? claims["email"] : "",
            "issuer", claims.Has("iss") ? claims["iss"] : ChatGptPlanAuth.ISSUER,
            "subject", claims["sub"],
            "client_id", clientId,
            "ext_agent_host_id", hostId,
            "id_token", tokens["id_token"],
            "access_token", tokens.Has("access_token") ? tokens["access_token"] : "",
            "refresh_token", tokens.Has("refresh_token") ? tokens["refresh_token"] : "",
            "token_type", tokens.Has("token_type") ? tokens["token_type"] : "Bearer",
            "expires_in", expiresIn,
            "saved_at_epoch", now,
            "access_expires_at", now + expiresIn,
            "scopes", ChatGptPlanAuth._Scopes(tokens.Has("scope") ? tokens["scope"] : "")
        )
        if tokens.Has("earliest_refresh_at") && IsNumber(tokens["earliest_refresh_at"])
            account["earliest_refresh_at"] := Integer(tokens["earliest_refresh_at"])
        return account
    }

    static _AccountHasSession(account) {
        return IsObject(account)
            && account.Has("access_token") && account["access_token"] != ""
            && account.Has("refresh_token") && account["refresh_token"] != ""
    }

    static _SaveOrReplaceAccount(account, makeActive := true) {
        return ChatGptPlanAuth._WithCredentialMutex(() => ChatGptPlanAuth._SaveOrReplaceAccountLocked(account, makeActive))
    }

    static _SaveOrReplaceAccountLocked(account, makeActive) {
        store := ChatGptPlanAuth._LoadStore()
        if !store.Has("accounts") || !(store["accounts"] is Array)
            store["accounts"] := []
        replaced := false
        for i, existing in store["accounts"] {
            if IsObject(existing) && existing.Has("client_id") && existing["client_id"] = account["client_id"] {
                store["accounts"][i] := account
                replaced := true
                break
            }
        }
        if !replaced
            store["accounts"].Push(account)
        if makeActive
            store["active_client_id"] := account["client_id"]
        ChatGptPlanAuth._SaveStore(store)
        return true
    }

    static _ActiveAccount(store) {
        if !IsObject(store) || !store.Has("accounts") || !(store["accounts"] is Array)
            return ""
        activeId := store.Has("active_client_id") ? store["active_client_id"] : ""
        if activeId != "" {
            found := ChatGptPlanAuth._FindAccount(store, activeId)
            if IsObject(found)
                return found
        }
        return store["accounts"].Length ? store["accounts"][1] : ""
    }

    static _FindAccount(store, clientId) {
        if !IsObject(store) || !store.Has("accounts") || !(store["accounts"] is Array)
            return ""
        for account in store["accounts"] {
            if IsObject(account) && account.Has("client_id") && account["client_id"] = clientId
                return account
        }
        return ""
    }

    static _HasScope(account, scope) {
        if !IsObject(account) || !account.Has("scopes") || !(account["scopes"] is Array)
            return false
        for value in account["scopes"]
            if value = scope
                return true
        return false
    }

    static _Scopes(raw) {
        out := []
        for value in StrSplit(Trim(String(raw)), " ") {
            value := Trim(value)
            if value != ""
                out.Push(value)
        }
        return out
    }

    static _TokenRequest(fields) {
        ChatGptPlanAuth._ValidateTokenRequest(fields)
        response := ChatGptPlanAuth._HttpJson(
            "POST",
            ChatGptPlanAuth.TOKEN_ENDPOINT,
            ChatGptPlanAuth._FormEncode(fields),
            "",
            "application/x-www-form-urlencoded"
        )
        if response.status != 200 {
            message := "ChatGPT token request failed with HTTP " response.status "."
            try {
                parsed := jsongo.Parse(response.body)
                message := ChatGptPlanAuth._TokenErrorMessage(response.status, parsed)
            }
            throw Error(message)
        }
        parsed := jsongo.Parse(response.body)
        if !IsObject(parsed)
            throw Error("ChatGPT token endpoint returned invalid JSON.")
        return parsed
    }

    static _ValidateTokenRequest(fields) {
        required := ["grant_type", "client_id", "resource"]
        if fields.Get("grant_type", "") = "authorization_code"
            required.Push("code", "code_verifier", "redirect_uri")
        else if fields.Get("grant_type", "") = "refresh_token"
            required.Push("refresh_token")
        for field in required {
            if !fields.Has(field) || Trim(String(fields[field])) = ""
                throw Error("ChatGPT token request is missing parameter: " field ".")
        }
    }

    static _TokenErrorMessage(status, response) {
        message := "ChatGPT token exchange failed (HTTP " status
        if !(response is Map)
            return message ")."
        errorDetails := response.Has("error") && response["error"] is Map ? response["error"] : response
        code := errorDetails.Get("code", response.Get("error", ""))
        ; Report protocol metadata only; never include request or token values.
        if !IsObject(code) && RegExMatch(String(code), "^(invalid_request|invalid_grant|invalid_client|unauthorized_client|unsupported_grant_type|invalid_scope|access_denied|temporarily_unavailable|server_error)$")
            message .= "; " code
        parameter := errorDetails.Get("param", errorDetails.Get("parameter", ""))
        if !IsObject(parameter) && RegExMatch(String(parameter), "^(grant_type|client_id|code|code_verifier|redirect_uri|resource|refresh_token|scope|ext_agent_host_id)$")
            message .= "; parameter: " parameter
        description := response.Get("error_description", errorDetails.Get("message", ""))
        return message ")." (description != "" && !IsObject(description) ? " " description : "")
    }

    static _HttpJson(method, url, body := "", bearer := "", contentType := "") {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(10000, 10000, 30000, 30000)
        http.Open(method, url, false)
        http.SetRequestHeader("Accept", "application/json")
        if bearer != ""
            http.SetRequestHeader("Authorization", "Bearer " bearer)
        if contentType != ""
            http.SetRequestHeader("Content-Type", contentType)
        http.Send(body)
        return { status: http.Status, body: http.ResponseText }
    }

    static _ValidateIdToken(idToken, clientId, expectedNonce := "") {
        parts := StrSplit(idToken, ".")
        if parts.Length != 3
            throw Error("ChatGPT ID token is not a valid JWT.")

        header := jsongo.Parse(ChatGptPlanCrypto.Utf8FromBuffer(ChatGptPlanCrypto.Base64UrlDecode(parts[1])))
        payload := jsongo.Parse(ChatGptPlanCrypto.Utf8FromBuffer(ChatGptPlanCrypto.Base64UrlDecode(parts[2])))
        if !IsObject(header) || !IsObject(payload)
            throw Error("ChatGPT ID token contains invalid JSON.")
        if !header.Has("alg") || header["alg"] != "RS256"
            throw Error("ChatGPT ID token uses an unsupported signing algorithm.")
        if !header.Has("kid") || header["kid"] = ""
            throw Error("ChatGPT ID token did not identify a signing key.")

        key := ChatGptPlanAuth._JwkForKid(header["kid"])
        signature := ChatGptPlanCrypto.Base64UrlDecode(parts[3])
        if !ChatGptPlanCrypto.VerifyRs256(parts[1] "." parts[2], signature, key)
            throw Error("ChatGPT ID token signature validation failed.")

        now := ChatGptPlanCrypto.UnixNow()
        if !payload.Has("iss") || payload["iss"] != ChatGptPlanAuth.ISSUER
            throw Error("ChatGPT ID token issuer is invalid.")
        if !payload.Has("aud") || !ChatGptPlanAuth._AudienceContains(payload["aud"], clientId)
            throw Error("ChatGPT ID token audience does not match the issued client ID.")
        if !payload.Has("exp") || Integer(payload["exp"]) + 5 < now
            throw Error("ChatGPT ID token has expired.")
        if !payload.Has("iat")
            throw Error("ChatGPT ID token is missing its issued-at claim.")
        if Integer(payload["iat"]) > now + 300
            throw Error("ChatGPT ID token issued-at time is invalid.")
        if expectedNonce != "" && (!payload.Has("nonce") || payload["nonce"] != expectedNonce)
            throw Error("ChatGPT ID token nonce did not match this sign-in attempt.")
        if !payload.Has("sub") || payload["sub"] = ""
            throw Error("ChatGPT ID token did not contain an account subject.")
        return payload
    }

    static _AudienceContains(aud, clientId) {
        if !IsObject(aud)
            return String(aud) = clientId
        if aud is Array {
            for value in aud
                if String(value) = clientId
                    return true
        }
        return false
    }

    static _JwkForKid(kid) {
        now := ChatGptPlanCrypto.UnixNow()
        if !IsObject(ChatGptPlanAuth._jwks) || now - ChatGptPlanAuth._jwksFetchedAt > 600
            ChatGptPlanAuth._RefreshJwks()
        key := ChatGptPlanAuth._FindJwk(ChatGptPlanAuth._jwks, kid)
        if IsObject(key)
            return key

        ChatGptPlanAuth._RefreshJwks()
        key := ChatGptPlanAuth._FindJwk(ChatGptPlanAuth._jwks, kid)
        if !IsObject(key)
            throw Error("ChatGPT ID token signing key was not found in OpenAI's JWKS.")
        return key
    }

    static _RefreshJwks() {
        response := ChatGptPlanAuth._HttpJson("GET", ChatGptPlanAuth.JWKS_ENDPOINT)
        if response.status != 200
            throw Error("Could not load OpenAI signing keys (HTTP " response.status ").")
        parsed := jsongo.Parse(response.body)
        if !IsObject(parsed) || !parsed.Has("keys") || !(parsed["keys"] is Array)
            throw Error("OpenAI JWKS response is invalid.")
        ChatGptPlanAuth._jwks := parsed
        ChatGptPlanAuth._jwksFetchedAt := ChatGptPlanCrypto.UnixNow()
    }

    static _FindJwk(jwks, kid) {
        if !IsObject(jwks) || !jwks.Has("keys")
            return ""
        for key in jwks["keys"] {
            if IsObject(key) && key.Has("kid") && key["kid"] = kid
                return key
        }
        return ""
    }

    static _EnsureHostId() {
        path := ChatGptPlanAuth.HostIdPath()
        if FileExist(path) {
            value := Trim(FileRead(path, "UTF-8"))
            if RegExMatch(value, "^urn:uuid:[0-9a-fA-F-]{36}$")
                return value
        }
        dir := SubStr(path, 1, InStr(path, "\", , -1) - 1)
        if !DirExist(dir)
            DirCreate(dir)
        value := "urn:uuid:" ChatGptPlanCrypto.UuidV4()
        temp := path ".tmp"
        FileOpen(temp, "w", "UTF-8-RAW").Write(value)
        FileMove(temp, path, 1)
        return value
    }

    static _ParseQuery(query) {
        params := Map()
        for part in StrSplit(query, "&") {
            if part = ""
                continue
            eq := InStr(part, "=")
            key := ChatGptPlanCrypto.UrlDecode(eq ? SubStr(part, 1, eq - 1) : part)
            value := ChatGptPlanCrypto.UrlDecode(eq ? SubStr(part, eq + 1) : "")
            params[key] := value
        }
        return params
    }

    static _FormEncode(fields) {
        out := ""
        for key, value in fields
            out .= (out = "" ? "" : "&") ChatGptPlanCrypto.UrlEncode(key) "=" ChatGptPlanCrypto.UrlEncode(value)
        return out
    }

    static _CreateLoopbackListener() {
        sock := DllCall("Ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
        if sock = -1
            throw Error("Could not create the ChatGPT OAuth callback socket.")
        try {
            addr := Buffer(16, 0)
            NumPut("UShort", 2, addr, 0)
            NumPut("UShort", DllCall("Ws2_32\htons", "UShort", 0, "UShort"), addr, 2)
            NumPut("UInt", DllCall("Ws2_32\inet_addr", "AStr", "127.0.0.1", "UInt"), addr, 4)
            if DllCall("Ws2_32\bind", "Ptr", sock, "Ptr", addr.Ptr, "Int", addr.Size, "Int") != 0
                throw Error("Could not bind the ChatGPT OAuth callback to 127.0.0.1.")
            if DllCall("Ws2_32\listen", "Ptr", sock, "Int", 1, "Int") != 0
                throw Error("Could not listen for the ChatGPT OAuth callback.")

            len := addr.Size
            if DllCall("Ws2_32\getsockname", "Ptr", sock, "Ptr", addr.Ptr, "Int*", &len, "Int") != 0
                throw Error("Could not determine the ChatGPT OAuth callback port.")
            port := DllCall("Ws2_32\ntohs", "UShort", NumGet(addr, 2, "UShort"), "UShort")
            ChatGptPlanAuth._SetNonBlocking(sock)
            return { socket: sock, port: port }
        } catch {
            DllCall("Ws2_32\closesocket", "Ptr", sock)
            throw
        }
    }

    static _SetNonBlocking(sock) {
        mode := 1
        if DllCall("Ws2_32\ioctlsocket", "Ptr", sock, "UInt", 0x8004667E, "UInt*", &mode, "Int") != 0
            throw Error("Could not configure the OAuth callback socket.")
    }

    static _EnsureWinsock() {
        if ChatGptPlanAuth._winsockStarted
            return
        data := Buffer(512, 0)
        result := DllCall("Ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", data.Ptr, "Int")
        if result != 0
            throw Error("Winsock initialization failed: " result)
        ChatGptPlanAuth._winsockStarted := true
    }

    static _SendBrowserResponse(sock, success, message) {
        if !sock
            return
        title := success ? "Connected" : "Sign-in incomplete"
        safeMessage := StrReplace(StrReplace(StrReplace(String(message), "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
        quote := Chr(34)
        html := "<!doctype html><html><head><meta charset=" quote "utf-8" quote "><title>" title "</title></head>"
            . "<body style=" quote "font-family:Segoe UI,Arial,sans-serif;padding:32px" quote "><h2>" title "</h2><p>" safeMessage "</p></body></html>"
        body := ChatGptPlanCrypto.Utf8Buffer(html)
        crlf := Chr(13) Chr(10)
        headers := "HTTP/1.1 200 OK" crlf
            . "Content-Type: text/html; charset=utf-8" crlf
            . "Content-Length: " body.Size crlf
            . "Connection: close" crlf
            . "Cache-Control: no-store" crlf crlf
        head := ChatGptPlanCrypto.Utf8Buffer(headers)
        try DllCall("Ws2_32\send", "Ptr", sock, "Ptr", head.Ptr, "Int", head.Size, "Int", 0, "Int")
        if body.Size
            try DllCall("Ws2_32\send", "Ptr", sock, "Ptr", body.Ptr, "Int", body.Size, "Int", 0, "Int")
    }

    static _LoadStore() {
        path := ChatGptPlanAuth.CredentialsPath()
        if !FileExist(path)
            return Map("active_client_id", "", "accounts", [])
        credentialFile := FileOpen(path, "r")
        if !credentialFile
            throw Error("Could not open the ChatGPT credential store.")
        bytes := Buffer(credentialFile.Length, 0)
        if bytes.Size
            credentialFile.RawRead(bytes, bytes.Size)
        credentialFile.Close()
        plain := ChatGptPlanCrypto.UnprotectText(bytes)
        parsed := jsongo.Parse(plain)
        if !IsObject(parsed)
            throw Error("ChatGPT credential store is invalid.")
        store := SettingsPersistence._ToMap(parsed)
        if !store.Has("accounts") || !(store["accounts"] is Array)
            store["accounts"] := []
        if !store.Has("active_client_id")
            store["active_client_id"] := ""
        return store
    }

    static _SaveStore(store) {
        path := ChatGptPlanAuth.CredentialsPath()
        dir := SubStr(path, 1, InStr(path, "\", , -1) - 1)
        if !DirExist(dir)
            DirCreate(dir)
        protected := ChatGptPlanCrypto.ProtectText(jsongo.Stringify(store))
        temp := path ".tmp"
        credentialFile := FileOpen(temp, "w")
        credentialFile.RawWrite(protected, protected.Size)
        credentialFile.Close()
        FileMove(temp, path, 1)
    }

    static _WithCredentialMutex(callback) {
        mutex := DllCall("CreateMutexW", "Ptr", 0, "Int", false, "WStr", "Local\AhkLLM_ChatGptPlanAuth", "Ptr")
        if !mutex
            throw OSError(A_LastError, "Could not create ChatGPT credential mutex")
        try {
            wait := DllCall("WaitForSingleObject", "Ptr", mutex, "UInt", 15000, "UInt")
            if wait != 0 && wait != 0x80
                throw Error("Timed out waiting for the ChatGPT credential store.")
            try return callback.Call()
            finally DllCall("ReleaseMutex", "Ptr", mutex)
        } finally {
            DllCall("CloseHandle", "Ptr", mutex)
        }
    }
}
