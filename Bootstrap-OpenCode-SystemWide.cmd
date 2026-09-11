@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard OpenCode System Bootstrap

set "ROOT=%~dp0"
set "GIT_REF=%~1"
if not defined GIT_REF set "GIT_REF=main"

if not exist "%ROOT%Pull-And-Run-AgentSwitchboard.cmd" (
  echo [FAIL] Canonical AgentSwitchboard pull-and-run entrypoint is missing.
  endlocal & exit /b 2
)

where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo [FAIL] PowerShell 7 is required.
  endlocal & exit /b 127
)

rem Invoke one repository-owned script path through the canonical dispatcher.
rem Do not paste implementation fragments into an interactive PowerShell REPL.
call "%ROOT%Pull-And-Run-AgentSwitchboard.cmd" bootstrap-opencode "%ROOT%." "%GIT_REF%"
set "RESULT=%ERRORLEVEL%"
endlocal & exit /b %RESULT%
