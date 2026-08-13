@echo off
REM Double-click this file to start BiomiX with a simple graphical setup window.
REM
REM IMPORTANT: this file (BiomiX_Start.bat) and BiomiX_Start.ps1 must be kept
REM together in the same folder.

set SCRIPT_DIR=%~dp0
set PS1_PATH=%SCRIPT_DIR%BiomiX_Start.ps1

if not exist "%PS1_PATH%" (
    echo.
    echo [ERROR] Could not find BiomiX_Start.ps1
    echo Expected it here: %PS1_PATH%
    echo.
    echo Make sure BiomiX_Start.bat and BiomiX_Start.ps1 are both in the same folder.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" -ScriptDir "%SCRIPT_DIR%"

echo.
echo ============================================
echo  BiomiX window closed / process ended.
echo  If you saw an error above, please copy it
echo  and share it so it can be fixed.
echo ============================================
pause
