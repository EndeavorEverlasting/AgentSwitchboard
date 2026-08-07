@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Windows Toolchain Preflight
set "ERRORLEVEL="
set "RESULT=0"
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) was not found on PATH.
  set "RESULT=23"
  goto :finish
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-WindowsToolchainLaunch.ps1"
set "RESULT=%ERRORLEVEL%"
:finish
echo.
if "%RESULT%"=="0" (
  echo [PASS] Windows toolchain launch preflight completed.
) else (
  echo [FAIL] Windows toolchain launch preflight exited with code %RESULT%.
)
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)
endlocal & exit /b %RESULT%
