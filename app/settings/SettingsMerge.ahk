; ======================================================
; SettingsMerge.ahk — deep-merge loaded settings with defaults
;
; For each top-level key in defaults, use the loaded value when present,
; otherwise the default. Nested Maps merge recursively, except models/providers
; where the saved file defines WHICH entries exist (so removals persist) and
; defaults only fill fields of retained entries; unknown keys in the loaded
; settings are preserved.
; ======================================================

#Include ..\..\shared\ModelParser.ahk

class SettingsMerge {
    ; Normalize the historical ChatGPT-plan `codex` namespace without touching
    ; conversation DB rows. The returned settings tree uses canonical
    ; `chatgpt` provider/model ids so the next save permanently upgrades
    ; settings.json while old DB model ids remain resolvable via ModelParser.
    static CanonicalizeChatGptAliases(settings) {
        if !IsObject(settings) || !(settings is Map)
            return settings

        result := Map()
        for k, v in settings
            result[k] := v

        if result.Has("providers") && IsObject(result["providers"]) && result["providers"] is Map {
            src := result["providers"], dst := Map()
            hasCanonical := src.Has("chatgpt")
            for k, v in src {
                if k = "codex" {
                    if hasCanonical
                        continue
                    dst["chatgpt"] := v
                } else
                    dst[k] := v
            }
            result["providers"] := dst
        }

        if result.Has("models") && IsObject(result["models"]) && result["models"] is Map {
            src := result["models"], dst := Map()
            for k, v in src {
                canonicalId := ModelParser.Canonicalize(k)
                if canonicalId != k && src.Has(canonicalId)
                    continue
                if IsObject(v) && v is Map {
                    copy := Map()
                    for field, fieldValue in v
                        copy[field] := fieldValue
                    if copy.Has("provider")
                        copy["provider"] := ModelParser.CanonicalProvider(copy["provider"])
                    v := copy
                }
                dst[canonicalId] := v
            }
            result["models"] := dst
        }

        if result.Has("assistants") && IsObject(result["assistants"]) {
            normalized := []
            for _, a in result["assistants"] {
                if IsObject(a) && a is Map {
                    copy := Map()
                    for field, fieldValue in a
                        copy[field] := fieldValue
                    if copy.Has("baseModel")
                        copy["baseModel"] := ModelParser.Canonicalize(copy["baseModel"])
                    normalized.Push(copy)
                } else
                    normalized.Push(a)
            }
            result["assistants"] := normalized
        }

        if result.Has("commands") && IsObject(result["commands"]) {
            normalized := []
            for _, c in result["commands"] {
                if IsObject(c) && c is Map {
                    copy := Map()
                    for field, fieldValue in c
                        copy[field] := fieldValue
                    if copy.Has("APIModels")
                        copy["APIModels"] := ModelParser.Canonicalize(copy["APIModels"])
                    normalized.Push(copy)
                } else
                    normalized.Push(c)
            }
            result["commands"] := normalized
        }

        if result.Has("newChatStartsWith") {
            value := result["newChatStartsWith"]
            if value != "" && SubStr(value, 1, 5) != "asst:"
                result["newChatStartsWith"] := ModelParser.Canonicalize(value)
        }

        if result.Has("threadTitles") && IsObject(result["threadTitles"]) && result["threadTitles"] is Map {
            tt := Map()
            for field, fieldValue in result["threadTitles"]
                tt[field] := fieldValue
            if tt.Has("model")
                tt["model"] := ModelParser.Canonicalize(tt["model"])
            result["threadTitles"] := tt
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
                        ; The built-in ChatGPT-plan provider/models must exist even
                        ; for authoritative settings files created before they shipped.
                        ; Other removed defaults stay removed.
                        if k = "providers" && defaultVal.Has("chatgpt") && !result[k].Has("chatgpt")
                            result[k]["chatgpt"] := SettingsDefaults._DeepClone(defaultVal["chatgpt"])
                        if k = "models" && !SettingsMerge.HasAccountModelCatalog(existing) {
                            for defaultId, defaultModel in defaultVal {
                                if !result[k].Has(defaultId) && IsObject(defaultModel) && defaultModel.Has("provider") && defaultModel["provider"] = "chatgpt"
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
