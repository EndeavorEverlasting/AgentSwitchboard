@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Technician Bootstrap

set "BRANCH=feat/technician-clickable-live-cert-cmds"
set "EXPECTED_PARENT_SHA256=8dea9f202eb0a3a3b5b41fda8ec6547d4cf444260e3d03a26ad76a5e855154bb"
set "DEFAULT_REPO=%USERPROFILE%\Desktop\dev\AgentSwitchboard"
set "PARENT_NAME=Pull-Repo-And-Setup-AgentSwitchboard.cmd"
set "PARENT_URL=https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/%BRANCH%/%PARENT_NAME%"
set "PARENT_TEMP=%TEMP%\AgentSwitchboard-%PARENT_NAME%"

if not "%~1"=="" set "DEFAULT_REPO=%~1"
if not "%~2"=="" set "BRANCH=%~2"
set "PARENT_URL=https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/%BRANCH%/%PARENT_NAME%"

for %%I in ("%~dp0.") do set "SCRIPT_DIR=%%~fI"
set "REPO_ROOT=%DEFAULT_REPO%"
if exist "%SCRIPT_DIR%\.git" set "REPO_ROOT=%SCRIPT_DIR%"

if /I not "%BRANCH%"=="feat/technician-clickable-live-cert-cmds" (
  echo [FAIL] This development bootstrap is pinned to feat/technician-clickable-live-cert-cmds.
  echo        A different branch requires a separately reviewed bootstrap/hash pair.
  exit /b 8
)

echo ============================================================
echo  AgentSwitchboard Technician Bootstrap
echo ============================================================
echo Repository: %REPO_ROOT%
echo Branch:     %BRANCH%
echo.

where curl.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] curl.exe was not found.
  exit /b 10
)
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) was not found on PATH.
  exit /b 23
)

set "PARENT_PATH=%SCRIPT_DIR%\%PARENT_NAME%"
if not exist "%PARENT_PATH%" (
  echo [INFO] Repository parent bootstrap is not local. Downloading the pinned source...
  curl.exe -fL "%PARENT_URL%" -o "%PARENT_TEMP%"
  if errorlevel 1 (
    echo [FAIL] Could not download the AgentSwitchboard parent bootstrap.
    exit /b 11
  )
  set "PARENT_PATH=%PARENT_TEMP%"
)

set "AS_PARENT_PATH=%PARENT_PATH%"
set "ACTUAL_PARENT_SHA256="
for /f "usebackq delims=" %%H in (`pwsh.exe -NoLogo -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath $env:AS_PARENT_PATH).Hash.ToLowerInvariant()"`) do set "ACTUAL_PARENT_SHA256=%%H"
if not defined ACTUAL_PARENT_SHA256 (
  echo [FAIL] Could not calculate the parent bootstrap SHA-256.
  exit /b 12
)
if /I not "%ACTUAL_PARENT_SHA256%"=="%EXPECTED_PARENT_SHA256%" (
  echo [FAIL] Parent bootstrap SHA-256 mismatch.
  echo Expected: %EXPECTED_PARENT_SHA256%
  echo Actual:   %ACTUAL_PARENT_SHA256%
  echo No downloaded bootstrap was executed.
  exit /b 13
)

echo [PASS] Parent bootstrap SHA-256 verified.
call "%PARENT_PATH%" "%REPO_ROOT%" "%BRANCH%"
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" (
  echo [FAIL] Repository acquisition/setup failed with exit code %EXITCODE%.
  goto :finish
)

if not exist "%REPO_ROOT%\Run-Technician-LiveCert.cmd" (
  echo [FAIL] Freshly pulled repository does not contain Run-Technician-LiveCert.cmd.
  set "EXITCODE=21"
  goto :finish
)

echo.
echo [PASS] Repository acquisition/setup completed.
echo [NEXT] Starting the repository-owned full technician live certificate.
call "%REPO_ROOT%\Run-Technician-LiveCert.cmd"
set "EXITCODE=%ERRORLEVEL%"

:finish
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)
exit /b %EXITCODE%
