; ======================================================
; AssistantRepo.ahk — Assistant CRUD operations
;
; Part of ChatDB split. Extracted from ChatDB.ahk.
; ======================================================

#Include ..\..\shared\SystemMessageResolver.ahk
#Include ..\..\shared\DebugLog.ahk

class AssistantRepo {

    ; Get an assistant by ID from the global assistants array (populated by SettingsHandler)
    static GetFromSettings(assistantId) {
        global assistants
        if !IsSet(assistants)
            return ""
        for a in assistants {
            if a.HasOwnProp("id") && a.id = assistantId
                return a
        }
        return ""
    }

    static _resolveSystemMessage(a) {
        ; Use the shared system-message resolver.
        res := SystemMessageResolver.Resolve(a)
        if res.error != ""
            debugLog("[SETTINGS] Failed to read assistant system message: " res.error)
        return res.text
    }
}
