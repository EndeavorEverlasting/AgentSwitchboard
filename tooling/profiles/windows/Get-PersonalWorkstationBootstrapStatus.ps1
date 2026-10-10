[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('desktop-workstation', 'personal-windows-laptop')]
    [string]$EnvironmentRoleId,

    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This is a non-mutating package/CLI discovery report. Installation and
# authentication belong to existing product- and provider-owned entrypoints.
$contractPath = Join-Path $PSScriptRoot 'harness/machine-profile/personal-workstation-bootstrap.v1.json'
$rolesPath = Join-Path $PSScriptRoot 'harness/machine-profile/environment-role.registry.json'
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$roles = Get-Content -LiteralPath $rolesPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($contract.schema -ne 'agentswitchboard.personal-workstation-bootstrap.v1') {
    throw "Unsupported personal workstation bootstrap contract schema: $($contract.schema)"
}
if ($EnvironmentRoleId -notin @($contract.roles)) {
    throw "Role '$EnvironmentRoleId' is not allowed by the personal-workstation contract."
}
if ($EnvironmentRoleId -notin @($roles.roles | ForEach-Object { $_.roleId })) {
    throw "Role '$EnvironmentRoleId' is missing from the canonical environment-role registry."
}
if (-not $OutputRoot) {
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
    $OutputRoot = Join-Path $base 'AgentSwitchboard/personal-workstation-bootstrap/runs'
}
$runId = '{0}-{1}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'), [Guid]::NewGuid().ToString('N').Substring(0,8)
$runDir = Join-Path $OutputRoot $runId
$null = New-Item -ItemType Directory -Path $runDir -Force

$stageResults = @(
    foreach ($stage in $contract.stages) {
        $observations = @(
            foreach ($component in $stage.components) {
                # Existence on PATH is not validation of version, auth, or ability to run.
                $command = Get-Command -Name ([string]$component.command) -ErrorAction SilentlyContinue | Select-Object -First 1
                [pscustomobject]@{
                    id = [string]$component.id
                    command = [string]$component.command
                    necessity = [string]$component.necessity
                    result = if ($command) { 'discovered-unverified' } else { 'not-found-on-path' }
                    resolvedPath = if ($command) { [string]$command.Source } else { $null }
                    version = $null
                    authenticated = $null
                }
            }
        )
        $missingCore = @($observations | Where-Object { $_.necessity -eq 'core' -and $_.result -eq 'not-found-on-path' })
        [pscustomobject]@{
            id = [string]$stage.id
            platform = [string]$stage.platform
            dependencies = @($stage.dependencies)
            componentObservations = $observations
            status = if ($missingCore.Count -gt 0) { 'needs-prerequisites' } elseif ($observations.Count -eq 0) { 'manual-gate' } else { 'discovery-only' }
            proofCeiling = 'PATH discovery only; versions, auth, installer success, and live agent functionality not verified'
        }
    }
)

$summary = [ordered]@{
    schema = 'agentswitchboard.personal-workstation-bootstrap-status.v1'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    environmentRoleId = $EnvironmentRoleId
    runId = $runId
    mode = 'inspect-only'
    contract = 'tooling/profiles/windows/harness/machine-profile/personal-workstation-bootstrap.v1.json'
    stages = $stageResults
    proofCeiling = 'PATH discovery on the inspected host, not version/auth/setup certification'
    nextActionOwner = 'operator / canonical AgentSwitchboard installers'
    tracked = $false
}
$json = Join-Path $runDir 'status.json'
$markdown = Join-Path $runDir 'status.md'
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $json -Encoding utf8
$reportLines = @(
    '# Personal Workstation Bootstrap — Inspection',
    '',
    "Role: $EnvironmentRoleId",
    "Run: $runId",
    'Proof: command-discovery only, not installation or authentication.',
    ''
)
foreach ($s in $stageResults) {
    $reportLines += "## $($s.id) — $($s.status)"
    foreach ($c in $s.componentObservations) {
        $reportLines += "- $($c.id): $($c.result) ($($c.necessity))"
    }
    $reportLines += ''
}
$reportLines += @(
    '## Next action',
    'Follow docs/workstation/personal-development-workstation.md and the existing technician bootstrap.',
    'Installer and provider credentials are never collected by this inspection.',
    ''
)
$reportLines | Set-Content -LiteralPath $markdown -Encoding utf8
Write-Host 'Personal-workstation bootstrap: INSPECT ONLY'
foreach ($s in $stageResults) { Write-Host ('{0}: {1}' -f $s.id, $s.status) }
Write-Host "JSON: $json"
Write-Host "Report: $markdown"
Write-Host 'NEXT: run the code-now steps in docs/workstation/personal-development-workstation.md'
