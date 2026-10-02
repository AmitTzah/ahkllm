; Model discovery from models.dev and the active ChatGPT account.
_BuildModelsDevCatalogConfig(providerData) {
    providersMap := SettingsHandler._ToMap(providerData)
    spec := ""
    config := Map()
    for providerKey, p in providersMap {
        if ModelParser.CanonicalProvider(providerKey) = "chatgpt" || p.Get("transport", "http") != "http"
            continue
        providerKey := Trim(providerKey)
        if !RegExMatch(providerKey, "^[a-z0-9][a-z0-9._-]*$")
            throw Error("Invalid provider ID for models.dev refresh: " providerKey)
        catalog := Trim(p.Get("modelsDevProvider", ""))
        if catalog = ""
            catalog := providerKey
        if !RegExMatch(catalog, "^[a-z0-9][a-z0-9._-]*$")
            throw Error("Invalid models.dev provider key: " catalog)
        spec .= (spec = "" ? "" : ";") providerKey "=" catalog
        config[providerKey] := { catalog: catalog, displayName: p.Get("displayName", providerKey) }
    }
    return { spec: spec, providers: config }
}

_HandleRefreshModelPricing(parsed) {
    try postWebMessage("modelPricingRefresh", _RefreshConfiguredModelCatalogs(parsed))
    catch Error as e
        postWebMessage("modelPricingRefresh", { success: false, error: e.Message })
}

_RefreshConfiguredModelCatalogs(parsed, fetchMetadata := "", refreshPlanCatalog := "") {
    if !IsObject(fetchMetadata)
        fetchMetadata := _FetchModelsDevMetadata
    if !IsObject(refreshPlanCatalog)
        refreshPlanCatalog := _HandleRefreshChatGptModels
    providerData := parsed.Get("providers", "")
    liveCatalogs := IsObject(providerData)
    config := liveCatalogs ? _BuildModelsDevCatalogConfig(providerData) : ""
    result := { success: true, models: [], warnings: [], sources: [] }
    if !liveCatalogs || config.spec != "" {
        try {
            result.models := fetchMetadata.Call(config)
            result.sources.Push("models.dev")
            if liveCatalogs
                _AddModelsDevWarnings(result, config)
        } catch Error as e
            result.warnings.Push(e.Message)
    }
    if liveCatalogs && (providerData.Has("chatgpt") || providerData.Has("codex")) {
        try {
            catalog := refreshPlanCatalog.Call()
            for modelId, metadata in catalog
                result.models.Push({ id: modelId, meta: metadata })
            result.sources.Push("ChatGPT")
        } catch Error as e
            result.warnings.Push("ChatGPT: " e.Message)
    }
    if !result.sources.Length
        throw Error(result.warnings.Length ? CodexCliRuntime.Join(result.warnings, " ") : "No providers configured for model refresh")
    return result
}

_FetchModelsDevMetadata(config := "") {
    scriptPath := A_ScriptDir "\..\scripts\Refresh-Models.ps1"
    if !FileExist(scriptPath)
        throw Error("scripts\Refresh-Models.ps1 not found")
    ; -NoPause prevents the hidden script from waiting for interactive input.
    cmd := "powershell -NoProfile -ExecutionPolicy Bypass -File `"" scriptPath "`" -NoPause"
    if IsObject(config) {
        cmd .= " -ProviderCatalogs `"" config.spec "`" -NoUpdateDefaults"
        pricingFile := A_ScriptDir "\..\scripts\models_metadata.txt"
    } else
        pricingFile := A_ScriptDir "\..\default-settings\DefaultModels.ahk"
    exitCode := RunWait(cmd, A_ScriptDir, "Hide")
    if exitCode != 0
        throw Error("Refresh-Models.ps1 exited with code " exitCode)
    if !FileExist(pricingFile)
        throw Error("Model metadata output was not generated")
    fetchedModels := ModelPricingParser.Parse(FileRead(pricingFile, "UTF-8"))
    if !IsObject(config) && !fetchedModels.Length
        throw Error("No models parsed from DefaultModels.ahk")
    return fetchedModels
}

_AddModelsDevWarnings(result, config) {
    seenProviders := Map()
    for model in result.models {
        parts := ModelParser.Split(model.id)
        if parts.provider != ""
            seenProviders[parts.provider] := true
    }
    for providerKey, providerConfig in config.providers {
        if providerConfig.catalog = "openrouter" {
            if providerKey != "openrouter"
                result.warnings.Push(providerConfig.displayName ": the OpenRouter catalog is lookup-only; add models manually for this transport.")
        } else if !seenProviders.Has(providerKey)
            result.warnings.Push(providerConfig.displayName ": no compatible models were found in models.dev catalog '" providerConfig.catalog "'.")
    }
}
