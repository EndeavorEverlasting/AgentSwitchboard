@echo off
setlocal EnableExtensions DisableDelayedExpansion
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) is required.
  exit /b 23
)
for %%I in ("%~dp0.") do set "ROOT=%%~fI"
pushd "%ROOT%" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Unable to enter repository root: %ROOT%
  exit /b 25
)
set "OUTROOT=%LOCALAPPDATA%\AgentSwitchboard\technician-bootstrap-order\runs"
if not defined LOCALAPPDATA set "OUTROOT=%TEMP%\AgentSwitchboard\technician-bootstrap-order\runs"
for /f "usebackq delims=" %%I in (`pwsh.exe -NoLogo -NoProfile -Command "[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)"`) do set "RUNID=%%I"
if not defined RUNID (
  popd >nul 2>&1
  echo [FAIL] Unable to create run id.
  exit /b 24
)
set "RUNDIR=%OUTROOT%\%RUNID%"

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\Test-TechnicianBootstrapOrderHarnessCompleteness.ps1" -RootPath "%ROOT%" -OutputDirectory "%RUNDIR%"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" goto :finish

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\Test-TechnicianBootstrapOrder.ps1" -RootPath "%ROOT%"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" goto :finish

python -m unittest tests.test_technician_bootstrap_order_harness -v
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" goto :finish

python -m unittest tests.test_technician_bootstrap_order -v
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" goto :finish

python -m unittest tests.test_technician_agentswitchboard_ready -v
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" goto :finish

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tooling\profiles\windows\Get-TechnicianBootstrapOrderHarnessStatus.ps1" -RootPath "%ROOT%" -OutputDirectory "%RUNDIR%"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" goto :finish

git -C "%ROOT%" diff --check
set "RESULT=%ERRORLEVEL%"

:finish
if "%RESULT%"=="0" (
  echo [PASS] Technician bootstrap-order harness validation completed.
  echo [INFO] Artifact root: %RUNDIR%
) else (
  echo [FAIL] Technician bootstrap-order harness validation exited with code %RESULT%.
  echo [INFO] Artifact root: %RUNDIR%
)
popd >nul 2>&1
endlocal & exit /b %RESULT%
