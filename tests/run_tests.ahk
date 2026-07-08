; ======================================================
; run_tests.ahk — Test runner entry point
;
; Usage: AutoHotkey64.exe ai-automation/tests/run_tests.ahk
; ======================================================

#Requires AutoHotkey v2.0.18+
#ErrorStdOut
#SingleInstance Off
#NoTrayIcon

; -----------------------------------------------------------
; Output file for test results
; -----------------------------------------------------------
global TEST_LOG := A_Temp "\test_results.txt"
try FileDelete(TEST_LOG)

; -----------------------------------------------------------
; Global error handler
; -----------------------------------------------------------
OnError(TestErrorHandler, -1)
TestErrorHandler(err, mode) {
    global TEST_LOG
    try FileAppend("[RUNTIME ERROR] " err.Message "`n", TEST_LOG)
    if err.HasProp("Stack") && err.Stack
        try FileAppend(err.Stack "`n", TEST_LOG)
    ExitApp(1)
}

; -----------------------------------------------------------
; Override MsgBox/ExitApp BEFORE Config loads UserConfig
; -----------------------------------------------------------
MsgBox(text, title := "", options := "") {
    FileAppend("[MSGBOX] " title ": " text "`n", "*")
    return "OK"
}
ExitApp(ExitCode := 0) {
    FileAppend("[EXITAPP suppressed in test mode]`n", "*")
}

global testMode := true

; -----------------------------------------------------------
; Mock globals needed by production modules loaded via Config
; (Must be set BEFORE Config.ahk so they override vendor libs)
; -----------------------------------------------------------
global responseWindow := {PostWebMessageAsJSON: (*) => ""}

; -----------------------------------------------------------
; Load production config
; -----------------------------------------------------------
#Include ..\lib\Config.ahk

; -----------------------------------------------------------
; Override UserConfig globals with test values (after Config)
; -----------------------------------------------------------
#Include test_config.ahk

; -----------------------------------------------------------
; Include ChatWindow-specific modules not in Config.ahk
; (ChatUtils, StreamHandler, and callbacks are loaded by ChatWindow.ahk
; but we need them directly in test mode)
; -----------------------------------------------------------
#Include ..\chat\ChatUtils.ahk
#Include ..\chat\streaming\StreamHandler.ahk
#Include ..\chat\callbacks\Message.ahk
#Include ..\chat\ChatRequestBuilder.ahk

; -----------------------------------------------------------
; Test registration
; -----------------------------------------------------------
global __TestClasses := []

RegisterTestClass(className) {
    global __TestClasses
    __TestClasses.Push(className)
}

#Include unit\ChatDB.test.ahk
#Include unit\LLMRequestBuilder.test.ahk
#Include unit\ChatUtils.test.ahk
#Include unit\StreamHandler.test.ahk
#Include unit\ChatRequestBuilder.test.ahk
#Include unit\CustomMessages.test.ahk
#Include integration\ChatFlow.test.ahk
#Include integration\BranchFlow.test.ahk

; -----------------------------------------------------------
; Test runner
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
        proto := %className%.Prototype
        for methodName in proto.OwnProps() {
            if SubStr(methodName, 1, 1) = "_"
                continue
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

if MsgBox("test") != "OK" {
    FileAppend("[CRITICAL] MsgBox override not active! Tests aborted.`n", TEST_LOG)
    ExitApp(1)
}

RunAllTests()
