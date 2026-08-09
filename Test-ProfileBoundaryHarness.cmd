@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
where python >nul 2>nul
if errorlevel 1 (
  echo BLOCKED: python is required for the profile-boundary harness. 1>&2
  exit /b 2
)
python "%ROOT%scripts\Test-ProfileBoundaryHarness.py"
if errorlevel 1 exit /b %errorlevel%
python "%ROOT%tests\test_profile_boundary_harness.py"
if errorlevel 1 exit /b %errorlevel%
python "%ROOT%tests\test_device_profile_launcher_contract.py"
if errorlevel 1 exit /b %errorlevel%
python "%ROOT%tests\test_android_termux_harness.py"
if errorlevel 1 exit /b %errorlevel%
git -C "%ROOT%" diff --check
if errorlevel 1 exit /b %errorlevel%
echo PASS: profile-boundary harness Windows front door
exit /b 0
