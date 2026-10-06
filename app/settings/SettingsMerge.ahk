; ======================================================
; SettingsMerge.ahk — deep-merge loaded settings with defaults
;
; For each top-level key in defaults, use the loaded value when present,
; otherwise the default. Nested Maps merge recursively, except models/providers
; where the saved file defines WHICH entries exist (so removals persist) and
; defaults only fill fields of retained entries; unknown keys in the loaded
; settings are preserved.
; ======================================================

class SettingsMerge {

    static ProviderDisplayName(providerKey, displayName) {
        ; Repair labels inherited from the provider replacement, while keeping
        ; names the user has deliberately customized.
        if providerKey != "codex" && providerKey != "chatgpt"
            return displayName
        if displayName = "" || displayName = "Codex CLI (ChatGPT subscription)"
            || displayName = "Codex CLI" || displayName = "ChatGPT plan"
            return providerKey = "codex" ? "Codex CLI" : "ChatGPT plan"
        return displayName
    }

    static NormalizeProviderDisplayNames(settings) {
        if !(settings is Map) || !settings.Has("providers") || !(settings["providers"] is Map)
            return settings
        result := settings.Clone()
        result["providers"] := settings["providers"].Clone()
        for providerKey in ["codex", "chatgpt"] {
            if !result["providers"].Has(providerKey) || !(result["providers"][providerKey] is Map)
                continue
            provider := result["providers"][providerKey].Clone()
            provider["displayName"] := SettingsMerge.ProviderDisplayName(providerKey, provider.Get("displayName", ""))
            result["providers"][providerKey] := provider
        }
        return result
    }

    static Merge(existing, defaults) {
        result := Map()
        for k, defaultVal in defaults {
            if existing.Has(k) {
                existingVal := existing[k]
                if IsObject(existingVal) && existingVal is Map && IsObject(defaultVal) && defaultVal is Map {
                    ; The Settings panel manages models/providers as complete
                    ; lists, so the saved file defines WHICH entries exist —
                    ; otherwise a removed default model/provider is resurrected
                    ; by the deep merge on every load. Entries still present get
                    ; their missing fields filled from defaults below.
                    if k = "models" || k = "providers" {
                        result[k] := SettingsMerge.MergeAuthoritativeList(existingVal, defaultVal)
                        ; Both built-in subscription providers/models must exist even
                        ; for authoritative settings files created before they shipped.
                        ; Other removed defaults stay removed.
                        if k = "providers" && defaultVal.Has("chatgpt") && !result[k].Has("chatgpt")
                            result[k]["chatgpt"] := SettingsDefaults._DeepClone(defaultVal["chatgpt"])
                        if k = "providers" && defaultVal.Has("codex") && !result[k].Has("codex")
                            result[k]["codex"] := SettingsDefaults._DeepClone(defaultVal["codex"])
                        if k = "models" {
                            for defaultId, defaultModel in defaultVal {
                                if !IsObject(defaultModel) || !defaultModel.Has("provider")
                                    continue
                                shouldInject := defaultModel["provider"] = "codex"
                                    || (defaultModel["provider"] = "chatgpt" && !SettingsMerge.HasAccountModelCatalog(existing))
                                if shouldInject && !result[k].Has(defaultId)
                                    result[k][defaultId] := SettingsDefaults._DeepClone(defaultModel)
                            }
                        }
                    }
                    else
                        result[k] := SettingsMerge.Merge(existingVal, defaultVal)
                } else {
                    result[k] := existingVal
                }
            } else {
                result[k] := defaultVal
            }
        }
        ; Also include any keys in existing that are NOT in defaults
        for k, existingVal in existing {
            if !result.Has(k)
                result[k] := existingVal
        }
        ; A profile predating a new built-in provider may have no saved models
        ; list. Populate defaults only for its configured providers, otherwise
        ; orphan defaults block every Settings save. Never prune saved models.
        if !existing.Has("models") && result.Has("models") && result.Has("providers") {
            result["models"] := result["models"].Clone()
            orphanedDefaults := []
            for modelId, metadata in result["models"]
                if metadata.Has("provider") && !result["providers"].Has(metadata["provider"])
                    orphanedDefaults.Push(modelId)
            for modelId in orphanedDefaults
                result["models"].Delete(modelId)
        }
        return result
    }

    static HasAccountModelCatalog(settings) {
        return settings.Has("providers") && settings["providers"].Has("chatgpt")
            && settings["providers"]["chatgpt"].Get("modelCatalogSource", "") = "account"
    }

    ; Merge a saved enumeration (models/providers) with its defaults so that
    ; membership comes from the saved file (removals persist across reloads),
    ; while each entry that still exists fills missing fields from the matching
    ; default entry (e.g. api/compat/thinkingLevelMap metadata added after the
    ; entry was first saved).
    static MergeAuthoritativeList(existingList, defaultList) {
        result := Map()
        for k, existingEntry in existingList {
            if IsObject(existingEntry) && existingEntry is Map && defaultList.Has(k) && IsObject(defaultList[k]) && defaultList[k] is Map
                result[k] := SettingsMerge.Merge(existingEntry, defaultList[k])
            else
                result[k] := existingEntry
        }
        return result
    }

    ; Apply a settings-panel save payload over a base settings Map.
    ; Every top-level key the UI sends replaces the base value wholesale —
    ; each settings section returns its complete data (models, providers,
    ; hotkeys, ...), so a deep merge would resurrect entries the user removed
    ; from a section. Top-level keys the UI did not send keep their base
    ; (saved/default) values.
    static Override(incoming, base) {
        ; Reject non-object incoming payloads (for example, "" from crafted IPC);
        ; would iterate over string characters and pollute the merged map.
        if !IsObject(incoming)
            incoming := Map()
        result := Map()
        for k, v in base
            result[k] := v
        for k, v in incoming
            result[k] := v
        return result
    }
}
