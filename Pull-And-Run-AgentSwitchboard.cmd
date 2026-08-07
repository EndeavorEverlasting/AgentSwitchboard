@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Technician Pull and Run

set "REPO_URL=https://github.com/EndeavorEverlasting/AgentSwitchboard.git"
set "DEFAULT_REPO=%USERPROFILE%\dev\AgentSwitchBoard-Live"
set "TOOLCHAIN_PREFLIGHT_REF=19c671837c51c2893e9eade92c340bb67e970cee"
set "EXPECTED_TOOLCHAIN_PREFLIGHT_BLOB=7110b9c6141971d93987cdb07f1ffc397e2e9f2e"
set "TOOLCHAIN_PREFLIGHT_NAME=Test-WindowsToolchainLaunch.ps1"
set "TOOLCHAIN_PREFLIGHT_PATH=%TEMP%\AgentSwitchboard-%TOOLCHAIN_PREFLIGHT_NAME%"
set "GIT_QUERY_ROOT="

if /I "%~1"=="--repo-ready" goto :repo_ready

set "MODE=%~1"
if not defined MODE set "MODE=shell"
if /I not "%MODE%"=="shell" if /I not "%MODE%"=="agy" if /I not "%MODE%"=="opencode" if /I not "%MODE%"=="setup" if /I not "%MODE%"=="hermes" if /I not "%MODE%"=="acquire" (
  echo [FAIL] Unsupported mode: %MODE%
  echo Usage: %~nx0 [shell^|agy^|opencode^|setup^|hermes^|acquire] [repo-path] [git-ref]
  set "RESULT=2"
  goto :finish
)

set "REPO_ROOT=%~2"
if not defined REPO_ROOT set "REPO_ROOT=%DEFAULT_REPO%"
for %%I in ("%REPO_ROOT%") do set "REPO_ROOT=%%~fI"

set "GIT_REF=%~3"
if not defined GIT_REF set "GIT_REF=main"

call :resolve_git
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" goto :finish

if /I not "%MODE%"=="acquire" goto :require_pwsh
goto :after_pwsh_gate
:require_pwsh
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) was not found on PATH.
  echo Install PowerShell 7, reopen Command Prompt, and run this CMD again.
  set "RESULT=23"
  goto :finish
)
:after_pwsh_gate

echo ============================================================
echo  AgentSwitchboard Technician Pull and Run
echo ============================================================
echo Mode:      %MODE%
echo Repo:      %REPO_ROOT%
echo Git ref:   %GIT_REF%
echo Git exe:   %AGENT_SWITCHBOARD_GIT_EXE%
echo.

set "GIT_QUERY_ROOT=%TEMP%\AgentSwitchboard-git-query-%RANDOM%-%RANDOM%"
if not exist "%GIT_QUERY_ROOT%" mkdir "%GIT_QUERY_ROOT%" >nul 2>&1
if not exist "%GIT_QUERY_ROOT%" (
  echo [FAIL] Could not create temporary Git query directory:
  echo        %GIT_QUERY_ROOT%
  set "RESULT=34"
  goto :finish
)

if not exist "%REPO_ROOT%\.git" goto :clone_repo

set "ORIGIN_URL="
"%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" remote get-url origin >"%GIT_QUERY_ROOT%\origin.txt" 2>nul
if errorlevel 1 (
  echo [FAIL] The existing checkout has no readable origin remote.
  set "RESULT=11"
  goto :finish
)
set /p "ORIGIN_URL="<"%GIT_QUERY_ROOT%\origin.txt"
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
"%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" status --porcelain=v1 --untracked-files=normal >"%GIT_QUERY_ROOT%\status.txt" 2>nul
if errorlevel 1 (
  echo [FAIL] Could not read repository status with the proved Git executable.
  set "RESULT=28"
  goto :finish
)
set "DIRTY="
for %%I in ("%GIT_QUERY_ROOT%\status.txt") do if %%~zI GTR 0 set "DIRTY=1"
if defined DIRTY (
  echo [FAIL] The checkout contains local changes.
  echo Nothing was stashed, reset, cleaned, or overwritten.
  echo Resolve or preserve the work, then run this CMD again.
  set "RESULT=13"
  goto :finish
)

