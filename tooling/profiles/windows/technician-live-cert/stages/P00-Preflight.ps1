[CmdletBinding()]
param(
    [string]$StageId = 'P00',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Running P00-Preflight checks...' -ForegroundColor Yellow

if ($env:OS -ne 'Windows_NT') {
    throw 'P00-Preflight requires Windows_NT.'
}

$requiredCommands = [ordered]@{}
foreach ($commandName in @('pwsh.exe', 'git.exe', 'curl.exe', 'wsl.exe')) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    $requiredCommands[$commandName] = if ($command) { $command.Source } else { $null }
}

foreach ($commandName in @('pwsh.exe', 'git.exe', 'curl.exe')) {
    if ([string]::IsNullOrWhiteSpace([string]$requiredCommands[$commandName])) {
        throw "$commandName is required on PATH."
    }
}

# Prove that the evidence location is writable by creating and removing a tiny probe.
if (-not (Test-Path -LiteralPath $StageDir -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $StageDir -Force
}
$writeProbe = Join-Path $StageDir '.write-probe.tmp'
[System.IO.File]::WriteAllText($writeProbe, 'ok', [System.Text.Encoding]::ASCII)
if (-not (Test-Path -LiteralPath $writeProbe -PathType Leaf)) {
    throw "Live-cert evidence directory is not writable: $StageDir"
}
Remove-Item -LiteralPath $writeProbe -Force

$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.User -or [string]::IsNullOrWhiteSpace($identity.User.Value)) {
    throw 'Unable to resolve the current Windows account SID.'
}

$ciSurfaceOnly = ($env:TECHNICIAN_LIVE_CERT_CI_SURFACE -eq '1')
$ubuntuInitialized = $false
$distributions = @()
$wslPath = [string]$requiredCommands['wsl.exe']

if (-not $ciSurfaceOnly) {
    if ([string]::IsNullOrWhiteSpace($wslPath)) {
        throw "WSL is not installed. Double-click Repair-Technician-WSL-Ubuntu.cmd, complete any required reboot and Ubuntu initialization, then restart P00."
    }

    $rawDistributions = @(& $wslPath --list --quiet 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'WSL is installed but its distribution list could not be read.'
    }
    $distributions = @($rawDistributions | ForEach-Object { ([string]$_).Replace([char]0, '').Trim() } | Where-Object { $_ })
    $ubuntuInitialized = $distributions -contains 'Ubuntu'
    if (-not $ubuntuInitialized) {
        throw "The required WSL distribution 'Ubuntu' is not initialized. Double-click Repair-Technician-WSL-Ubuntu.cmd, complete Ubuntu first-run initialization, then restart P00."
    }

    & $wslPath -d Ubuntu -- bash -lc 'printf AGENT_SWITCHBOARD_UBUNTU_READY' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Ubuntu exists but could not execute a non-interactive bash command. Complete Ubuntu initialization and restart P00."
    }
}

$preflightFile = Join-Path $StageDir 'preflight-summary.json'
$summaryData = [ordered]@{
    schema = 'agentswitchboard.technician-live-cert-preflight.v1'
    os = $env:OS
    psVersion = $PSVersionTable.PSVersion.ToString()
    account = $identity.Name
    accountSid = $identity.User.Value
    elevated = ([System.Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    commands = $requiredCommands
    evidenceWritable = $true
    wslDistributions = $distributions
    ubuntuInitialized = $ubuntuInitialized
    ciSurfaceOnly = $ciSurfaceOnly
    proofScope = if ($ciSurfaceOnly) { 'Windows CMD surface only; WSL/Ubuntu prerequisite not asserted in hosted CI.' } else { 'Windows workstation preflight including initialized Ubuntu execution.' }
    passed = $true
}
$summaryData | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $preflightFile -Encoding utf8NoBOM

if ($ciSurfaceOnly) {
    Write-Host 'P00 surface preflight passed; hosted CI intentionally did not assert WSL/Ubuntu readiness.' -ForegroundColor Green
} else {
    Write-Host 'P00-Preflight passed, including initialized Ubuntu execution.' -ForegroundColor Green
}
return 0
