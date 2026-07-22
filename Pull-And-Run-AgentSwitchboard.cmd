@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Technician Pull and Run

set "REPO_URL=https://github.com/EndeavorEverlasting/AgentSwitchboard.git"
set "DEFAULT_REPO=%USERPROFILE%\Desktop\dev\AgentSwitchboard"

if /I "%~1"=="--repo-ready" goto :repo_ready

set "MODE=%~1"
if not defined MODE set "MODE=shell"
if /I not "%MODE%"=="shell" if /I not "%MODE%"=="agy" if /I not "%MODE%"=="opencode" if /I not "%MODE%"=="setup" (
  echo [FAIL] Unsupported mode: %MODE%
  echo Usage: %~nx0 [shell^|agy^|opencode^|setup] [repo-path] [git-ref]
  set "RESULT=2"
  goto :finish
)

set "REPO_ROOT=%~2"
if not defined REPO_ROOT set "REPO_ROOT=%DEFAULT_REPO%"
for %%I in ("%REPO_ROOT%") do set "REPO_ROOT=%%~fI"

set "GIT_REF=%~3"
if not defined GIT_REF set "GIT_REF=main"

where git.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Git for Windows was not found on PATH.
  echo Install Git, reopen Command Prompt, and run this CMD again.
  set "RESULT=10"
  goto :finish
)

echo ============================================================
echo  AgentSwitchboard Technician Pull and Run
echo ============================================================
echo Mode:      %MODE%
echo Repo:      %REPO_ROOT%
echo Git ref:   %GIT_REF%
echo.

if not exist "%REPO_ROOT%\.git" goto :clone_repo

set "ORIGIN_URL="
for /f "usebackq delims=" %%I in (`git -C "%REPO_ROOT%" remote get-url origin 2^>nul`) do set "ORIGIN_URL=%%I"
if not defined ORIGIN_URL (
  echo [FAIL] The existing checkout has no readable origin remote.
  set "RESULT=11"
  goto :finish
)

if /I "%ORIGIN_URL%"=="https://github.com/EndeavorEverlasting/AgentSwitchboard.git" goto :origin_ok
if /I "%ORIGIN_URL%"=="https://github.com/EndeavorEverlasting/AgentSwitchboard" goto :origin_ok
if /I "%ORIGIN_URL%"=="git@github.com:EndeavorEverlasting/AgentSwitchboard.git" goto :origin_ok

echo [FAIL] Existing checkout points to an unexpected origin:
echo        %ORIGIN_URL%
echo Expected: %REPO_URL%
set "RESULT=12"
goto :finish

:origin_ok
set "DIRTY="
for /f "usebackq delims=" %%I in (`git -C "%REPO_ROOT%" status --porcelain=v1 --untracked-files=normal 2^>nul`) do set "DIRTY=1"
if defined DIRTY (
  echo [FAIL] The checkout contains local changes.
  echo Nothing was stashed, reset, cleaned, or overwritten.
  echo Resolve or preserve the work, then run this CMD again.
  set "RESULT=13"
  goto :finish
)

set "CURRENT_BRANCH="
for /f "usebackq delims=" %%I in (`git -C "%REPO_ROOT%" symbolic-ref --quiet --short HEAD 2^>nul`) do set "CURRENT_BRANCH=%%I"
if not defined CURRENT_BRANCH (
  echo [FAIL] The checkout is detached. Attach it to a branch before setup.
  set "RESULT=14"
  goto :finish
)

echo [INFO] Fetching current repository state...
git -C "%REPO_ROOT%" fetch --all --prune
if errorlevel 1 (
  set "RESULT=15"
  goto :finish
)

if /I "%CURRENT_BRANCH%"=="%GIT_REF%" goto :branch_ready
git -C "%REPO_ROOT%" show-ref --verify --quiet "refs/heads/%GIT_REF%"
if errorlevel 1 (
  git -C "%REPO_ROOT%" switch --track -c "%GIT_REF%" "origin/%GIT_REF%"
) else (
  git -C "%REPO_ROOT%" switch "%GIT_REF%"
)
if errorlevel 1 (
  echo [FAIL] Could not switch safely to %GIT_REF%.
  set "RESULT=16"
  goto :finish
)

:branch_ready
echo [INFO] Fast-forwarding %GIT_REF%...
git -C "%REPO_ROOT%" pull --ff-only origin "%GIT_REF%"
if errorlevel 1 (
  echo [FAIL] Fast-forward-only pull was rejected.
  echo The CMD did not rewrite history or discard local work.
  set "RESULT=17"
  goto :finish
)
goto :run_repo_copy

:clone_repo
if exist "%REPO_ROOT%" (
  dir /b "%REPO_ROOT%" 2>nul | findstr . >nul
  if not errorlevel 1 (
    echo [FAIL] The target path exists but is not an empty Git checkout:
    echo        %REPO_ROOT%
    set "RESULT=18"
    goto :finish
  )
)
for %%I in ("%REPO_ROOT%\..") do set "REPO_PARENT=%%~fI"
if not exist "%REPO_PARENT%" mkdir "%REPO_PARENT%"
if errorlevel 1 (
  set "RESULT=19"
  goto :finish
)

echo [INFO] Cloning AgentSwitchboard...
git clone --branch "%GIT_REF%" --single-branch "%REPO_URL%" "%REPO_ROOT%"
if errorlevel 1 (
  set "RESULT=20"
  goto :finish
)

:run_repo_copy
if not exist "%REPO_ROOT%\Pull-And-Run-AgentSwitchboard.cmd" (
  echo [FAIL] The selected ref does not contain the technician CMD.
  echo Ref: %GIT_REF%
  set "RESULT=21"
  goto :finish
)

echo [INFO] Handing off to the freshly pulled repository copy...
call "%REPO_ROOT%\Pull-And-Run-AgentSwitchboard.cmd" --repo-ready "%MODE%" "%REPO_ROOT%" "%GIT_REF%"
set "RESULT=%ERRORLEVEL%"
goto :finish

:repo_ready
set "MODE=%~2"
set "REPO_ROOT=%~3"
set "GIT_REF=%~4"
cd /d "%REPO_ROOT%"
if errorlevel 1 (
  echo [FAIL] Could not enter repository: %REPO_ROOT%
  set "RESULT=22"
  goto :finish
)

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) was not found on PATH.
  echo Install PowerShell 7, reopen Command Prompt, and run this CMD again.
  set "RESULT=23"
  goto :finish
)

set "SETUP_SCRIPT=%REPO_ROOT%\tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1"
if not exist "%SETUP_SCRIPT%" (
  echo [FAIL] Repository setup script is missing:
  echo        %SETUP_SCRIPT%
  set "RESULT=24"
  goto :finish
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SETUP_SCRIPT%" -Mode "%MODE%" -RepoRoot "%REPO_ROOT%" -GitRef "%GIT_REF%"
set "RESULT=%ERRORLEVEL%"

:finish
echo.
if "%RESULT%"=="0" (
  echo [PASS] AgentSwitchboard technician operation completed.
) else (
  echo [FAIL] AgentSwitchboard technician operation exited with code %RESULT%.
)
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)
endlocal & exit /b %RESULT%
