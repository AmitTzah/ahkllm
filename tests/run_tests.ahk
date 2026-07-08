; ======================================================
; run_tests.ahk — Test runner entry point
;
; Usage: AutoHotkey64.exe ai-automation/tests/run_tests.ahk
;
; Includes all test files, discovers test classes,
; runs each method, prints PASS/FAIL to test log file.
; Output goes to A_Temp "\test_results.txt"
; #ErrorStdOut catches load-time parse errors (no flag needed).
; OnError catches runtime errors (prevents GUI popups).
; ======================================================

#Requires AutoHotkey v2.0.18+
#ErrorStdOut
#SingleInstance Off
#NoTrayIcon

; -----------------------------------------------------------
; Output file for test results (avoids FileAppend to "*" which
; fails when no console is attached to the AHK process)
; -----------------------------------------------------------
global TEST_LOG := A_Temp "\test_results.txt"
try FileDelete(TEST_LOG)

; -----------------------------------------------------------
; Global error handler — catches ALL runtime errors and
; writes to the test log instead of showing a GUI dialog.
; This is REQUIRED for headless/automated test execution.
; -----------------------------------------------------------
OnError(TestErrorHandler, -1)
TestErrorHandler(err, mode) {
    global TEST_LOG
    try FileAppend("[RUNTIME ERROR] " err.Message "`n", TEST_LOG)
    if err.HasProp("Stack") && err.Stack
        try FileAppend(err.Stack "`n", TEST_LOG)
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
#Include ..\api\CurlBuilder.ahk
#Include ..\api\ProviderResolver.ahk
#Include ..\api\ResponseParser.ahk
#Include ..\api\LLMRequestBuilder.ahk
#Include ..\api\SSEParser.ahk
#Include ..\api\ApiLogger.ahk
#Include ..\api\CostCalculator.ahk
#Include ..\chat\ChatDB.ahk
#Include ..\chat\ChatUtils.ahk
#Include ..\chat\StreamHandler.ahk
#Include ..\chat\ChatCallbacks_Message.ahk
#Include ..\chat\ChatRequestBuilder.ahk
#Include ..\ui\CustomMessages.ahk

; Include test files
#Include unit\ChatDB.test.ahk
#Include unit\LLMRequestBuilder.test.ahk
#Include unit\ChatUtils.test.ahk
#Include unit\StreamHandler.test.ahk
#Include unit\ChatRequestBuilder.test.ahk
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
    FileAppend("`n---`n", TEST_LOG)
    FileAppend(total " tests run | " totalPassed " passed | " totalFailed " failed`n", TEST_LOG)
    if failedDetails.Length > 0 {
        FileAppend("`nFAILURES:`n", TEST_LOG)
        for detail in failedDetails
            FileAppend("  " detail "`n", TEST_LOG)
    }
    ExitApp(totalFailed > 0 ? 1 : 0)
}

RunTestClass(className) {
    global __TestClasses, totalPassed, totalFailed, failedDetails, TEST_LOG
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
                FileAppend("[PASS] " className "." methodName "`n", TEST_LOG)
                totalPassed++
            } catch Error as err {
                FileAppend("[FAIL] " className "." methodName " — " err.Message "`n", TEST_LOG)
                totalFailed++
                failedDetails.Push(className "." methodName ": " err.Message)
            }
        }
    } catch Error as err {
        FileAppend("[FAIL] " className " (class init) — " err.Message "`n", TEST_LOG)
        totalFailed++
    }
}

; Verify MsgBox override is active
if MsgBox("test") != "OK" {
    FileAppend("[CRITICAL] test_config.ahk MsgBox override not active! Tests aborted.`n", TEST_LOG)
    ExitApp(1)
}

RunAllTests()
