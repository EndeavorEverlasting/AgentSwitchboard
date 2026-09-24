[CmdletBinding()]
param(
    [string]$InstallRoot,
    [Nullable[int]]$CmdShimExitCode,
    [string]$CmdShimEvidence,
    [ValidateSet('Human','Json')][string]$Emit = 'Human',
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'InstallRoot is required when LOCALAPPDATA is unavailable.' }
    $InstallRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\GnhfFleet'
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$statePath = Join-Path $InstallRoot 'state.json'
$operatorPath = Join-Path $InstallRoot 'Start-AgentSwitchboard.ps1'
$shimPath = Join-Path $InstallRoot 'agent-switchboard.cmd'
$stateExists = Test-Path -LiteralPath $statePath -PathType Leaf
$operatorExists = Test-Path -LiteralPath $operatorPath -PathType Leaf
$shimExists = Test-Path -LiteralPath $shimPath -PathType Leaf

$classification = $null
$nextAction = $null
if (-not $stateExists -and -not $operatorExists) {
    $classification = 'not-bootstrapped'
    $nextAction = 'bootstrap-or-repair'
} elseif ($stateExists -xor $operatorExists) {
    $classification = 'partial-or-inconsistent'
    $nextAction = 'bootstrap-or-repair'
} else {
    $shimBlocked = -not $shimExists
    if ($null -ne $CmdShimExitCode -and [int]$CmdShimExitCode -eq 5) { $shimBlocked = $true }
    if (-not [string]::IsNullOrWhiteSpace($CmdShimEvidence) -and $CmdShimEvidence -match '(?i)access\s+is\s+denied') { $shimBlocked = $true }
    if ($shimBlocked) {
        $classification = 'cmd-shim-blocked'
        $nextAction = 'prove-readiness-through-powershell'
    } else {
        $classification = 'installed-unclassified'
        $nextAction = 'prove-readiness-through-powershell'
    }
}

$powerShellCommand = 'pwsh -NoLogo -NoProfile -File "' + $operatorPath + '" -ListAgents'
$startupReportCommand = 'pwsh -NoLogo -NoProfile -File tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1'
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard/agent-fleet-readiness/$runId" }
$null = New-Item -ItemType Directory -Path $OutputRoot -Force

$result = [ordered]@{
    schema = 'agentswitchboard.agent-fleet-readiness-boundary-status.v1'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    classification = $classification
    nextAction = $nextAction
    fleetStateExists = $stateExists
    powerShellOperatorExists = $operatorExists
    cmdShimExists = $shimExists
    cmdShimExitCode = if ($null -ne $CmdShimExitCode) { [int]$CmdShimExitCode } else { $null }
    cmdShimAccessDenied = (-not [string]::IsNullOrWhiteSpace($CmdShimEvidence) -and $CmdShimEvidence -match '(?i)access\s+is\s+denied')
    powerShellReadinessCommand = $powerShellCommand
    startupReadinessCommand = $startupReportCommand
    tracked = $false
    proofCeiling = 'Read-only installed-authority and compatibility-shim classification only; adapter/provider/runtime readiness is not proven.'
}
$jsonPath = Join-Path $OutputRoot 'agent-fleet-readiness-boundary.json'
$mdPath = Join-Path $OutputRoot 'agent-fleet-readiness-boundary.md'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8
@(
    '# Agent Fleet Readiness Boundary',
    '',
    "- Classification: **$classification**",
    "- Fleet state exists: $stateExists",
    "- PowerShell operator exists: $operatorExists",
    "- CMD shim exists: $shimExists",
    "- Next action: $nextAction",
    '',
    '## PowerShell readiness route',
    '',
    '```powershell',
    $powerShellCommand,
    '```',
    '',
    'Then use the current startup-readiness reporter:',
    '',
    '```powershell',
    $startupReportCommand,
    '```',
    '',
    '## Proof ceiling',
    '',
    $result.proofCeiling
) | Set-Content -LiteralPath $mdPath -Encoding utf8

if ($Emit -eq 'Json') { $result | ConvertTo-Json -Depth 8 }
else {
    Write-Host "Agent fleet boundary: $classification"
    Write-Host "JSON: $jsonPath"
    Write-Host "Report: $mdPath"
    Write-Host "NEXT: $nextAction"
    if ($nextAction -eq 'prove-readiness-through-powershell') { Write-Host "COMMAND: $powerShellCommand" }
}
