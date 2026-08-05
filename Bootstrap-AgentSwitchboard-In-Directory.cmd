@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Directory Bootstrap

set "WORKSPACE_ROOT=%~1"
set "REPO_LEAF=%~2"
if not defined REPO_LEAF set "REPO_LEAF=AgentSwitchBoard-Live"
set "BOOTSTRAP_REF=241329b9f9ef785ad457832b3d312830b248795b"
set "EXPECTED_BOOTSTRAP_BLOB=ceaf48a5dd1c72d99a88c1e9c97cb56a4cb437f2"

if not defined WORKSPACE_ROOT (
  echo [FAIL] A workspace directory is required.
  echo Usage: %~nx0 "C:\path\to\Dev" [repo-folder-name]
  echo Example: %~nx0 "C:\Users\Example\Desktop\Dev"
  exit /b 2
)

for %%I in ("%WORKSPACE_ROOT%") do set "WORKSPACE_ROOT=%%~fI"
set "REPO_ROOT=%WORKSPACE_ROOT%\%REPO_LEAF%"
set "BOOTSTRAP_URL=https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/%BOOTSTRAP_REF%/AgentSwitchboard-Technician-Bootstrap.cmd"
set "BOOTSTRAP_PATH=%TEMP%\AgentSwitchboard-Technician-Bootstrap.cmd"

if not exist "%WORKSPACE_ROOT%" mkdir "%WORKSPACE_ROOT%"
if errorlevel 1 (
  echo [FAIL] Could not create workspace directory:
  echo        %WORKSPACE_ROOT%
  exit /b 3
)

where curl.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] curl.exe was not found.
  exit /b 10
)
where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Windows PowerShell was not found.
  exit /b 9
)

echo ============================================================
echo  AgentSwitchboard Directory Bootstrap
echo ============================================================
echo Workspace:   "%WORKSPACE_ROOT%"
echo Repository:  "%REPO_ROOT%"
echo Bootstrap:   %BOOTSTRAP_REF%
echo.
echo [INFO] Downloading the immutable repository-owned technician bootstrap...
curl.exe -fL "%BOOTSTRAP_URL%" -o "%BOOTSTRAP_PATH%"
if errorlevel 1 (
  echo [FAIL] Could not download AgentSwitchboard-Technician-Bootstrap.cmd.
  exit /b 11
)

set "AS_BOOTSTRAP_PATH=%BOOTSTRAP_PATH%"
set "ACTUAL_BOOTSTRAP_BLOB="
for /f "usebackq delims=" %%H in (`powershell.exe -NoLogo -NoProfile -Command "$p=$env:AS_BOOTSTRAP_PATH; $b=[IO.File]::ReadAllBytes($p); $prefix=[Text.Encoding]::ASCII.GetBytes(('blob {0}' -f $b.Length)+[char]0); $all=New-Object byte[] ($prefix.Length+$b.Length); [Array]::Copy($prefix,0,$all,0,$prefix.Length); [Array]::Copy($b,0,$all,$prefix.Length,$b.Length); ([BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash($all))).Replace('-','').ToLowerInvariant()"`) do set "ACTUAL_BOOTSTRAP_BLOB=%%H"
if not defined ACTUAL_BOOTSTRAP_BLOB (
  echo [FAIL] Could not calculate the downloaded bootstrap Git blob identity.
  exit /b 12
)
if /I not "%ACTUAL_BOOTSTRAP_BLOB%"=="%EXPECTED_BOOTSTRAP_BLOB%" (
  echo [FAIL] Downloaded bootstrap identity mismatch.
  echo Expected: %EXPECTED_BOOTSTRAP_BLOB%
  echo Actual:   %ACTUAL_BOOTSTRAP_BLOB%
  echo No downloaded bootstrap was executed.
  exit /b 13
)

echo [PASS] Immutable technician bootstrap identity verified.
call "%BOOTSTRAP_PATH%" "%REPO_ROOT%" main
set "RESULT=%ERRORLEVEL%"
if "%RESULT%"=="0" (
  echo [PASS] AgentSwitchboard completed for:
  echo        "%REPO_ROOT%"
) else (
  echo [FAIL] AgentSwitchboard directory bootstrap exited with code %RESULT%.
)
exit /b %RESULT%
