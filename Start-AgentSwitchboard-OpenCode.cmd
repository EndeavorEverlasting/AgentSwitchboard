@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard OpenCode sprint

set "RESULT=0"
set "PWSH="
set "SCRIPT=%~dp0tooling\gnhf\Start-AgentSwitchboardOpenCode.ps1"
set "PWSH_PROBE=%~dp0scripts\Test-OperatorChildExecutableLaunch.ps1"
set "PROBE_HOST=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%SCRIPT%" (
  echo [FAIL] Repository-owned OpenCode launcher is missing:
  echo        %SCRIPT%
  set "RESULT=26"
  goto :finish
)

if not exist "%PWSH_PROBE%" (
  echo [FAIL] Concrete child-executable launch probe is missing:
  echo        %PWSH_PROBE%
  echo        Refusing to treat path discovery as PowerShell launch proof.
  set "RESULT=27"
  goto :finish
)

if not exist "%PROBE_HOST%" (
  echo [FAIL] Inbox Windows PowerShell probe host is missing:
  echo        %PROBE_HOST%
  set "RESULT=28"
  goto :finish
)

if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" call :try_pwsh "%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH if defined LOCALAPPDATA if exist "%LOCALAPPDATA%\Programs\PowerShell\7\pwsh.exe" call :try_pwsh "%LOCALAPPDATA%\Programs\PowerShell\7\pwsh.exe"
if not defined PWSH for /f "delims=" %%I in ('where pwsh.exe 2^>nul') do if not defined PWSH call :try_pwsh "%%I"

if not defined PWSH (
  echo [FAIL] No PowerShell 7 candidate passed concrete process-start proof.
  echo        Run Setup-AgentSwitchboard.cmd to repair the workstation, then click this launcher again.
  set "RESULT=25"
  goto :finish
)

echo [USE] PowerShell 7: %PWSH%
"%PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RESULT=%ERRORLEVEL%"
goto :finish

:try_pwsh
if defined PWSH exit /b 0
set "CANDIDATE=%~1"
if not exist "%CANDIDATE%" exit /b 0
echo [PROBE] PowerShell 7 candidate: %CANDIDATE%
"%PROBE_HOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PWSH_PROBE%" -ExecutablePath "%CANDIDATE%" -ArgumentList --version -Label opencode-launch-pwsh
if errorlevel 1 (
  echo [WARN] Candidate exists but did not pass concrete launch proof: %CANDIDATE%
) else (
  set "PWSH=%CANDIDATE%"
  echo [PASS] Concrete PowerShell 7 launch proof: %CANDIDATE%
)
exit /b 0

:finish
echo.
if "%RESULT%"=="0" (
  echo [DONE] AgentSwitchboard OpenCode launcher completed.
) else (
  echo [FAIL] AgentSwitchboard OpenCode launcher exited with code %RESULT%.
  echo        Review the evidence path printed above; the launcher does not discard failure diagnostics.
)
if /I not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  pause
)
endlocal & exit /b %RESULT%
