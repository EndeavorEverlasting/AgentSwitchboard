@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo  AgentSwitchboard Typed Cascade Harness
 echo ============================================================
echo.

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-TypedCascadeHarness.ps1"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" goto :finish

python "%~dp0tests\test_typed_cascade_harness.py"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" goto :finish

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-RuntimeEventContract.ps1"
set "RESULT=%ERRORLEVEL%"

:finish
echo.
if "%RESULT%"=="0" (
    echo [PASS] Typed cascade harness contracts and synthetic cascade semantics passed.
) else (
    echo [FAIL] Typed cascade harness validation exited with code %RESULT%.
)
exit /b %RESULT%
