[CmdletBinding()]
param(
    [string]$StageId = 'P02',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Running P02-Pull-And-Setup stage..." -ForegroundColor Yellow

$setupScript = Join-Path $RepoRoot 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
if (-not (Test-Path -LiteralPath $setupScript)) {
    throw "Setup-TechnicianAgentSwitchboard.ps1 missing at: $setupScript"
}

Write-Host "Delegating to Setup-TechnicianAgentSwitchboard.ps1 -Mode setup..." -ForegroundColor Gray
$proc = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$setupScript`"", "-Mode", "setup", "-RepoRoot", "`"$RepoRoot`"" -Wait -NoNewWindow -PassThru

if ($proc.ExitCode -ne 0) {
    throw "Setup-TechnicianAgentSwitchboard.ps1 failed with exit code $($proc.ExitCode)."
}

Write-Host "P02-Pull-And-Setup passed." -ForegroundColor Green
return 0
