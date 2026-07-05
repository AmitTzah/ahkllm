; ======================================================
; run_tests.ahk — Test runner entry point
;
; Usage: AutoHotkey64.exe ai-automation/tests/run_tests.ahk
;
; Includes all test files, discovers test classes,
; runs each method, prints PASS/FAIL to stdout.
; #ErrorStdOut catches load-time parse errors (no flag needed).
; OnError catches runtime errors (prevents GUI popups).
; ======================================================

#Requires AutoHotkey v2.0.18+
#ErrorStdOut
#SingleInstance Off
#NoTrayIcon

; -----------------------------------------------------------
; Global error handler — catches ALL runtime errors and
; outputs to stdout instead of showing a GUI dialog.
; This is REQUIRED for headless/automated test execution.
; -----------------------------------------------------------
OnError(TestErrorHandler, -1)
TestErrorHandler(err, mode) {
    FileAppend("[RUNTIME ERROR] " err.Message "`n", "*")
    if err.HasProp("Stack") && err.Stack
        FileAppend(err.Stack "`n", "*")
    ExitApp(1)
}

; Load test config FIRST (provides mock globals + MsgBox override)
#Include test_config.ahk

; -----------------------------------------------------------
; Test registration (must be BEFORE #Include test files
; since __New() in test files calls RegisterTestClass)
; -----------------------------------------------------------
global __TestClasses := []

RegisterTestClass(className) {
    global __TestClasses
    __TestClasses.Push(className)
}

; Include production modules needed by tests
#Include ..\lib\jsongo.v2.ahk
#Include ..\lib\SQLite\SQLite.ahk
#Include ..\api\LLMClient.ahk
#Include ..\api\SSEParser.ahk
#Include ..\api\ApiLogger.ahk
#Include ..\api\CostCalculator.ahk
#Include ..\chat\ChatDB.ahk
#Include ..\chat\ChatUtils.ahk
#Include ..\chat\StreamHandler.ahk
#Include ..\chat\ChatCallbacks_Message.ahk
#Include ..\ui\CustomMessages.ahk

; Include test files
#Include unit\ChatDB.test.ahk
#Include unit\LLMClient.test.ahk
#Include unit\ChatUtils.test.ahk
#Include unit\StreamHandler.test.ahk
#Include unit\CustomMessages.test.ahk
#Include integration\ChatFlow.test.ahk
#Include integration\BranchFlow.test.ahk

; -----------------------------------------------------------
; Test runner — discovers and runs all test classes
; -----------------------------------------------------------

totalPassed := 0
totalFailed := 0
failedDetails := []

RunAllTests(*) {
    global __TestClasses, totalPassed, totalFailed, failedDetails
    for i, className in __TestClasses {
        if SubStr(className, 1, 1) = "_"
            continue
        RunTestClass(className)
    }
    total := totalPassed + totalFailed
    FileAppend("`n---`n", "*")
    FileAppend(total " tests run | " totalPassed " passed | " totalFailed " failed`n", "*")
    if failedDetails.Length > 0 {
        FileAppend("`nFAILURES:`n", "*")
        for detail in failedDetails
            FileAppend("  " detail "`n", "*")
    }
    ExitApp(totalFailed > 0 ? 1 : 0)
}

RunTestClass(className) {
    global __TestClasses, totalPassed, totalFailed, failedDetails
    try {
        obj := %className%()
        methodCount := 0
        ; Iterate prototype to access method definitions
        proto := %className%.Prototype
        for methodName in proto.OwnProps() {
            if SubStr(methodName, 1, 1) = "_"
                continue
            methodCount++
            try {
                obj.%methodName%()
                FileAppend("[PASS] " className "." methodName "`n", "*")
                totalPassed++
            } catch Error as err {
                FileAppend("[FAIL] " className "." methodName " — " err.Message "`n", "*")
                totalFailed++
                failedDetails.Push(className "." methodName ": " err.Message)
            }
        }
    } catch Error as err {
        FileAppend("[FAIL] " className " (class init) — " err.Message "`n", "*")
        totalFailed++
    }
}

; Verify MsgBox override is active
if MsgBox("test") != "OK" {
    FileAppend("[CRITICAL] test_config.ahk MsgBox override not active! Tests aborted.`n", "*")
    ExitApp(1)
}

RunAllTests()
