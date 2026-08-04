; ======================================================
; SettingsService.ahk — single apply path for settings
;
; Consolidates the ad-hoc "settings changed" chains (the inline
; Load + Merge + ApplyToGlobals + per-section rebuild calls scattered
; across Main.ahk / ChatWindow.ahk / Dispatch.ahk) into one Apply()
; that runs registered update hooks. Each process registers the hooks
; it owns:
;   Main.ahk:        suspend banner, input window, hotkeys,
;                    runtime resolver, trash purge
;   ChatWindow.ahk:  chat hotkeys
;
; New settings-driven rebuilds register a hook here instead of adding
; another call site to the WM_SETTINGS_UPDATED chain.
; ======================================================

class SettingsService {
    static _hooks := Map()

    ; Register (or replace) an update hook by name. Hooks run after every
    ; Apply(); each hook failure is logged and does not abort the others.
    static RegisterHook(name, fn) {
        this._hooks[name] := fn
    }

    static _RunHooks() {
        for name, fn in this._hooks {
            try {
                fn.Call()
            } catch Error as e {
                debugLog("[SETTINGS] hook '" name "' failed: " e.Message)
            }
        }
    }

    ; Load saved settings merged with defaults.
    static LoadMerged() {
        loaded := SettingsHandler.Load()
        defaults := SettingsHandler.GetDefaults()
        return SettingsHandler.Merge(loaded, defaults)
    }

    ; Apply a settings Map to globals and run all registered update hooks.
    static Apply(settings) {
        SettingsHandler.ApplyToGlobals(settings)
        this._RunHooks()
    }

    ; Reload settings.json, merge with defaults, apply, run hooks.
    ; Single code path for Main's WM_SETTINGS_UPDATED handler (replaces the
    ; old inline Load+Merge+Apply+rebuild chain).
    static ReloadFromDisk() {
        debugLog("[SETTINGS] Reloading settings from disk...")
        this.Apply(this.LoadMerged())
    }

    ; Save a WebView payload: merge with the current loaded settings (each
    ; section payload authoritative for its own top-level key), persist,
    ; apply, and run hooks. Returns the merged Map, or "" when saving failed.
    static SaveFromWebView(settingsData) {
        settingsMap := SettingsHandler._ToMap(settingsData)
        base := SettingsHandler.Merge(SettingsHandler.Load(), SettingsHandler.GetDefaults())
        merged := SettingsHandler.Override(settingsMap, base)
        if !SettingsHandler.Save(merged)
            return ""
        this.Apply(merged)
        return merged
    }
}
