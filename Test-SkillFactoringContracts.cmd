@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PSHOST="
where pwsh.exe >nul 2>&1
if not errorlevel 1 set "PSHOST=pwsh.exe"
if not defined PSHOST (
  where powershell.exe >nul 2>&1
  if errorlevel 1 (
    echo [FAIL] Neither PowerShell 7 ^(pwsh.exe^) nor Windows PowerShell ^(powershell.exe^) was found on PATH.
    exit /b 23
  )
  set "PSHOST=powershell.exe"
)
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-SkillFactoringContracts.ps1" -RootPath "%~dp0" %*
set "RESULT=%ERRORLEVEL%"
endlocal & exit /b %RESULT%
