; Catalog replacement, persistence, and multi-source refresh use no real accounts.
class ChatGptModelCatalogTest {
    static __New() {
        RegisterTestClass("ChatGptModelCatalogTest")
    }

    Reconcile_PreservesCodexAndOtherProviders() {
        existing := Map(
            "openai/keep", Map("provider", "openai", "input", 5),
            "codex/old", Map("provider", "codex"),
            "chatgpt/stale", Map("provider", "chatgpt"),
            "chatgpt/kept", Map("provider", "chatgpt", "context", 12345,
                "input", 9, "thinkingLevelMap", Map("high", "high"))
        )
        result := ChatGptModelCatalog.Reconcile(existing, [
            { slug: "kept", displayName: "Updated name" },
            { slug: "new", displayName: "New model" }
        ])
        if result.Count != 4 || !result.Has("codex/old") || result.Has("chatgpt/stale")
            throw Error("Only models in the latest account catalog should remain")
        if result["openai/keep"]["input"] != 5 || result["chatgpt/kept"]["context"] != 12345
            throw Error("Unrelated models and retained model metadata must survive")
        if result["chatgpt/kept"]["input"] != 0 || result["chatgpt/kept"]["displayName"] != "Updated name"
            throw Error("Plan costs must be zero and display names must refresh")
        if !result["chatgpt/kept"].Has("thinkingLevelMap") || result["chatgpt/new"]["api"] != "chatgpt-responses"
            throw Error("Responses and thinking metadata must survive discovery")
        if existing["chatgpt/kept"]["input"] != 9
            throw Error("Reconciliation must not mutate the previous catalog")
        emptied := ChatGptModelCatalog.Reconcile(existing, [])
        if emptied.Count != 2 || !emptied.Has("openai/keep") || !emptied.Has("codex/old")
            throw Error("A successful empty account catalog must prune all plan models")
    }

    Reconcile_RejectsMalformedCatalogBeforeChangingSettings() {
        for discovered in [[{ slug: "../invalid", displayName: "Invalid" }], [
            { slug: "same", displayName: "One" }, { slug: "same", displayName: "Two" }
        ]] {
            threw := false
            try ChatGptModelCatalog.Reconcile(Map(), discovered)
            catch
                threw := true
            if !threw
                throw Error("Malformed or duplicate model slugs must fail catalog validation")
        }
    }

    Save_PersistsAccountCatalogWithoutResurrectingFallbacks() {
        global models, providers, providerMap
        oldModels := models, oldProviders := providers, oldProviderMap := providerMap
        oldPath := SettingsHandler.settingsPath
        settingsPath := A_Temp "\test_plan_catalog_" A_TickCount "_" Random(1000, 999999) ".json"
        SettingsHandler.settingsPath := settingsPath
        try {
            initial := SettingsHandler.GetDefaults()
            initial["ui"]["responseFont"] := "Catalog test font"
            if !SettingsHandler.Save(initial)
                throw Error("Failed to seed catalog settings")
            catalog := ChatGptModelCatalog.Save([{ slug: "discovered-only", displayName: "Discovered model" }])
            reloaded := SettingsService.LoadMerged()
            planCount := 0
            for modelId, metadata in reloaded["models"] {
                if ChatGptModelCatalog.IsPlanModel(modelId, metadata)
                    planCount++
            }
            if planCount != 1 || !reloaded["models"].Has("chatgpt/discovered-only")
                throw Error("Restart must load the saved account catalog without injecting bundled models")
            if reloaded["ui"]["responseFont"] != "Catalog test font"
                throw Error("Catalog refresh must preserve other saved settings")
            if !models.Has("chatgpt/discovered-only") || models["chatgpt/discovered-only"].displayName != "Discovered model"
                throw Error("Runtime picker must receive refreshed model names")
            if catalog.Count != 1 || catalog.Has("openai/gpt-5-mini")
                throw Error("UI update must contain only ChatGPT models")
            ChatGptModelCatalog.Save([])
            reloaded := SettingsService.LoadMerged()
            for modelId, metadata in reloaded["models"] {
                if ChatGptModelCatalog.IsPlanModel(modelId, metadata)
                    throw Error("Empty account catalogs must remain empty after reload")
            }
        } finally {
            models := oldModels, providers := oldProviders, providerMap := oldProviderMap
            SettingsHandler.settingsPath := oldPath
            try FileDelete(settingsPath)
        }
    }

    Refresh_PlanOnlySkipsModelsDevAndMergesMixedSources() {
        planProviders := Map("chatgpt", Map("transport", "chatgpt-responses"))
        catalog := Map("chatgpt/new", Map("provider", "chatgpt"))
        calls := []
        fetchMetadata := (config) => (calls.Push(config.spec), [{ id: "openai/api-model", meta: Map("provider", "openai") }])
        result := _RefreshConfiguredModelCatalogs(Map("providers", planProviders), fetchMetadata, () => catalog)
        if calls.Length || result.models.Length != 1 || result.sources[1] != "ChatGPT"
            throw Error("Plan-only refresh must skip models.dev and return the account catalog")
        planProviders["openai"] := Map("transport", "http")
        result := _RefreshConfiguredModelCatalogs(Map("providers", planProviders), fetchMetadata, () => catalog)
        if calls.Length != 1 || calls[1] != "openai=openai" || result.models.Length != 2
            throw Error("Mixed-source refresh must fetch both catalogs without sending ChatGPT to models.dev")
    }

    Refresh_PartialFailureKeepsSuccessfulSourceAndReportsWarning() {
        providerData := Map("chatgpt", Map("transport", "chatgpt-responses"), "openai", Map("transport", "http"))
        fail := (*) => this._ThrowRefreshFailure()
        result := _RefreshConfiguredModelCatalogs(Map("providers", providerData),
            (*) => [{ id: "openai/kept", meta: Map("provider", "openai") }], fail)
        if result.models.Length != 1 || result.sources[1] != "models.dev" || !result.warnings.Length
            throw Error("ChatGPT refresh failure must preserve successful API results and report a warning")
        result := _RefreshConfiguredModelCatalogs(Map("providers", providerData), fail,
            () => Map("chatgpt/kept", Map("provider", "chatgpt")))
        if result.models.Length != 1 || result.sources[1] != "ChatGPT" || !result.warnings.Length
            throw Error("Metadata-source failure must preserve successful ChatGPT results")
        threw := false
        try _RefreshConfiguredModelCatalogs(Map("providers", providerData), fail, fail)
        catch
            threw := true
        if !threw
            throw Error("Failure of every source must not be reported as a successful refresh")
    }

    _ThrowRefreshFailure() {
        throw Error("Fixture refresh failed")
    }
}
