@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard OpenCode System Unbootstrap

set "ROOT=%~dp0"
set "OWNER=%ROOT%tooling\profiles\windows\Install-AgentSwitchboardOpenCode.ps1"

if not exist "%OWNER%" (
  echo [FAIL] Canonical OpenCode lifecycle owner is missing:
  echo        %OWNER%
  endlocal & exit /b 2
)

where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo [FAIL] PowerShell 7 is required.
  endlocal & exit /b 127
)

rem Remove is ownership-driven and does not fetch, pull, reset, clean, or rewrite Git state.
rem The lifecycle owner may reverse only machine mutations recorded as AgentSwitchboard-owned.
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%OWNER%" -Mode Remove
set "RESULT=%ERRORLEVEL%"

if "%RESULT%"=="0" (
  echo [PASS] OpenCode AgentSwitchboard-owned machine changes were reversed or were already absent.
  echo [INFO] User credentials, sessions, project state, and unrelated OpenCode configuration were not targeted.
) else (
  echo [FAIL] OpenCode unbootstrap exited with code %RESULT%.
  echo [INFO] Inspect the emitted lifecycle receipt before changing machine state manually.
)

endlocal & exit /b %RESULT%
