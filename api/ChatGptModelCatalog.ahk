; Account-specific model catalogs replace only ChatGPT entries in settings.
class ChatGptModelCatalog {
    static IsPlanModel(modelId, metadata) {
        if ModelParser.IsChatGptPlan(modelId)
            return true
        return IsObject(metadata) && metadata.Has("provider")
            && ModelParser.CanonicalProvider(metadata["provider"]) = "chatgpt"
    }

    static Reconcile(existingModels, discovered) {
        if !(discovered is Array)
            throw Error("ChatGPT model catalog must be an array.")
        result := Map()
        for modelId, metadata in existingModels {
            if !ChatGptModelCatalog.IsPlanModel(modelId, metadata)
                result[modelId] := metadata
        }
        for item in discovered {
            if !IsObject(item) || !item.HasOwnProp("slug") || !RegExMatch(item.slug, "^[A-Za-z0-9._:-]+$")
                throw Error("ChatGPT model catalog contains an invalid model slug.")
            modelId := "chatgpt/" item.slug
            if result.Has(modelId)
                throw Error("ChatGPT model catalog contains duplicate model slugs.")
            existing := existingModels.Has(modelId) ? existingModels[modelId] : Map()
            metadata := SettingsPersistence._ToMap(existing)
            metadata["provider"] := "chatgpt"
            metadata["api"] := "chatgpt-responses"
            metadata["displayName"] := item.displayName
            for field in ["input", "cachedInput", "output"]
                metadata[field] := 0
            for field, value in Map("context", 0, "reasoning", true, "vision", true) {
                if !metadata.Has(field)
                    metadata[field] := value
            }
            if !metadata.Has("compat")
                metadata["compat"] := Map()
            for field, value in Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "")
                metadata["compat"][field] := value
            result[modelId] := metadata
        }
        return result
    }

    static Save(discovered) {
        settings := SettingsService.LoadMerged()
        settings["models"] := ChatGptModelCatalog.Reconcile(settings["models"], discovered)
        settings["providers"]["chatgpt"]["modelCatalogSource"] := "account"
        if !SettingsHandler.Save(settings)
            throw Error("Could not save the ChatGPT model catalog. The previous catalog was kept.")
        SettingsService.Apply(Map("models", settings["models"], "providers", settings["providers"]))
        catalog := Map()
        for modelId, metadata in settings["models"] {
            if ChatGptModelCatalog.IsPlanModel(modelId, metadata)
                catalog[modelId] := metadata
        }
        return catalog
    }
}
