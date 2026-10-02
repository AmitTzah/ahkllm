; Exercise real mutex callbacks and DPAPI persistence using an isolated profile.
; Fake tokens remain unexpired; sign-out omits renewal tokens, so no network is used.
class ChatGptCredentialStoreTest {
    static __New() {
        RegisterTestClass("ChatGptCredentialStoreTest")
    }

    CredentialLifecycle_PublicCallbacksSaveReadSwitchAndSignOut() {
        oldDataDir := AppInfo.DataDir
        oldFixtureMode := EnvGet("AHKLLM_E2E_PLAN_AUTH")
        profileDirectory := A_Temp "\test_chatgpt_credentials_" A_TickCount "_" Random(1000, 999999)
        AppInfo.DataDir := profileDirectory
        EnvSet("AHKLLM_E2E_PLAN_AUTH", "")
        credentialPath := ChatGptPlanAuth.CredentialsPath()
        try {
            first := this._Account("fixture-first", "fixture-token-first")
            ChatGptPlanAuth._SaveOrReplaceAccount(first, true)
            if !FileExist(credentialPath)
                throw Error("Sign-in must save an encrypted credential record")
            if !ChatGptPlanAuth.Status().authenticated
                throw Error("A saved renewable session must be authenticated")
            if ChatGptPlanAuth.EnsureAccessToken() != first["access_token"]
                throw Error("Token retrieval must invoke the mutex callback with its method receiver")

            second := this._Account("fixture-second", "fixture-token-second")
            ChatGptPlanAuth._SaveOrReplaceAccount(second, false)
            if ChatGptPlanAuth.Status().clientId != "fixture-first"
                throw Error("Adding a registration must preserve the active account when requested")
            if !ChatGptPlanAuth.SetActiveAccount("fixture-second")
                throw Error("Account switching must invoke its mutex callback successfully")
            if ChatGptPlanAuth.EnsureAccessToken() != second["access_token"]
                throw Error("Token retrieval must use the selected account after switching")
            if ChatGptPlanAuth.SetActiveAccount("missing-account")
                throw Error("Unknown registrations must not become active")

            ; Remove the dummy renewal token to exercise local sign-out only.
            second["refresh_token"] := ""
            ChatGptPlanAuth._SaveOrReplaceAccount(second, true)
            result := ChatGptPlanAuth.SignOut("fixture-second")
            if !result.success || ChatGptPlanAuth.Status().authenticated
                throw Error("Sign-out must clear the selected account's session")
            stored := ChatGptPlanAuth._LoadStore()
            if stored["accounts"].Length != 2 || stored["active_client_id"] != "fixture-second"
                throw Error("Sign-out must retain registration records and active-account identity")
            if !ChatGptPlanAuth.SetActiveAccount("fixture-first") || !ChatGptPlanAuth.Status().authenticated
                throw Error("Signing out one account must preserve the other saved session")
        } finally {
            AppInfo.DataDir := oldDataDir
            EnvSet("AHKLLM_E2E_PLAN_AUTH", oldFixtureMode)
            for path in [credentialPath, credentialPath ".tmp"]
                try FileDelete(path)
            try DirDelete(profileDirectory)
        }
    }

    _Account(clientId, accessToken) {
        return Map(
            "client_id", clientId, "subject", "fixture-subject-" clientId,
            "email", "fixture@example.invalid", "access_token", accessToken,
            "refresh_token", "fixture-renewal", "access_expires_at", ChatGptPlanCrypto.UnixNow() + 3600,
            "scopes", ["openid", "chatgpt.tokens.use.direct"]
        )
    }
}
