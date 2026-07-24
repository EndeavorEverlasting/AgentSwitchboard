@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Technician Bootstrap

set "BRANCH=main"
set "EXPECTED_PARENT_SHA256=a0d603585bb66dfa9fa4c3af2179415321d667b0c8548c960d8012278968881b"
set "DEFAULT_REPO=%USERPROFILE%\dev\AgentSwitchBoard-Live"
set "STATE_DIR=%LOCALAPPDATA%\AgentSwitchBoard\state"
set "STATE_FILE=%STATE_DIR%\repo-path.txt"
set "PARENT_NAME=Pull-Repo-And-Setup-AgentSwitchboard.cmd"
set "PARENT_TEMP=%TEMP%\AgentSwitchboard-%PARENT_NAME%"
set "ORIGINAL_NO_PAUSE=%AGENT_SWITCHBOARD_NO_PAUSE%"

if not "%~2"=="" set "BRANCH=%~2"
if /I not "%BRANCH%"=="main" (
  echo [FAIL] This production bootstrap is pinned to main.
  echo        A different ref requires a separately reviewed bootstrap/hash pair.
  exit /b 8
)

for %%I in ("%~dp0.") do set "SCRIPT_DIR=%%~fI"
set "REPO_ROOT="
set "BINDING_SOURCE="

rem 1. Explicit invocation argument always wins.
if not "%~1"=="" (
  set "REPO_ROOT=%~1"
  set "BINDING_SOURCE=explicit argument"
  goto :repo_selected
)

rem 2. Environment override is portable across shells and shortcuts.
if defined AGENT_SWITCHBOARD_REPO (
  set "REPO_ROOT=%AGENT_SWITCHBOARD_REPO%"
  set "BINDING_SOURCE=AGENT_SWITCHBOARD_REPO"
  goto :repo_selected
)

rem 3. When invoked from an existing checkout, keep that checkout.
if exist "%SCRIPT_DIR%\.git" (
  set "REPO_ROOT=%SCRIPT_DIR%"
  set "BINDING_SOURCE=bootstrap directory"
  goto :repo_selected
)
if exist "%CD%\.git" (
  set "REPO_ROOT=%CD%"
  set "BINDING_SOURCE=current directory"
  goto :repo_selected
)

rem 4. Reuse this machine's previously verified checkout from any directory.
if exist "%STATE_FILE%" goto :load_machine_binding
goto :after_machine_binding

:load_machine_binding
set "REPO_ROOT="
set /p "REPO_ROOT="<"%STATE_FILE%"
if not defined REPO_ROOT goto :after_machine_binding
if exist "%REPO_ROOT%\.git" (
  set "BINDING_SOURCE=machine binding"
  goto :repo_selected
)
set "REPO_ROOT="

:after_machine_binding
rem 5. Recognize common healthy historical locations without depending on them.
if exist "%USERPROFILE%\dev\AgentSwitchBoard-Live\.git" (
  set "REPO_ROOT=%USERPROFILE%\dev\AgentSwitchBoard-Live"
  set "BINDING_SOURCE=portable candidate"
  goto :repo_selected
)
if exist "%USERPROFILE%\dev\AgentSwitchBoard\.git" (
  set "REPO_ROOT=%USERPROFILE%\dev\AgentSwitchBoard"
  set "BINDING_SOURCE=portable candidate"
  goto :repo_selected
)
if exist "%USERPROFILE%\Desktop\dev\AgentSwitchBoard-Live\.git" (
  set "REPO_ROOT=%USERPROFILE%\Desktop\dev\AgentSwitchBoard-Live"
  set "BINDING_SOURCE=legacy Desktop candidate"
  goto :repo_selected
)
if exist "%USERPROFILE%\Desktop\dev\AgentSwitchBoard\.git" (
  set "REPO_ROOT=%USERPROFILE%\Desktop\dev\AgentSwitchBoard"
  set "BINDING_SOURCE=legacy Desktop candidate"
  goto :repo_selected
)

rem 6. A machine with no checkout gets one stable path outside Desktop/OneDrive.
set "REPO_ROOT=%DEFAULT_REPO%"
set "BINDING_SOURCE=portable default"

:repo_selected
for %%I in ("%REPO_ROOT%") do set "REPO_ROOT=%%~fI"
set "PARENT_URL=https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/%BRANCH%/%PARENT_NAME%"

