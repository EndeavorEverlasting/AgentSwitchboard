[CmdletBinding()]
param(
    [string]$RepairId = 'WSL-Ubuntu',
    [string]$RunId,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Repairing WSL Ubuntu installation...' -ForegroundColor Yellow
$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
    throw 'wsl.exe is unavailable. Windows Subsystem for Linux must be enabled before this repair can continue.'
}

& $wsl.Source --install -d Ubuntu
$installExit = $LASTEXITCODE

$rawDistributions = @(& $wsl.Source --list --quiet 2>$null)
$listExit = $LASTEXITCODE
$distributions = @($rawDistributions | ForEach-Object { ([string]$_).Replace([char]0, '').Trim() } | Where-Object { $_ })
if ($listExit -ne 0) {
    throw "WSL distribution verification failed after repair attempt. Installer exit: $installExit."
}
if ($distributions -notcontains 'Ubuntu') {
    throw "Ubuntu is not yet available after 'wsl --install -d Ubuntu' (exit $installExit). Complete any required reboot/Windows feature activation and rerun this repair before P00."
}

& $wsl.Source -d Ubuntu -- bash -lc 'printf AGENT_SWITCHBOARD_UBUNTU_READY' | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Ubuntu is registered but first-run initialization is incomplete. Launch Ubuntu once, create the Linux user, then rerun this repair/P00.'
}

Write-Host 'WSL Ubuntu repair verified an initialized Ubuntu distribution.' -ForegroundColor Green
return 0
