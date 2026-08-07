@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard tmux live proof

set "RESULT=0"
set "PWSH="
where pwsh.exe >nul 2>&1
if not errorlevel 1 for /f "delims=" %%I in ('where pwsh.exe') do if not defined PWSH set "PWSH=%%I"

if not defined PWSH (
  where winget.exe >nul 2>&1
  if errorlevel 1 (
    echo [FAIL] PowerShell 7 is missing and WinGet is unavailable.
    echo        Install PowerShell 7, then rerun %~nx0.
    set "RESULT=23"
    goto :finish
  )
  echo [INSTALL] PowerShell 7 is missing; installing Microsoft.PowerShell with WinGet.
  winget.exe install --id Microsoft.PowerShell --exact --source winget --silent --accept-source-agreements --accept-package-agreements
  if errorlevel 1 (
    echo [FAIL] WinGet could not install PowerShell 7.
    set "RESULT=24"
    goto :finish
  )
  if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
)

if not defined PWSH (
  echo [FAIL] PowerShell 7 installation completed but pwsh.exe is not resolvable.
  set "RESULT=25"
  goto :finish
)

set "SCRIPT=%~dp0Open-AgentSwitchboard-Tmux.ps1"
if not exist "%SCRIPT%" (
  echo [FAIL] Repository-owned tmux launcher is missing:
  echo        %SCRIPT%
  set "RESULT=26"
  goto :finish
)

"%PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RESULT=%ERRORLEVEL%"

:finish
if "%RESULT%"=="0" (
  echo [PASS] AgentSwitchboard tmux live-proof launcher completed.
) else (
  echo [FAIL] AgentSwitchboard tmux live-proof launcher exited with code %RESULT%.
)
endlocal & exit /b %RESULT%
