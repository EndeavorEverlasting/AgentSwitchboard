@echo off
setlocal EnableExtensions DisableDelayedExpansion

cd /d "%~dp0"
title AgentSwitchboard tmux + GNHF workstation setup

set "SETUP_PS1=%~dp0tooling\wsl\Start-TmuxGnhfWorkspaceSetup.ps1"
set "MODE=Guided"

if /I "%~1"=="plan" set "MODE=Plan"
if /I "%~1"=="apply" set "MODE=Apply"

if not exist "%SETUP_PS1%" (
  echo [FAIL] Setup entrypoint is missing:
  echo        %SETUP_PS1%
  echo.
  echo Re-clone or repair the AgentSwitchboard checkout before continuing.
  set "RESULT=2"
  goto :finish
)

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) is required but was not found on PATH.
  echo Install PowerShell 7, reopen this file, and try again.
  set "RESULT=2"
  goto :finish
)

echo ============================================================
echo  AgentSwitchboard persistent tmux + GNHF workstation setup
echo ============================================================
echo.
echo Mode: %MODE%
echo This launcher writes local logs and never authenticates providers,
echo stores tokens, pushes Git branches, or unregisters WSL.
echo.

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SETUP_PS1%" -Mode "%MODE%"
set "RESULT=%ERRORLEVEL%"

:finish
echo.
if "%RESULT%"=="0" (
  echo [PASS] The requested setup operation completed.
) else if "%RESULT%"=="10" (
  echo [STOP] Setup was cancelled before apply.
) else if "%RESULT%"=="30" (
  echo [WAIT] A reboot or WSL first-run step is required.
  echo        Complete it, then double-click this same CMD again.
) else (
  echo [FAIL] Setup did not complete. Exit code: %RESULT%
  echo        The setup window above contains the exact local log path.
)

if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)

exit /b %RESULT%