"%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" symbolic-ref --quiet --short HEAD >"%GIT_QUERY_ROOT%\branch.txt" 2>nul
if errorlevel 1 (
  echo [FAIL] The checkout is detached. Attach it to a branch before setup.
  set "RESULT=14"
  goto :finish
)
set "CURRENT_BRANCH="
set /p "CURRENT_BRANCH="<"%GIT_QUERY_ROOT%\branch.txt"
if not defined CURRENT_BRANCH (
  echo [FAIL] The checkout is detached. Attach it to a branch before setup.
  set "RESULT=14"
  goto :finish
)

echo [INFO] Fetching verified origin state...
"%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" fetch origin --prune
if errorlevel 1 (
  set "RESULT=15"
  goto :finish
)

if /I "%CURRENT_BRANCH%"=="%GIT_REF%" goto :branch_ready
"%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" show-ref --verify --quiet "refs/heads/%GIT_REF%"
if errorlevel 1 (
  "%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" switch --track -c "%GIT_REF%" "origin/%GIT_REF%"
) else (
  "%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" switch "%GIT_REF%"
)
if errorlevel 1 (
  echo [FAIL] Could not switch safely to %GIT_REF%.
  set "RESULT=16"
  goto :finish
)

:branch_ready
echo [INFO] Fast-forwarding %GIT_REF%...
"%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" pull --ff-only origin "%GIT_REF%"
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

echo [INFO] Cloning AgentSwitchboard with the proved Git executable...
"%AGENT_SWITCHBOARD_GIT_EXE%" clone --branch "%GIT_REF%" --single-branch "%REPO_URL%" "%REPO_ROOT%"
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
call :resolve_git
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" goto :finish
cd /d "%REPO_ROOT%"
if errorlevel 1 (
  echo [FAIL] Could not enter repository: %REPO_ROOT%
  set "RESULT=22"
  goto :finish
)

if /I "%MODE%"=="acquire" (
  echo [PASS] Repository acquisition completed without requiring PowerShell 7; concrete Git launch proof passed.
  echo [INFO] Git executable: %AGENT_SWITCHBOARD_GIT_EXE%
  echo [INFO] Workstation setup is intentionally deferred.
  set "RESULT=0"
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
goto :finish

:resolve_git
where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Windows PowerShell was not found.
  echo Repository acquisition cannot prove a concrete Git executable without it.
  exit /b 9
)
where curl.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] curl.exe was not found.
  echo Repository acquisition cannot retrieve the immutable Git-launch preflight without it.
  exit /b 10
)

set "TOOLCHAIN_PREFLIGHT_URL=https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/%TOOLCHAIN_PREFLIGHT_REF%/scripts/%TOOLCHAIN_PREFLIGHT_NAME%"
echo [INFO] Downloading immutable Git-launch preflight %TOOLCHAIN_PREFLIGHT_REF%...
curl.exe -fL "%TOOLCHAIN_PREFLIGHT_URL%" -o "%TOOLCHAIN_PREFLIGHT_PATH%"
if errorlevel 1 (
  echo [FAIL] Could not download the immutable Git-launch preflight.
  exit /b 25
)

set "AS_TOOLCHAIN_PREFLIGHT_PATH=%TOOLCHAIN_PREFLIGHT_PATH%"
set "ACTUAL_TOOLCHAIN_PREFLIGHT_BLOB="
for /f "usebackq delims=" %%H in (`powershell.exe -NoLogo -NoProfile -Command "$p=$env:AS_TOOLCHAIN_PREFLIGHT_PATH; $b=[IO.File]::ReadAllBytes($p); $prefix=[Text.Encoding]::ASCII.GetBytes(('blob {0}' -f $b.Length)+[char]0); $all=New-Object byte[] ($prefix.Length+$b.Length); [Array]::Copy($prefix,0,$all,0,$prefix.Length); [Array]::Copy($b,0,$all,$prefix.Length,$b.Length); ([BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash($all))).Replace('-','').ToLowerInvariant()"`) do set "ACTUAL_TOOLCHAIN_PREFLIGHT_BLOB=%%H"
if not defined ACTUAL_TOOLCHAIN_PREFLIGHT_BLOB (
  echo [FAIL] Could not calculate the immutable Git-launch preflight identity.
  exit /b 26
)
if /I not "%ACTUAL_TOOLCHAIN_PREFLIGHT_BLOB%"=="%EXPECTED_TOOLCHAIN_PREFLIGHT_BLOB%" (
  echo [FAIL] Immutable Git-launch preflight identity mismatch.
  echo Expected: %EXPECTED_TOOLCHAIN_PREFLIGHT_BLOB%
  echo Actual:   %ACTUAL_TOOLCHAIN_PREFLIGHT_BLOB%
  echo No Git executable was launched by the acquisition path.
  exit /b 27
)

