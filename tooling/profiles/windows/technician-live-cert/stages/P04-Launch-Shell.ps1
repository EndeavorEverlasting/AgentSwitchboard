[CmdletBinding()]
param(
    [string]$StageId = 'P04',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Running P04-Launch-Shell stage..." -ForegroundColor Yellow

$launcherScript = Join-Path $RepoRoot 'tooling\profiles\windows\Invoke-AgentSwitchboardOpenOrActivate.ps1'
if (-not (Test-Path -LiteralPath $launcherScript)) {
    # Fallback to Setup-TechnicianAgentSwitchboard.ps1 with -Mode shell
    $launcherScript = Join-Path $RepoRoot 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
}

Write-Host "Delegating shell launch to: $launcherScript" -ForegroundColor Gray
$proc = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$launcherScript`"", "-RepoRoot", "`"$RepoRoot`"", "-Mode", "shell" -Wait -NoNewWindow -PassThru

if ($proc.ExitCode -ne 0) {
    Write-Warning "Shell launch returned exit code $($proc.ExitCode)."
}

Write-Host "P04-Launch-Shell completed." -ForegroundColor Green
return 0
