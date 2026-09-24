[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Base = Join-Path $RepoRoot 'tooling/profiles/windows/harness/agent-fleet-readiness'
$Required = @(
    'tooling/profiles/windows/harness/agent-fleet-readiness/readiness-boundary.contract.json',
    'tooling/profiles/windows/harness/agent-fleet-readiness/artifact-registry.json',
    'tooling/profiles/windows/harness/agent-fleet-readiness/fixtures/readiness-boundary-cases.json',
    'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/prove-readiness-through-powershell.workflow.json',
    'tooling/profiles/windows/Get-AgentFleetReadinessBoundary.ps1',
    'tests/test_agent_fleet_readiness_boundary.py',
    'docs/harness/agent-fleet-readiness-boundary.md',
    '.github/workflows/agent-fleet-readiness-boundary.yml'
)
foreach ($Relative in $Required) {
    $Path = Join-Path $RepoRoot $Relative
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing readiness-boundary file: $Relative" }
    & git -C $RepoRoot ls-files --error-unmatch -- $Relative *> $null
    if ($LASTEXITCODE -ne 0) { throw "Readiness-boundary file is not tracked: $Relative" }
}

$Python = Get-Command python -ErrorAction SilentlyContinue
if (-not $Python) { $Python = Get-Command python3 -ErrorAction Stop }
& $Python.Source (Join-Path $RepoRoot 'tests/test_agent_fleet_readiness_boundary.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Status = Join-Path $RepoRoot 'tooling/profiles/windows/Get-AgentFleetReadinessBoundary.ps1'
$cases = @(
    @{ Name='empty'; State=$false; Operator=$false; Shim=$false; Exit=$null; Evidence=$null; Expected='not-bootstrapped' },
    @{ Name='state-only'; State=$true; Operator=$false; Shim=$true; Exit=$null; Evidence=$null; Expected='partial-or-inconsistent' },
    @{ Name='healthy-authority-no-shim'; State=$true; Operator=$true; Shim=$false; Exit=$null; Evidence=$null; Expected='cmd-shim-blocked' },
    @{ Name='healthy-authority-shim'; State=$true; Operator=$true; Shim=$true; Exit=$null; Evidence=$null; Expected='installed-unclassified' },
    @{ Name='shim-exit-five'; State=$true; Operator=$true; Shim=$true; Exit=5; Evidence='Access is denied.'; Expected='cmd-shim-blocked' }
)
foreach ($case in $cases) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('asb-fleet-boundary-' + [guid]::NewGuid().ToString('N'))
    $out = Join-Path $root 'out'
    $null = New-Item -ItemType Directory -Path $root -Force
    try {
        if ($case.State) { '{}' | Set-Content -LiteralPath (Join-Path $root 'state.json') -Encoding utf8 }
        if ($case.Operator) { '# fixture' | Set-Content -LiteralPath (Join-Path $root 'Start-AgentSwitchboard.ps1') -Encoding utf8 }
        if ($case.Shim) { '@echo off' | Set-Content -LiteralPath (Join-Path $root 'agent-switchboard.cmd') -Encoding ascii }
        $args = @('-NoLogo','-NoProfile','-File',$Status,'-InstallRoot',$root,'-Emit','Json','-OutputRoot',$out)
        if ($null -ne $case.Exit) { $args += @('-CmdShimExitCode',[string]$case.Exit) }
        if ($case.Evidence) { $args += @('-CmdShimEvidence',[string]$case.Evidence) }
        $payload = (& pwsh @args | Out-String) | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw "Boundary reporter failed for $($case.Name)" }
        if ($payload.classification -ne $case.Expected) { throw "$($case.Name): expected $($case.Expected), got $($payload.classification)" }
        if ($payload.tracked -ne $false) { throw "$($case.Name): generated status is marked tracked" }
        if (-not $payload.startupReadinessCommand.Contains($root)) { throw "$($case.Name): startup reporter lost InstallRoot" }
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'PASS: agent-fleet readiness boundary'
