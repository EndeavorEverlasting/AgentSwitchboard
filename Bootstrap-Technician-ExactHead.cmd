@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ERRORLEVEL="
title AgentSwitchboard Stale-Checkout Exact-Head Bootstrap

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) was not found on PATH.
  exit /b 23
)

set "SCRIPT=%~dp0scripts\Invoke-StaleCheckoutExactHeadBootstrap.ps1"
if not exist "%SCRIPT%" (
  echo [FAIL] Bootstrap implementation is missing:
  echo        %SCRIPT%
  exit /b 24
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RESULT=%ERRORLEVEL%"
endlocal & exit /b %RESULT%
