@echo off
echo.
echo Refresh-Models -- Model metadata pipeline
echo ==========================================
echo.
echo Applies corrections from models-corrections.json
echo then generates default-settings\DefaultSettings.ahk.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Refresh-Models.ps1" -NoPause
pause
