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
  echo [OPENCODE] Copy the bounded sprint prompt, then double-click Start-AgentSwitchboard-OpenCode.cmd.
  echo            To target another repository without rebuilding a command, drag its folder onto that CMD file.
  echo [ADVANCED] Other agents and automation may still pass bounded sprint arguments to AgentSwitchboard.cmd.
  goto :finish
)

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\gnhf\Start-AgentSwitchboard.ps1" %*
set "_code=%ERRORLEVEL%"

:finish
popd
endlocal & exit /b %_code%
