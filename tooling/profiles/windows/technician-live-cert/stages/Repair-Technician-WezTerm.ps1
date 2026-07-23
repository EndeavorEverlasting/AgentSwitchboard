[CmdletBinding()]
param(
    [string]$RepairId = 'WezTerm',
    [string]$RunId,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Repairing WezTerm installation via WinGet..." -ForegroundColor Yellow
$proc = Start-Process -FilePath "winget.exe" -ArgumentList "install", "wez.wezterm", "--accept-package-agreements", "--accept-source-agreements" -Wait -NoNewWindow -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Warning "WinGet returned exit code $($proc.ExitCode)."
}
Write-Host "WezTerm repair complete." -ForegroundColor Green
exit 0
