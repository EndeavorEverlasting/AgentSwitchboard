@echo off
setlocal EnableExtensions DisableDelayedExpansion
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) was not found on PATH.
  exit /b 23
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-SkillFactoringContracts.ps1" -RootPath "%~dp0" %*
set "RESULT=%ERRORLEVEL%"
endlocal & exit /b %RESULT%
