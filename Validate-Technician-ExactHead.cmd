@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Exact-Head Validation

set "REPO_ROOT=%~1"
if not defined REPO_ROOT set "REPO_ROOT=%~dp0"
for %%I in ("%REPO_ROOT%\.") do set "REPO_ROOT=%%~fI"

set "REMOTE_REF=%~2"
set "EXPECTED_HEAD=%~3"

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) was not found on PATH.
  set "RESULT=23"
  goto :finish
)

set "SCRIPT=%REPO_ROOT%\scripts\Invoke-TechnicianExactHeadValidation.ps1"
if not exist "%SCRIPT%" (
  echo [FAIL] Exact-head validator is missing:
  echo        %SCRIPT%
  set "RESULT=24"
  goto :finish
)

if defined REMOTE_REF goto :with_ref
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoRoot "%REPO_ROOT%"
set "RESULT=%ERRORLEVEL%"
goto :finish

:with_ref
if defined EXPECTED_HEAD goto :with_expected
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoRoot "%REPO_ROOT%" -RemoteRef "%REMOTE_REF%"
set "RESULT=%ERRORLEVEL%"
goto :finish

:with_expected
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoRoot "%REPO_ROOT%" -RemoteRef "%REMOTE_REF%" -ExpectedHead "%EXPECTED_HEAD%"
set "RESULT=%ERRORLEVEL%"

:finish
echo.
if "%RESULT%"=="0" (
  echo [PASS] Exact-head validation completed.
) else (
  echo [FAIL] Exact-head validation exited with code %RESULT%.
)
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)
endlocal & exit /b %RESULT%
