[CmdletBinding()]
param(
    [string]$RepairId = 'AGY',
    [string]$RunId,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Repairing AGY installation inside Ubuntu...' -ForegroundColor Yellow
$wsl = Get-Command wsl.exe -ErrorAction Stop
$script = 'set -euo pipefail; curl -fsSL https://antigravity.google/cli/install.sh | bash; export PATH="$HOME/.local/bin:$PATH"; command -v agy; agy --version'
$output = (& $wsl.Source -d Ubuntu -- bash -lc $script 2>&1 | Out-String).Trim()
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "AGY repair failed inside Ubuntu with exit code $exitCode. Output: $output"
}
if ($output -notmatch '(?im)^/.+agy\s*$') {
    throw "AGY installer returned success but command resolution was not proven. Output: $output"
}

Write-Host "AGY repair verified inside Ubuntu.`n$output" -ForegroundColor Green
return 0
