@echo off
setlocal
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "MANAGER=%~dp0tooling\profiles\windows\Manage-PromptKitWebsiteSchedule.ps1"

if not exist "%POWERSHELL%" (
  echo Windows PowerShell was not found.
  exit /b 1
)
if not exist "%MANAGER%" (
  echo Prompt Kit sync manager was not found: %MANAGER%
  exit /b 1
)

if "%~1"=="" (
  "%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%MANAGER%" Status
) else (
  "%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%MANAGER%" %*
)
exit /b %ERRORLEVEL%
