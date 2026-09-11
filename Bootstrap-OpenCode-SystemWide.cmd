@echo off
setlocal EnableExtensions EnableDelayedExpansion
title AgentSwitchboard OpenCode System Bootstrap

rem PowerShell does not run bare .cmd names from the current directory.
rem From PowerShell inside the canonical checkout, use:
rem   .\Bootstrap-OpenCode-SystemWide.cmd
rem From cmd.exe:
rem   Bootstrap-OpenCode-SystemWide.cmd
rem Do not invent Desktop/OneDrive/Backup clone paths.

set "SCRIPT_ROOT=%~dp0"
if "%SCRIPT_ROOT:~-1%"=="\" set "SCRIPT_ROOT=%SCRIPT_ROOT:~0,-1%"

set "GIT_REF=%~1"
if not defined GIT_REF set "GIT_REF=main"

set "CANONICAL_DEFAULT=%USERPROFILE%\dev\AgentSwitchBoard-Live"
set "REPO_ROOT="
set "ROOT_SOURCE="

if defined AGENT_SWITCHBOARD_REPO (
  set "REPO_ROOT=%AGENT_SWITCHBOARD_REPO%"
  set "ROOT_SOURCE=AGENT_SWITCHBOARD_REPO"
)

if not defined REPO_ROOT if exist "%LOCALAPPDATA%\AgentSwitchboard\machine-profile\machine-profile.env.cmd" (
  call "%LOCALAPPDATA%\AgentSwitchboard\machine-profile\machine-profile.env.cmd"
  if defined AGENT_SWITCHBOARD_REPO (
    set "REPO_ROOT=%AGENT_SWITCHBOARD_REPO%"
    set "ROOT_SOURCE=machine-profile.env.cmd"
  )
)

if not defined REPO_ROOT if exist "%LOCALAPPDATA%\AgentSwitchBoard\state\repo-path.txt" (
  set /p REPO_ROOT=<"%LOCALAPPDATA%\AgentSwitchBoard\state\repo-path.txt"
  set "ROOT_SOURCE=verified-machine-binding"
)

if not defined REPO_ROOT (
  set "REPO_ROOT=%CANONICAL_DEFAULT%"
  set "ROOT_SOURCE=canonical-default"
)

for %%I in ("%REPO_ROOT%") do set "REPO_ROOT=%%~fI"
for %%I in ("%SCRIPT_ROOT%") do set "SCRIPT_ROOT=%%~fI"
for %%I in ("%CANONICAL_DEFAULT%") do set "CANONICAL_DEFAULT=%%~fI"

echo ============================================================
echo  AgentSwitchboard OpenCode system-wide bootstrap
echo ============================================================
echo Canonical development/use checkout:
echo   %CANONICAL_DEFAULT%
echo Resolved target checkout:
echo   %REPO_ROOT%
echo Resolution source: %ROOT_SOURCE%
echo Script location:
echo   %SCRIPT_ROOT%
echo.

echo %REPO_ROOT%| findstr /I /C:"\OneDrive" >nul
if not errorlevel 1 (
  echo [FAIL] Resolved repository root is under OneDrive/cloud redirection.
  echo OneDrive/Desktop/Backup copies are NONCANONICAL + PRESERVE.
  echo Develop and run from: %CANONICAL_DEFAULT%
  echo.
  echo Next command [cmd.exe]:
  echo   "%USERPROFILE%\dev\AgentSwitchBoard-Live\Bootstrap-OpenCode-SystemWide.cmd"
  echo Next command [PowerShell]:
  echo   Set-Location -LiteralPath "$env:USERPROFILE\dev\AgentSwitchBoard-Live"; .\Bootstrap-OpenCode-SystemWide.cmd
  endlocal & exit /b 31
)

echo %REPO_ROOT%| findstr /I /C:"\Desktop\" >nul
if not errorlevel 1 (
  echo [FAIL] Resolved repository root is under Desktop.
  echo Desktop copies are NONCANONICAL + PRESERVE unless explicitly bound by operator policy.
  echo Develop and run from: %CANONICAL_DEFAULT%
  endlocal & exit /b 32
)

if /I not "%SCRIPT_ROOT%"=="%REPO_ROOT%" (
  echo [FAIL] This launcher was invoked from a non-target checkout.
  echo Observed script location: %SCRIPT_ROOT%
  echo Required target checkout: %REPO_ROOT%
  echo Disposition: NONCANONICAL + PRESERVE for the observed copy; do not create another mutable clone.
  echo.
  if exist "%REPO_ROOT%\Bootstrap-OpenCode-SystemWide.cmd" (
    echo Canonical launcher exists. Re-run it from the canonical checkout.
    echo Next command [cmd.exe]:
    echo   "%REPO_ROOT%\Bootstrap-OpenCode-SystemWide.cmd" %GIT_REF%
    echo Next command [PowerShell]:
    echo   Set-Location -LiteralPath "%REPO_ROOT%"; .\Bootstrap-OpenCode-SystemWide.cmd %GIT_REF%
    endlocal & exit /b 33
  )
  echo Canonical checkout is missing or incomplete.
  echo Next command [cmd.exe] to acquire the canonical checkout, then bootstrap OpenCode:
  echo   curl.exe -fL https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/main/AgentSwitchboard-Technician-Bootstrap.cmd -o "%%TEMP%%\AgentSwitchboard-Technician-Bootstrap.cmd" ^&^& call "%%TEMP%%\AgentSwitchboard-Technician-Bootstrap.cmd"
  echo After acquisition:
  echo   "%CANONICAL_DEFAULT%\Bootstrap-OpenCode-SystemWide.cmd"
  endlocal & exit /b 34
)

if not exist "%SCRIPT_ROOT%\Pull-And-Run-AgentSwitchboard.cmd" (
  echo [FAIL] Canonical AgentSwitchboard pull-and-run entrypoint is missing.
  endlocal & exit /b 2
)

where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo [FAIL] PowerShell 7 is required.
  endlocal & exit /b 127
)

echo [INFO] PowerShell tip: use .\Bootstrap-OpenCode-SystemWide.cmd from this directory.
echo [INFO] Do not paste implementation fragments into an interactive PowerShell REPL.
echo [INFO] Invoking repository-owned installer through the canonical dispatcher.
echo.

call "%SCRIPT_ROOT%\Pull-And-Run-AgentSwitchboard.cmd" bootstrap-opencode "%SCRIPT_ROOT%" "%GIT_REF%"
set "RESULT=%ERRORLEVEL%"
endlocal & exit /b %RESULT%
