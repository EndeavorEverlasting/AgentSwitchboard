@echo off
setlocal
title AgentSwitchboard
pushd "%~dp0"

where pwsh >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh^) was not found on PATH.
  echo Install PowerShell 7, reopen this launcher, and try again.
  set "_code=1"
  goto :finish
)

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\gnhf\Get-AgentSwitchboardStartupReport.ps1"
set "_code=%ERRORLEVEL%"
if not "%_code%"=="0" goto :finish

if "%~1"=="" (
  echo.
  echo [READY] Startup orientation is complete.
  echo Pass bounded sprint arguments to this launcher when repository work is intended.
  goto :finish
)

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\gnhf\Start-AgentSwitchboard.ps1" %*
set "_code=%ERRORLEVEL%"

:finish
popd
endlocal & exit /b %_code%