echo [PASS] Immutable Git-launch preflight identity verified.
set "TOOLCHAIN_RUN_ID=acquisition-%RANDOM%-%RANDOM%"
if defined LOCALAPPDATA (
  set "TOOLCHAIN_RUN_ROOT=%LOCALAPPDATA%\AgentSwitchboard\technician-live-cert\toolchain-preflight\%TOOLCHAIN_RUN_ID%"
) else (
  set "TOOLCHAIN_RUN_ROOT=%TEMP%\AgentSwitchboard\technician-live-cert\toolchain-preflight\%TOOLCHAIN_RUN_ID%"
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%TOOLCHAIN_PREFLIGHT_PATH%" -OutputRoot "%TOOLCHAIN_RUN_ROOT%"
set "PREFLIGHT_EXIT=%ERRORLEVEL%"
if not "%PREFLIGHT_EXIT%"=="0" (
  echo [BLOCKED] Git executable launch proof failed with exit code %PREFLIGHT_EXIT%.
  echo [BLOCKED] Evidence: %TOOLCHAIN_RUN_ROOT%\windows-toolchain-launch-preflight.json
  echo [BLOCKED] No fetch, pull, switch, status, origin lookup, or clone was attempted.
  exit /b %PREFLIGHT_EXIT%
)

set "TOOLCHAIN_JSON=%TOOLCHAIN_RUN_ROOT%\windows-toolchain-launch-preflight.json"
if not exist "%TOOLCHAIN_JSON%" (
  echo [FAIL] Git-launch preflight passed without its canonical JSON artifact:
  echo        %TOOLCHAIN_JSON%
  exit /b 32
)
set "AS_TOOLCHAIN_JSON=%TOOLCHAIN_JSON%"
set "AGENT_SWITCHBOARD_GIT_EXE="
for /f "usebackq delims=" %%I in (`powershell.exe -NoLogo -NoProfile -Command "$r=Get-Content -LiteralPath $env:AS_TOOLCHAIN_JSON -Raw | ConvertFrom-Json; if($r.status -ne 'passed' -or [string]::IsNullOrWhiteSpace([string]$r.selectedGit)){exit 31}; [Console]::Out.WriteLine([string]$r.selectedGit)"`) do set "AGENT_SWITCHBOARD_GIT_EXE=%%I"
if not defined AGENT_SWITCHBOARD_GIT_EXE (
  echo [FAIL] Git-launch preflight did not yield a selected executable.
  echo [FAIL] Evidence: %TOOLCHAIN_JSON%
  exit /b 33
)
if not exist "%AGENT_SWITCHBOARD_GIT_EXE%" (
  echo [FAIL] Selected Git executable no longer exists:
  echo        %AGENT_SWITCHBOARD_GIT_EXE%
  exit /b 33
)

echo [PASS] Concrete Git executable proved: %AGENT_SWITCHBOARD_GIT_EXE%
echo [INFO] Toolchain evidence: %TOOLCHAIN_JSON%
exit /b 0

:finish
if defined GIT_QUERY_ROOT if exist "%GIT_QUERY_ROOT%" rmdir /s /q "%GIT_QUERY_ROOT%" >nul 2>&1
echo.
if "%RESULT%"=="0" (
  echo [PASS] AgentSwitchboard technician operation completed.
  if /I not "%MODE%"=="acquire" echo [INFO] Open a new PowerShell window to use: wezterm, tmux, agy, and opencode.
) else (
  echo [FAIL] AgentSwitchboard technician operation exited with code %RESULT%.
)
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)
endlocal & exit /b %RESULT%
