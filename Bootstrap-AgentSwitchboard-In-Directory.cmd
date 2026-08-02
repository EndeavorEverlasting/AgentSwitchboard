@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Directory Bootstrap

set "WORKSPACE_ROOT=%~1"
set "REPO_LEAF=%~2"
if not defined REPO_LEAF set "REPO_LEAF=AgentSwitchBoard-Live"

if not defined WORKSPACE_ROOT (
  echo [FAIL] A workspace directory is required.
  echo Usage: %~nx0 "C:\path\to\Dev" [repo-folder-name]
  echo Example: %~nx0 "C:\Users\Example\Desktop\Dev"
  exit /b 2
)

for %%I in ("%WORKSPACE_ROOT%") do set "WORKSPACE_ROOT=%%~fI"
set "REPO_ROOT=%WORKSPACE_ROOT%\%REPO_LEAF%"
set "BOOTSTRAP_URL=https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/main/AgentSwitchboard-Technician-Bootstrap.cmd"
set "BOOTSTRAP_PATH=%TEMP%\AgentSwitchboard-Technician-Bootstrap.cmd"

if not exist "%WORKSPACE_ROOT%" mkdir "%WORKSPACE_ROOT%"
if errorlevel 1 (
  echo [FAIL] Could not create workspace directory:
  echo        %WORKSPACE_ROOT%
  exit /b 3
)

where curl.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] curl.exe was not found.
  exit /b 10
)

echo ============================================================
echo  AgentSwitchboard Directory Bootstrap
echo ============================================================
echo Workspace:  %WORKSPACE_ROOT%
echo Repository: %REPO_ROOT%
echo.
echo [INFO] Downloading the repository-owned technician bootstrap...
curl.exe -fL "%BOOTSTRAP_URL%" -o "%BOOTSTRAP_PATH%"
if errorlevel 1 (
  echo [FAIL] Could not download AgentSwitchboard-Technician-Bootstrap.cmd.
  exit /b 11
)

call "%BOOTSTRAP_PATH%" "%REPO_ROOT%" main
set "RESULT=%ERRORLEVEL%"
if "%RESULT%"=="0" (
  echo [PASS] AgentSwitchboard completed for:
  echo        %REPO_ROOT%
) else (
  echo [FAIL] AgentSwitchboard directory bootstrap exited with code %RESULT%.
)
exit /b %RESULT%
