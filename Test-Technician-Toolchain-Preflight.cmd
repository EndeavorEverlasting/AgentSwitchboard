@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Windows Toolchain Preflight
set "ERRORLEVEL="
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) was not found on PATH.
  set "_rc=23"
  goto :finish
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-WindowsToolchainLaunch.ps1"
set "_rc=%ERRORLEVEL%"
:finish
echo.
if "%_rc%"=="0" (
  echo [PASS] Windows toolchain launch preflight completed.
) else (
  echo [FAIL] Windows toolchain launch preflight exited with code %_rc%.
)
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)
endlocal & exit /b %_rc%
