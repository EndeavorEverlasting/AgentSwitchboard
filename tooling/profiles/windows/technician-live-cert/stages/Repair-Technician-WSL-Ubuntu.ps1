[CmdletBinding()]
param(
    [string]$RepairId = 'WSL-Ubuntu',
    [string]$RunId,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Repairing WSL Ubuntu installation..." -ForegroundColor Yellow
$proc = Start-Process -FilePath "wsl.exe" -ArgumentList "--install", "-d", "Ubuntu" -Wait -NoNewWindow -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Warning "wsl --install returned exit code $($proc.ExitCode). Checking existing WSL distributions..."
    wsl --list --verbose
}
Write-Host "WSL Ubuntu repair complete." -ForegroundColor Green
exit 0
