[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$MapPath = Join-Path $RepoRoot 'tooling/profiles/windows/harness/machine-profile/codebase-map.json'
$Map = Get-Content -LiteralPath $MapPath -Raw | ConvertFrom-Json
$Ops = $Map.operationalHarness

foreach ($Relative in @($Ops.requiredTracked)) {
    $Path = Join-Path $RepoRoot ([string]$Relative)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing machine-profile operational file: $Relative" }
    & git -C $RepoRoot ls-files --error-unmatch -- ([string]$Relative) *> $null
    if ($LASTEXITCODE -ne 0) { throw "Machine-profile operational file is not tracked: $Relative" }
}

$Roles = Get-Content -LiteralPath (Join-Path $RepoRoot ([string]$Ops.roleRegistry)) -Raw | ConvertFrom-Json
$ExpectedRoles = @('personal-windows-laptop','desktop-workstation','admin-box-1','admin-box-2')
$ActualRoles = @($Roles.roles | ForEach-Object { [string]$_.roleId } | Sort-Object)
if (($ActualRoles -join '|') -ne (($ExpectedRoles | Sort-Object) -join '|')) { throw "Environment-role set drifted: $($ActualRoles -join ', ')" }
foreach ($Role in @($Roles.roles)) {
    if ($Role.selectionMode -ne 'explicit-or-local-binding') { throw "Role can be inferred: $($Role.roleId)" }
    if ($Role.repositoryPathSource -ne 'machine-profile:pathRoles.developmentCheckout') { throw "Role owns stale path policy: $($Role.roleId)" }
    if ($Role.committedResolvedPathAllowed -ne $false) { throw "Role allows committed local path: $($Role.roleId)" }
}
$RoleText = Get-Content -LiteralPath (Join-Path $RepoRoot ([string]$Ops.roleRegistry)) -Raw
if ($RoleText -match [regex]::Escape('%USERPROFILE%\Desktop\Dev')) { throw 'Historical Desktop path policy was revived.' }

$Artifacts = Get-Content -LiteralPath (Join-Path $RepoRoot ([string]$Ops.artifactRegistry)) -Raw | ConvertFrom-Json
foreach ($Artifact in @($Artifacts.generatedArtifacts)) { if ($Artifact.tracked -ne $false) { throw "Generated artifact is tracked: $($Artifact.id)" } }
$Workflows = Get-Content -LiteralPath (Join-Path $RepoRoot ([string]$Ops.workflowSpecs)) -Raw | ConvertFrom-Json
$ExpectedWorkflows = @('machine-profile-task-intake','machine-profile-validation','machine-profile-failure-recovery','machine-profile-handoff')
$ActualWorkflows = @($Workflows.workflows | ForEach-Object { [string]$_.workflowId } | Sort-Object)
if (($ActualWorkflows -join '|') -ne (($ExpectedWorkflows | Sort-Object) -join '|')) { throw 'Operational workflow set drifted.' }

$Python = Get-Command python -ErrorAction SilentlyContinue
if (-not $Python) { $Python = Get-Command python3 -ErrorAction Stop }
& $Python.Source (Join-Path $RepoRoot 'tests/test_machine_profile_operational_harness.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Temp = Join-Path ([IO.Path]::GetTempPath()) ('AgentSwitchboard-machine-profile-ops-' + [guid]::NewGuid().ToString('N'))
try {
    $StatusScript = Join-Path $RepoRoot ([string]$Ops.statusReporter)
    & pwsh -NoLogo -NoProfile -File $StatusScript -RepoRoot $RepoRoot -EnvironmentRoleId 'admin-box-1' -Emit Json -OutputRoot $Temp | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Operational status reporter failed.' }
    $StatusPath = Join-Path $Temp 'machine-profile-operational-status.json'
    if (-not (Test-Path -LiteralPath $StatusPath -PathType Leaf)) { throw 'Operational status JSON was not generated.' }
    $Status = Get-Content -LiteralPath $StatusPath -Raw | ConvertFrom-Json
    if ($Status.status -ne 'ready' -or $Status.roleStatus -ne 'selected' -or $Status.environmentRoleId -ne 'admin-box-1') { throw 'Operational status payload is inconsistent.' }
    if ($Status.tracked -ne $false) { throw 'Operational status artifact is marked tracked.' }
}
finally { Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host 'PASS: machine-profile operational harness'
