@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Exact-Head Validation

set "REPO_ROOT=%~1"
if not defined REPO_ROOT set "REPO_ROOT=%~dp0"
for %%I in ("%REPO_ROOT%\.") do set "REPO_ROOT=%%~fI"

set "REMOTE_REF=%~2"
set "EXPECTED_HEAD=%~3"
set "FIELD_MODE=%~4"
if not defined FIELD_MODE set "FIELD_MODE=validate"

if /I not "%FIELD_MODE%"=="validate" if /I not "%FIELD_MODE%"=="ready" (
  echo [FAIL] Unsupported field mode: %FIELD_MODE%
  echo Usage: %~nx0 [repo-path] [remote-ref] [expected-sha] [validate^|ready]
  set "RESULT=2"
  goto :finish
)

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

if /I "%FIELD_MODE%"=="ready" goto :run_ready

if defined REMOTE_REF goto :validate_with_ref
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoRoot "%REPO_ROOT%"
set "RESULT=%ERRORLEVEL%"
goto :finish

:validate_with_ref
if defined EXPECTED_HEAD goto :validate_with_expected
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoRoot "%REPO_ROOT%" -RemoteRef "%REMOTE_REF%"
set "RESULT=%ERRORLEVEL%"
goto :finish

:validate_with_expected
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoRoot "%REPO_ROOT%" -RemoteRef "%REMOTE_REF%" -ExpectedHead "%EXPECTED_HEAD%"
set "RESULT=%ERRORLEVEL%"
goto :finish

:run_ready
if not defined REMOTE_REF (
  echo [FAIL] Ready mode requires an explicit remote ref.
  set "RESULT=2"
  goto :finish
)
if not defined EXPECTED_HEAD (
  echo [FAIL] Ready mode requires an explicit expected commit SHA.
  set "RESULT=2"
  goto :finish
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoRoot "%REPO_ROOT%" -RemoteRef "%REMOTE_REF%" -ExpectedHead "%EXPECTED_HEAD%" -RunReadiness
set "RESULT=%ERRORLEVEL%"

:finish
echo.
if "%RESULT%"=="0" (
  if /I "%FIELD_MODE%"=="ready" (
    echo [PASS] Exact-head validation and AgentSwitchboard readiness completed.
  ) else (
    echo [PASS] Exact-head validation completed.
  )
) else (
  echo [FAIL] Exact-head field operation exited with code %RESULT%.
)
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)
endlocal & exit /b %RESULT%