echo ============================================================
echo  AgentSwitchboard Technician Bootstrap
echo ============================================================
echo Repository: %REPO_ROOT%
echo Binding:    %BINDING_SOURCE%
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

rem Always execute the raw reviewed parent bootstrap, even when a checkout
rem already exists. This avoids Git line-ending conversion changing the hash.
echo [INFO] Downloading the pinned parent bootstrap...
curl.exe -fL "%PARENT_URL%" -o "%PARENT_TEMP%"
if errorlevel 1 (
  echo [FAIL] Could not download the AgentSwitchboard parent bootstrap.
  exit /b 11
)

set "AS_PARENT_PATH=%PARENT_TEMP%"
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
call "%PARENT_TEMP%" "%REPO_ROOT%" "%BRANCH%"
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" (
  echo [FAIL] Repository acquisition failed with exit code %EXITCODE%.
  goto :finish
)

rem Bind only after the canonical acquisition surface verified the checkout.
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>&1
if not exist "%STATE_DIR%" (
  echo [WARN] Repository acquisition passed but the per-machine binding directory could not be created:
  echo        %STATE_DIR%
) else (
  >"%STATE_FILE%" echo %REPO_ROOT%
  if errorlevel 1 (
    echo [WARN] Repository acquisition passed but the per-machine binding could not be saved:
    echo        %STATE_FILE%
  ) else (
    echo [PASS] Machine repo binding saved: %STATE_FILE%
  )
)

if not exist "%REPO_ROOT%\Repair-Technician-WSL-Ubuntu.cmd" (
  echo [FAIL] Freshly pulled repository does not contain Repair-Technician-WSL-Ubuntu.cmd.
  set "EXITCODE=21"
  goto :finish
)
if not exist "%REPO_ROOT%\Pull-And-Run-AgentSwitchboard.cmd" (
  echo [FAIL] Freshly pulled repository does not contain Pull-And-Run-AgentSwitchboard.cmd.
  set "EXITCODE=22"
  goto :finish
)
if not exist "%REPO_ROOT%\Run-Technician-LiveCert.cmd" (
  echo [FAIL] Freshly pulled repository does not contain Run-Technician-LiveCert.cmd.
  set "EXITCODE=24"
  goto :finish
)

rem A first-machine bootstrap repairs the WSL platform before workstation setup.
rem This is intentionally idempotent on machines whose WSL/Ubuntu state is healthy.
set "AGENT_SWITCHBOARD_NO_PAUSE=1"
echo.
echo ============================================================
echo  FIRST-MACHINE PREREQUISITE: WSL / UBUNTU
echo ============================================================
call "%REPO_ROOT%\Repair-Technician-WSL-Ubuntu.cmd"
set "REPAIR_EXIT=%ERRORLEVEL%"
if "%REPAIR_EXIT%"=="3010" (
  echo.
  echo [REBOOT REQUIRED] Windows must restart before setup can continue.
  echo [INFO] The WSL repair has registered its one-time continuation.
  echo [INFO] After that repair finishes, run AgentSwitchboard-Technician-Bootstrap.cmd again from anywhere.
  set "EXITCODE=3010"
  goto :finish
)
if not "%REPAIR_EXIT%"=="0" (
  echo [FAIL] First-machine WSL/Ubuntu repair failed with exit code %REPAIR_EXIT%.
  set "EXITCODE=%REPAIR_EXIT%"
  goto :finish
)

rem Only after WSL/Ubuntu is healthy do we install/verify the workstation tools.
echo.
echo ============================================================
echo  WORKSTATION SETUP
echo ============================================================
call "%REPO_ROOT%\Pull-And-Run-AgentSwitchboard.cmd" setup "%REPO_ROOT%" "%BRANCH%"
set "SETUP_EXIT=%ERRORLEVEL%"
if not "%SETUP_EXIT%"=="0" (
  echo [FAIL] Workstation setup failed with exit code %SETUP_EXIT%.
  set "EXITCODE=%SETUP_EXIT%"
  goto :finish
)

echo.
echo [PASS] Repository acquisition, first-machine prerequisites, and workstation setup completed.
echo [NEXT] Starting the repository-owned full technician live certificate.
call "%REPO_ROOT%\Run-Technician-LiveCert.cmd"
set "EXITCODE=%ERRORLEVEL%"

:finish
if not "%ORIGINAL_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)
exit /b %EXITCODE%
