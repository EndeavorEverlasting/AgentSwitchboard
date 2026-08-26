@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Technician Ready

set "MODE=%~1"
if not defined MODE set "MODE=shell"

if /I not "%MODE%"=="shell" if /I not "%MODE%"=="agy" if /I not "%MODE%"=="opencode" if /I not "%MODE%"=="setup" if /I not "%MODE%"=="hermes" (
  echo [FAIL] Unsupported mode: %MODE%
  echo Usage: %~nx0 [shell^|agy^|opencode^|setup^|hermes] [repo-path] [git-ref]
  set "RESULT=2"
  goto :finish
)

set "REPO_ROOT=%~2"
if not defined REPO_ROOT set "REPO_ROOT=%~dp0"
for %%I in ("%REPO_ROOT%\.") do set "REPO_ROOT=%%~fI"

set "GIT_REF=%~3"
if not defined GIT_REF (
  for /f "usebackq delims=" %%I in (`git -C "%REPO_ROOT%" symbolic-ref --quiet --short HEAD 2^>nul`) do set "GIT_REF=%%I"
)
if not defined GIT_REF set "GIT_REF=main"

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) was not found on PATH.
  set "RESULT=23"
  goto :finish
)

set "BOOTSTRAP=%REPO_ROOT%\tooling\profiles\windows\Invoke-TechnicianBootstrapPrerequisites.ps1"
if not exist "%BOOTSTRAP%" (
  echo [FAIL] Canonical technician prerequisite gate is missing:
  echo        %BOOTSTRAP%
  set "RESULT=24"
  goto :finish
)

set "ENGINE=%REPO_ROOT%\tooling\profiles\windows\Invoke-TechnicianAgentSwitchboardReady.ps1"
if not exist "%ENGINE%" (
  echo [FAIL] Canonical technician readiness engine is missing:
  echo        %ENGINE%
  set "RESULT=25"
  goto :finish
)

echo ============================================================
echo  AgentSwitchboard Technician Ready
echo ============================================================
echo Mode:       %MODE%
echo Repository: %REPO_ROOT%
echo Git ref:    %GIT_REF%
echo.

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%BOOTSTRAP%" -RepoRoot "%REPO_ROOT%"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" goto :finish

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Mode "%MODE%" -RepoRoot "%REPO_ROOT%" -GitRef "%GIT_REF%"
set "RESULT=%ERRORLEVEL%"

:finish
echo.
if "%RESULT%"=="0" (
  echo [PASS] AgentSwitchboard technician readiness completed.
  echo [INFO] Open a fresh PowerShell and run: AgentSwitchboard -ListAgents
) else (
  echo [FAIL] AgentSwitchboard technician readiness exited with code %RESULT%.
)
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)
endlocal & exit /b %RESULT%
