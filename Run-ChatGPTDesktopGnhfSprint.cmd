@echo off
setlocal EnableExtensions DisableDelayedExpansion

cd /d "%~dp0"
set "ENTRYPOINT=%~dp0tooling\gnhf\Invoke-ChatGPTDesktopGnhfSprint.ps1"
set "LATEST=%LOCALAPPDATA%\AgentSwitchboard\GnhfDesktop\latest-run.txt"

if not exist "%ENTRYPOINT%" (
  echo [FAIL] Canonical desktop GNHF entrypoint is missing:
  echo        %ENTRYPOINT%
  exit /b 2
)

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) is required.
  exit /b 2
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ENTRYPOINT%" %*
set "RESULT=%ERRORLEVEL%"

if not "%RESULT%"=="0" (
  echo.
  echo [FAIL] Desktop GNHF sprint exited with code %RESULT%.
  if exist "%LATEST%" (
    echo        Exact local evidence:
    type "%LATEST%"
  ) else (
    echo        Evidence root: %LOCALAPPDATA%\AgentSwitchboard\GnhfDesktop
  )
)

endlocal & exit /b %RESULT%
