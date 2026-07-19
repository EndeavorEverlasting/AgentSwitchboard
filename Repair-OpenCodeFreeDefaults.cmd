@echo off
setlocal EnableExtensions DisableDelayedExpansion

cd /d "%~dp0"
set "ENTRYPOINT=%~dp0tooling\wsl\Invoke-OpenCodeFreeDefaultsRepair.ps1"

if not exist "%ENTRYPOINT%" (
  echo [FAIL] OpenCode free-default repair entrypoint is missing:
  echo        %ENTRYPOINT%
  exit /b 2
)

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 was not found on PATH.
  exit /b 3
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ENTRYPOINT%" -SourceRepoPath "%~dp0" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [FAIL] OpenCode free-default repair failed with exit code %EXIT_CODE%.
  pause >nul
)

exit /b %EXIT_CODE%
