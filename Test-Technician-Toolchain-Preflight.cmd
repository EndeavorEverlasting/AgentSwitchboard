@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Windows Toolchain Preflight
set "ERRORLEVEL="
set "RESULT=0"
where pwsh.exe >nul 2>&1
if not errorlevel 1 goto :run_pwsh
where powershell.exe >nul 2>&1
if not errorlevel 1 goto :run_windows_powershell
echo [FAIL] Neither PowerShell 7 ^(pwsh.exe^) nor Windows PowerShell ^(powershell.exe^) was found on PATH.
set "RESULT=23"
goto :finish

:run_pwsh
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-WindowsToolchainLaunch.ps1"
set "RESULT=%ERRORLEVEL%"
goto :finish

:run_windows_powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-WindowsToolchainLaunch.ps1"
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
