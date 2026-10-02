; ======================================================
; ChatGptPlanAuth.test.ahk — pure/account-flow contract tests
; No browser, network, or real account credentials.
; ======================================================

class ChatGptPlanAuthTest {
    static __New() {
        RegisterTestClass("ChatGptPlanAuthTest")
    }

    TokenRequest_MissingFieldsAreIdentifiedBeforeSending() {
        fields := Map("grant_type", "authorization_code", "client_id", "fixture-client", "resource", ChatGptPlanAuth.RESOURCE,
            "code", "fixture-code", "code_verifier", "fixture-verifier", "redirect_uri", "http://127.0.0.1:1455/auth/callback")
        ChatGptPlanAuth._ValidateTokenRequest(fields)
        fields.Delete("code_verifier")
        message := ""
        try ChatGptPlanAuth._ValidateTokenRequest(fields)
        catch Error as e
            message := e.Message
        if !InStr(message, "code_verifier") || InStr(message, "fixture-code")
            throw Error("Missing token fields must be named without exposing their values")
    }

    TokenErrors_PreserveHttpCodeAndParameterAlongsideDescription() {
        message := ChatGptPlanAuth._TokenErrorMessage(400, Map("error", "invalid_request", "error_description", "Missing a required parameter.", "param", "resource"))
        for expected in ["HTTP 400", "invalid_request", "parameter: resource", "Missing a required parameter."] {
            if !InStr(message, expected)
                throw Error("Token error dropped diagnostic detail: " expected)
        }
        message := ChatGptPlanAuth._TokenErrorMessage(401, Map("error", Map("code", "invalid_client", "message", "Client rejected.", "param", "client_id")))
        if !InStr(message, "invalid_client") || !InStr(message, "parameter: client_id")
            throw Error("Nested OAuth errors must retain protocol diagnostics")
        message := ChatGptPlanAuth._TokenErrorMessage(400, Map("error", "fixture-secret-value", "param", "fixture-secret-value"))
        if InStr(message, "fixture-secret-value")
            throw Error("Unexpected metadata values must not be echoed in token errors")
    }

    ScopeGate_DistinguishesIdentityFromPlanPermission() {
        identityOnly := Map(
            "access_token", "present",
            "refresh_token", "present",
            "scopes", ["openid", "profile", "email"]
        )
        planEnabled := Map(
            "access_token", "present",
            "refresh_token", "present",
            "scopes", ["openid", "chatgpt.tokens.use.direct"]
        )
        if !ChatGptPlanAuth._AccountHasSession(identityOnly)
            throw Error("identity-only account should still be a retained renewable session")
        if ChatGptPlanAuth._HasScope(identityOnly, "chatgpt.tokens.use.direct")
            throw Error("identity scopes must not imply ChatGPT-plan permission")
        if !ChatGptPlanAuth._HasScope(planEnabled, "chatgpt.tokens.use.direct")
            throw Error("direct plan scope should authorize the plan gate")
    }

    AccountFromTokenResponse_PreservesIssuedClientAndGrantedScopes() {
        tokens := Map(
            "id_token", "fixture-id",
            "access_token", "fixture-access",
            "refresh_token", "fixture-refresh",
            "expires_in", 3600,
            "scope", "openid profile chatgpt.tokens.use.direct"
        )
        claims := Map(
            "sub", "subject-1",
            "email", "person@example.test",
            "iss", ChatGptPlanAuth.ISSUER
        )
        account := ChatGptPlanAuth._AccountFromTokenResponse(tokens, claims, "oaiapp-fixture", "urn:uuid:00000000-0000-4000-8000-000000000001")
        if account["client_id"] != "oaiapp-fixture" || account["subject"] != "subject-1"
            throw Error("issued client id and verified subject must remain bound together")
        if !ChatGptPlanAuth._HasScope(account, "chatgpt.tokens.use.direct")
            throw Error("granted plan scope was not retained")
        if account["access_expires_at"] <= account["saved_at_epoch"]
            throw Error("access expiry metadata was not computed")
    }

    AudienceValidation_AcceptsOnlyIssuedClient() {
        if !ChatGptPlanAuth._AudienceContains("oaiapp-a", "oaiapp-a")
            throw Error("matching scalar audience should validate")
        if ChatGptPlanAuth._AudienceContains("oaiapp-a", "oaiapp-b")
            throw Error("mismatched scalar audience must fail")
        if !ChatGptPlanAuth._AudienceContains(["other", "oaiapp-b"], "oaiapp-b")
            throw Error("issued client should be accepted inside an audience array")
    }

    RecoveryFlow_RetainsIdentityAndPersistsRotatedRefreshBeforePermissionError() {
        src := FileRead(A_ScriptDir "\..\api\ChatGptPlanAuth.ahk")
        pollPos := InStr(src, "static PollSignIn(")
        ensurePos := InStr(src, "static _EnsureAccessTokenLocked(")
        if !pollPos || !ensurePos
            throw Error("ChatGPT auth flow functions not found")

        pollBlock := SubStr(src, pollPos, ensurePos - pollPos)
        savePos := InStr(pollBlock, "_SaveOrReplaceAccount(account, true)")
        permissionPos := InStr(pollBlock, 'hasPlanPermission := ChatGptPlanAuth._HasScope')
        if !savePos || !permissionPos || savePos > permissionPos
            throw Error("valid identity-only sign-in must be saved before plan-permission failure is reported")
        if !InStr(pollBlock, "permissionMissing := true")
            throw Error("identity-only sign-in must report the recoverable permission-missing state")

        refreshBlock := SubStr(src, ensurePos, InStr(src, "static FetchModels(", false, ensurePos) - ensurePos)
        saveRefreshPos := InStr(refreshBlock, "_SaveStore(store)")
        missingScopePos := InStr(refreshBlock, "no longer grants ChatGPT plan usage")
        if !saveRefreshPos || !missingScopePos || saveRefreshPos > missingScopePos
            throw Error("rotated refresh credentials must be persisted before reporting lost plan scope")
    }

    ReconnectWithoutPlanScope_RequestsConsentWithSavedClient() {
        src := FileRead(A_ScriptDir "\..\api\ChatGptPlanAuth.ahk")
        beginPos := InStr(src, "static BeginSignIn(")
        pollPos := InStr(src, "static PollSignIn(")
        block := SubStr(src, beginPos, pollPos - beginPos)
        if !InStr(block, 'pairs.Push(["prompt", "consent"])')
            throw Error("saved identity without plan scope must explicitly re-request consent")
        if InStr(block, "force_reconsent")
            throw Error("preview integration must not send force_reconsent before OpenAI enables it")
    }

    CredentialStore_IsSeparateFromSettingsAndStatusMetadataOmitsSecrets() {
        if InStr(ChatGptPlanAuth.CredentialsPath(), "settings.json")
            throw Error("ChatGPT credentials must not share settings.json")
        src := FileRead(A_ScriptDir "\..\api\ChatGptPlanAuth.ahk")
        statusPos := InStr(src, "static Status()")
        beginPos := InStr(src, "static BeginSignIn(")
        statusBlock := SubStr(src, statusPos, beginPos - statusPos)
        for forbidden in ['"accessToken"', '"refreshToken"', '"idToken"'] {
            if InStr(statusBlock, forbidden)
                throw Error("UI status metadata must not expose OAuth credentials: " forbidden)
        }
    }
}
