@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ROOT=%~dp0"
set "PY_KIND="
set "R="
where python.exe >nul 2>nul
if not errorlevel 1 (
  python.exe -c "import sys; raise SystemExit(0 if sys.version_info.major == 3 else 1)" >nul 2>nul
  if not errorlevel 1 set "PY_KIND=python"
)
if not defined PY_KIND (
  where py.exe >nul 2>nul
  if not errorlevel 1 (
    py.exe -3 -c "import sys; raise SystemExit(0 if sys.version_info.major == 3 else 1)" >nul 2>nul
    if not errorlevel 1 set "PY_KIND=py"
  )
)
if not defined PY_KIND (echo [FAIL] usable Python 3 is required.& endlocal & exit /b 127)
pushd "%ROOT%" || (echo [FAIL] cannot enter repository root.& endlocal & exit /b 2)
if "%PY_KIND%"=="python" goto :run_python
goto :run_py

:run_python
python.exe -m unittest tests.test_progressive_disclosure_harness -v
if errorlevel 1 set "R=%ERRORLEVEL%"
if defined R goto :fail
python.exe scripts/Test-ProgressiveDisclosureHarness.py
if errorlevel 1 set "R=%ERRORLEVEL%"
if defined R goto :fail
goto :diff_check

:run_py
py.exe -3 -m unittest tests.test_progressive_disclosure_harness -v
if errorlevel 1 set "R=%ERRORLEVEL%"
if defined R goto :fail
py.exe -3 scripts/Test-ProgressiveDisclosureHarness.py
if errorlevel 1 set "R=%ERRORLEVEL%"
if defined R goto :fail

:diff_check
git diff --check
if errorlevel 1 set "R=%ERRORLEVEL%"
if defined R goto :fail
popd
endlocal
exit /b 0

:fail
popd
endlocal & exit /b %R%
