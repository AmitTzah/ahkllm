; ======================================================
; CommandThinkingMap.test.ahk — Regression test for the "Refine still thinks"
; bug: after a settings.json round-trip, cmd.thinking is an AHK Map, and
; _extractCommandParams() gates on HasOwnProp("type") which is FALSE for Map
; keys — so thinking type/level are silently dropped and no thinking config is
; sent (the model falls back to its default, i.e. it thinks even when the
; command is set to "none"/off).
; ======================================================

class CommandThinkingMapTest {

    static __New() {
        RegisterTestClass("CommandThinkingMapTest")
    }

    ; Post-round-trip shape: command built by _ApplyCommands from a settings Map.
    MapForm_ThinkingIsDropped() {
        cmd := {}
        cmd.thinking := Map("type", "enabled", "level", "none")
        cmd.pasteMode := "replace"
        cmd.isFIM := false
        cmd.userMessage := "{{selection}}"

        params := _extractCommandParams(cmd, "")
        ; params: pasteMode, isFIM, inputText, temperature, maxTokens, stop,
        ;         stream, thinkingType, thinkingLevel, ...
        if params[8] != "" || params[9] != ""
            throw Error("Map-form thinking should be dropped, got type='" params[8] "' level='" params[9] "'")
    }

    ; Control: fresh-defaults object literal form keeps thinking.
    ObjectForm_ThinkingSurvives() {
        cmd := {
            thinking: { type: "enabled", level: "none" },
            pasteMode: "replace",
            isFIM: false,
            userMessage: "{{selection}}"
        }
        params := _extractCommandParams(cmd, "")
        if params[8] != "enabled" || params[9] != "none"
            throw Error("Object-form thinking should survive, got type='" params[8] "' level='" params[9] "'")
    }
}
