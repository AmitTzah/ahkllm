; ======================================================
; CommandThinkingMap.test.ahk — Regression test for bug #22: command `thinking`
; settings were dropped after a settings.json round-trip because cmd.thinking is
; an AHK Map and _extractCommandParams() gated on HasOwnProp("type") (false for
; Map keys). Fixed: the helper checks the shape (Map — Has(), object — HasOwnProp()).
; Both forms must survive.
; ======================================================

class CommandThinkingMapTest {

    static __New() {
        RegisterTestClass("CommandThinkingMapTest")
    }

    ; Post-round-trip shape: command built by _ApplyCommands from a settings Map.
    ; The fix: Map entries must be read with Has()/[] (HasOwnProp is false for
    ; Map keys), so Map-form thinking must survive exactly like the object form.
    MapForm_ThinkingSurvives() {
        cmd := {}
        cmd.thinking := Map("type", "enabled", "level", "none")
        cmd.pasteMode := "replace"
        cmd.isFIM := false
        cmd.userMessage := "{{selection}}"

        params := _extractCommandParams(cmd, "")
        ; params: pasteMode, isFIM, inputText, temperature, maxTokens, stop,
        ;         stream, thinkingType, thinkingLevel, ...
        if params[8] != "enabled" || params[9] != "none"
            throw Error("Map-form thinking should survive, got type='" params[8] "' level='" params[9] "'")
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
