; probe-cost.ahk - Bug #29: a blank cachedInput price must fall back to 10% of
; input, but CostCalculator only falls back when the property is MISSING, not
; when the settings round-trip stores it as "" or 0.
; Lightweight: includes ONLY ModelParser + CostCalculator with a stubbed
; `models` global. Usage: AutoHotkey64.exe probe-cost.ahk <outFile>
#Requires AutoHotkey v2.0.18+
#ErrorStdOut
#SingleInstance Off
#NoTrayIcon
global outFile := A_Args.Length >= 1 ? A_Args[1] : A_Temp "\bughunt_cost_result.txt"
global logLines := []
Log(m) {
    global logLines
    logLines.Push(m)
}
SetTimer(ExitProbe, -15000)
ExitProbe(*) {
    Log("WATCHDOG fired")
    Finish()
    ExitApp(1)
}
OnError((e, m) => (Log("ERROR: " e.Message), Finish(), ExitApp(1)), -1)

; A UI-added model: the settings round-trip stores cachedInput as "" (blank
; field), which the settings UI advertises as "defaults to 10% of input".
global models := Map(
    "test/blank-cached", { provider: "test", input: 10, cachedInput: "", output: 20, context: 1000000 },
    "test/no-cached",    { provider: "test", input: 10, output: 20, context: 1000000 }
)

#Include ..\..\shared\ModelParser.ahk
#Include ..\..\api\CostCalculator.ahk

Finish() {
    global outFile, logLines
    try FileAppend(Join("`n", logLines), outFile, "UTF-8")
}
Join(sep, arr) {
    out := ""
    for i, v in arr
        out .= (i > 1 ? sep : "") v
    return out
}

usage := { promptTokens: 1000000, completionTokens: 0, cachedTokens: 1000000, totalTokens: 1000000 }
missingCosts := CostCalculator.ComputeTokenCosts("test/no-cached", usage)
Log("missingCachedInputCost=" missingCosts.cachedInputCost)
Log("BUG29 missingFallback=" (missingCosts.cachedInputCost = 1 ? "OK" : "BROKEN"))
; A blank cachedInput ("" stored by the settings round-trip) must not crash cost
; calculation. Control above (property missing) is fine; this one throws.
try {
    blankCosts := CostCalculator.ComputeTokenCosts("test/blank-cached", usage)
    Log("BUG29 throw=NO blankCost=" blankCosts.cachedInputCost)
} catch Error as e {
    Log("BUG29 throw=YES error=" e.Message)
}
Finish()
ExitApp(0)
