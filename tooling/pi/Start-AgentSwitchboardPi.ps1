[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [switch]$Offline,

    [switch]$AllowVersionCheck,

    [switch]$EnableTelemetry,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PiArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

$verificationPath = Join-Path $RootPath 'tooling/pi/harness/upstream-verification.json'
$settingsPath = Join-Path $RootPath '.pi/settings.json'
if (-not (Test-Path -LiteralPath $verificationPath -PathType Leaf)) {
    throw "Pi upstream verification record is missing: $verificationPath"
}
if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw "Project-local Pi settings are missing: $settingsPath"
}

$verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json
$expectedVersion = [version]([string]$verification.version)

function Resolve-PiCommand {
    if ($IsWindows) {
        foreach ($name in @('pi.cmd', 'pi.exe', 'pi')) {
            $command = Get-Command $name -ErrorAction SilentlyContinue
            if ($command -and $command.Source -notlike '*.ps1') { return $command.Source }
        }
    }
    else {
        $command = Get-Command pi -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    return $null
}

function Get-PiVersion {
    param([Parameter(Mandatory)][string]$PiPath)

    $output = & $PiPath --version 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Pi version probe failed with exit code $LASTEXITCODE. Output: $($output.Trim())"
    }
    $match = [regex]::Match($output, '(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if (-not $match.Success) { throw "Pi version probe did not return a semantic version: $($output.Trim())" }
    return [pscustomobject]@{ Version = [version]$match.Groups[1].Value; Raw = $output.Trim() }
}

$piPath = Resolve-PiCommand
if (-not $piPath) {
    throw "Pi is not installed or not resolvable. Run: pwsh -NoLogo -NoProfile -File tooling/pi/Install-AgentSwitchboardPi.ps1 -Mode Install"
}
$piVersion = Get-PiVersion -PiPath $piPath
if ($piVersion.Version -ne $expectedVersion) {
    throw "Pi version mismatch. Expected $expectedVersion; found $($piVersion.Version). Run the repository installer to repair the pinned version."
}

if (-not $EnableTelemetry) { $env:PI_TELEMETRY = '0' }
else { Remove-Item Env:PI_TELEMETRY -ErrorAction SilentlyContinue }

if (-not $AllowVersionCheck) { $env:PI_SKIP_VERSION_CHECK = '1' }
else { Remove-Item Env:PI_SKIP_VERSION_CHECK -ErrorAction SilentlyContinue }

if ($Offline) { $env:PI_OFFLINE = '1' }
else { Remove-Item Env:PI_OFFLINE -ErrorAction SilentlyContinue }

if ($IsWindows -and $env:LOCALAPPDATA) {
    $stateRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard/PiHarness'
}
else {
    $baseState = if ($env:XDG_STATE_HOME) { $env:XDG_STATE_HOME } else { Join-Path $HOME '.local/state' }
    $stateRoot = Join-Path $baseState 'AgentSwitchboard/PiHarness'
}
$sessionRoot = Join-Path $stateRoot 'sessions'
$runRoot = Join-Path $stateRoot ('runs/{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8)))
$null = New-Item -ItemType Directory -Path $sessionRoot -Force
$null = New-Item -ItemType Directory -Path $runRoot -Force
$env:PI_CODING_AGENT_SESSION_DIR = $sessionRoot

$branch = (& git -C $RootPath branch --show-current 2>$null | Select-Object -First 1)
$head = (& git -C $RootPath rev-parse HEAD 2>$null | Select-Object -First 1)
$dirty = [bool](& git -C $RootPath status --short 2>$null)
$summaryPath = Join-Path $runRoot 'pi-launch-summary.json'
$summary = [ordered]@{
    schema = 'agentswitchboard.pi-launch-result.v1'
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    completedAt = $null
    status = 'running'
    repositoryRoot = $RootPath
    branch = [string]$branch
    head = [string]$head
    dirty = $dirty
    pi = [ordered]@{ path = $piPath; version = $piVersion.Version.ToString() }
    projectSettings = '.pi/settings.json'
    projectTrust = 'operator-interactive; never bypassed by this launcher'
    telemetry = if ($EnableTelemetry) { 'operator-enabled' } else { 'disabled' }
    versionCheck = if ($AllowVersionCheck) { 'operator-enabled' } else { 'disabled' }
    offline = [bool]$Offline
    sessionRoot = $sessionRoot
    argumentCount = @($PiArguments).Count
    rawArgumentsRecorded = $false
    rawPromptRecorded = $false
    exitCode = $null
    proofLevel = 'runtime-command-invocation'
    proofCeiling = 'Exact pinned Pi executable invocation from the repository root with project settings and low-noise environment controls. Provider authentication, model identity, response quality, privacy, extension behavior, code mutation, and delivery remain runtime evidence.'
    error = $null
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' AgentSwitchboard Pi' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Repository:    $RootPath"
Write-Host "Branch:        $branch"
Write-Host "HEAD:          $head"
Write-Host "Pi:            $($piVersion.Raw)"
Write-Host "Telemetry:     $($summary.telemetry)"
Write-Host "Version check: $($summary.versionCheck)"
Write-Host "Offline:       $Offline"
Write-Host "Sessions:      $sessionRoot"
Write-Host ''
Write-Host 'Pi may ask whether to trust this repository before loading project-local skills.' -ForegroundColor Yellow
Write-Host 'Review the prompt and approve only when the repository identity above is expected.' -ForegroundColor Yellow
Write-Host 'Authentication remains interactive; use /login or an explicitly configured provider.' -ForegroundColor Yellow
Write-Host ''

try {
    Push-Location -LiteralPath $RootPath
    try {
        & $piPath @PiArguments
        $summary.exitCode = $LASTEXITCODE
        if ($LASTEXITCODE -ne 0) {
            throw "Pi exited with code $LASTEXITCODE."
        }
        $summary.status = 'success'
    }
    finally {
        Pop-Location
    }
}
catch {
    $summary.status = 'failed'
    $summary.error = $_.Exception.ToString()
    Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
    $summary.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    Write-Host "Pi launch summary: $summaryPath"
}

if ($summary.status -ne 'success') { exit 1 }
exit 0
