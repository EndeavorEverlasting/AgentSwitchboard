@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Pull Repo and Setup

set "BRANCH=feat/technician-pull-and-run-cmd"
set "REPO_ROOT=%USERPROFILE%\Desktop\dev\AgentSwitchboard"
set "BOOTSTRAP_URL=https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/%BRANCH%/Pull-And-Run-AgentSwitchboard.cmd"
set "BOOTSTRAP_PATH=%TEMP%\Pull-And-Run-AgentSwitchboard.cmd"

if not "%~1"=="" set "REPO_ROOT=%~1"
if not "%~2"=="" set "BRANCH=%~2"
set "BOOTSTRAP_URL=https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/%BRANCH%/Pull-And-Run-AgentSwitchboard.cmd"

echo ============================================================
echo  AgentSwitchboard Parent Bootstrap
echo ============================================================
echo This is the first technician command.
echo It downloads the repo bootstrap, then clones or fast-forwards:
echo   %REPO_ROOT%
echo Branch:
echo   %BRANCH%
echo.

where curl.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] curl.exe was not found.
  exit /b 10
)

curl.exe -fL "%BOOTSTRAP_URL%" -o "%BOOTSTRAP_PATH%"
if errorlevel 1 (
  echo [FAIL] Could not download the AgentSwitchboard repository bootstrap.
  exit /b 11
)

call "%BOOTSTRAP_PATH%" setup "%REPO_ROOT%" "%BRANCH%"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo [FAIL] Repository pull/setup failed with exit code %RESULT%.
  exit /b %RESULT%
)

echo.
echo [PASS] The repository was cloned or safely fast-forwarded and setup completed.
echo [NEXT] Open a new PowerShell window and run:
echo        wezterm --version
echo        tmux -V
echo        agy --version
echo        opencode --version
exit /b 0
