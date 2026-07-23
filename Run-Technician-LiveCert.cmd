@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Technician Live-Cert Full-Run Orchestrator
cd /d "%~dp0"

set "TARGET_SCRIPT=%~dp0tooling\profiles\windows\technician-live-cert\Invoke-TechnicianLiveCert.ps1"

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) is required but was not found on PATH.
  exit /b 2
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%TARGET_SCRIPT%" -RepoRoot "%~dp0" %*
set "EXITCODE=%ERRORLEVEL%"

if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)

exit /b %EXITCODE%
