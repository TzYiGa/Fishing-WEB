@echo off
REM Launches deploy_firebase_hosting.ps1 (recommended on Windows).

set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%deploy_firebase_hosting.ps1"

echo.
pause
