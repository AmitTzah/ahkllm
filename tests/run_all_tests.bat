@echo off
setlocal enabledelayedexpansion

echo ============================================
echo  AhkLLM - Full Test Suite
echo ============================================
echo.

set FAILED=0
set RESULTS_FILE=%TEMP%\test_results.txt

echo [1/2] Running AHK tests...
"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" "tests\run_ahk_tests.ahk"
type "%RESULTS_FILE%"
findstr /c:"RESULT: FAIL" "%RESULTS_FILE%" > nul
if !ERRORLEVEL! EQU 0 (
    echo [FAIL] AHK tests failed
    set FAILED=1
) else (
    echo [PASS] AHK tests passed
)

echo.
echo [2/2] Running JS tests...
call tests\run_js_tests.bat
set JS_EXIT=!ERRORLEVEL!
if !JS_EXIT! NEQ 0 (
    echo [FAIL] JS tests failed
    set FAILED=1
) else (
    echo [PASS] JS tests passed
)

echo.
echo ============================================
if !FAILED! EQU 1 (
    echo Some tests FAILED - check output above for details.
    exit /b 1
) else (
    echo All tests passed!
    exit /b 0
)
echo ============================================
