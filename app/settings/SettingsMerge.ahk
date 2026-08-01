; ======================================================
; SettingsMerge.ahk — deep-merge loaded settings with defaults
;
; For each top-level key in defaults, use the loaded value when present,
; otherwise the default. Nested Maps merge recursively; unknown keys in the
; loaded settings are preserved.
; ======================================================

class SettingsMerge {
    static Merge(existing, defaults) {
        result := Map()
        for k, defaultVal in defaults {
            if existing.Has(k) {
                existingVal := existing[k]
                if IsObject(existingVal) && existingVal is Map && IsObject(defaultVal) && defaultVal is Map {
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
}
