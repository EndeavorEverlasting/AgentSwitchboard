@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard tmux live proof

set "RESULT=0"
set "PWSH="
set "SCRIPT=%~dp0Open-AgentSwitchboard-Tmux.ps1"
set "PWSH_PROBE=%~dp0scripts\Test-OperatorChildExecutableLaunch.ps1"
set "PROBE_HOST=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%SCRIPT%" (
  echo [FAIL] Repository-owned tmux launcher is missing:
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
  where winget.exe >nul 2>&1
  if errorlevel 1 (
    echo [FAIL] No launchable PowerShell 7 candidate was proved and WinGet is unavailable.
    echo        Install or repair PowerShell 7, then rerun %~nx0.
    set "RESULT=23"
    goto :finish
  )
  echo [INSTALL] No launchable PowerShell 7 candidate was proved; installing Microsoft.PowerShell with WinGet.
  winget.exe install --id Microsoft.PowerShell --exact --source winget --silent --accept-source-agreements --accept-package-agreements
  if errorlevel 1 (
    echo [FAIL] WinGet could not install PowerShell 7.
    set "RESULT=24"
    goto :finish
  )
  if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" call :try_pwsh "%ProgramFiles%\PowerShell\7\pwsh.exe"
  if not defined PWSH if defined LOCALAPPDATA if exist "%LOCALAPPDATA%\Programs\PowerShell\7\pwsh.exe" call :try_pwsh "%LOCALAPPDATA%\Programs\PowerShell\7\pwsh.exe"
  if not defined PWSH for /f "delims=" %%I in ('where pwsh.exe 2^>nul') do if not defined PWSH call :try_pwsh "%%I"
)

if not defined PWSH (
  echo [FAIL] PowerShell 7 candidates were discovered or installed, but none passed concrete process-start proof.
  echo        Review the child-executable-launch-result.json artifacts printed above.
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
"%PROBE_HOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PWSH_PROBE%" -ExecutablePath "%CANDIDATE%" -ArgumentList --version -Label pwsh
if errorlevel 1 (
  echo [WARN] Candidate exists but did not pass concrete launch proof: %CANDIDATE%
) else (
  set "PWSH=%CANDIDATE%"
  echo [PASS] Concrete PowerShell 7 launch proof: %CANDIDATE%
)
exit /b 0

:finish
if "%RESULT%"=="0" (
  echo [PASS] AgentSwitchboard tmux live-proof launcher completed.
) else (
  echo [FAIL] AgentSwitchboard tmux live-proof launcher exited with code %RESULT%.
)
endlocal & exit /b %RESULT%
