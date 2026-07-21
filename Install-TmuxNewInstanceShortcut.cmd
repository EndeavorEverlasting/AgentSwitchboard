@echo off
setlocal EnableExtensions DisableDelayedExpansion

cd /d "%~dp0"
title AgentSwitchboard tmux new-instance shortcut installer

set "INSTALLER=%~dp0tooling\profiles\windows\Install-TmuxNewInstanceShortcut.ps1"
set "MODE=Apply"

if /I "%~1"=="plan" set "MODE=Plan"
if /I "%~1"=="apply" set "MODE=Apply"

if not exist "%INSTALLER%" (
  echo [FAIL] Installer entrypoint is missing:
  echo        %INSTALLER%
  set "RESULT=2"
  goto :finish
)

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) is required but was not found on PATH.
  set "RESULT=2"
  goto :finish
)

echo ============================================================
echo  AgentSwitchboard tmux new-instance desktop shortcut
echo ============================================================
echo.
echo Mode: %MODE%
echo The shortcut delegates to the canonical Windows Profile launcher.
echo Each click requests one unique tmux session and one new WezTerm process.
echo.

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" -Mode "%MODE%"
set "RESULT=%ERRORLEVEL%"

:finish
echo.
if "%RESULT%"=="0" (
  echo [PASS] Shortcut operation completed.
) else if "%RESULT%"=="20" (
  echo [PLAN] No workstation files were changed.
) else (
  echo [FAIL] Shortcut operation did not complete. Exit code: %RESULT%
)

if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)

exit /b %RESULT%
