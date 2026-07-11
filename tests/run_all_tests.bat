@echo off
echo ============================================
echo  LLM AutoHotkey Assistant — Full Test Suite
echo ============================================
echo.

echo [1/2] Running AHK tests...
"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" "tests\run_ahk_tests.ahk"
type "%TEMP%\test_results.txt"
if %ERRORLEVEL% NEQ 0 (
    echo [FAIL] AHK tests failed
    set AHK_FAIL=1
) else (
    echo [PASS] AHK tests passed
)

echo.
echo [2/2] Running JS tests...
call tests\run_js_tests.bat
if %ERRORLEVEL% NEQ 0 (
    echo [FAIL] JS tests failed
    set JS_FAIL=1
) else (
    echo [PASS] JS tests passed
)

echo.
echo ============================================
if "%AHK_FAIL%"=="1" echo AHK tests: FAILED
if "%JS_FAIL%"=="1"  echo JS tests:  FAILED
if "%AHK_FAIL%"=="" if "%JS_FAIL%"=="" echo All tests passed!
echo ============================================
