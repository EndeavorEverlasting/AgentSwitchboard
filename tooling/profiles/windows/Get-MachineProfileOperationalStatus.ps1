[CmdletBinding()]
param(
    [ValidateSet('Human','Json')][string]$Emit = 'Human',
    [string]$OutputRoot,
    [string]$RepoRoot,
    [string]$EnvironmentRoleId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$now = Get-Date
$runId = '{0}-{1}' -f $now.ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0,8))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard/machine-profile-harness/$runId" }
$null = New-Item -ItemType Directory -Path $OutputRoot -Force

$mapPath = Join-Path $RepoRoot 'tooling/profiles/windows/harness/machine-profile/codebase-map.json'
$map = Get-Content -LiteralPath $mapPath -Raw | ConvertFrom-Json
$ops = $map.operationalHarness
$missing = [System.Collections.Generic.List[string]]::new()
$untracked = [System.Collections.Generic.List[string]]::new()
foreach ($relative in @($ops.requiredTracked)) {
    $full = Join-Path $RepoRoot ([string]$relative)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { [void]$missing.Add([string]$relative); continue }
    & git -C $RepoRoot ls-files --error-unmatch -- ([string]$relative) *> $null
    if ($LASTEXITCODE -ne 0) { [void]$untracked.Add([string]$relative) }
}

$roles = Get-Content -LiteralPath (Join-Path $RepoRoot ([string]$ops.roleRegistry)) -Raw | ConvertFrom-Json
$roleIds = @($roles.roles | ForEach-Object { [string]$_.roleId })
$roleStatus = 'unresolved'
if (-not [string]::IsNullOrWhiteSpace($EnvironmentRoleId)) {
    if ($roleIds -notcontains $EnvironmentRoleId) { throw "Unknown environment role: $EnvironmentRoleId" }
    $roleStatus = 'selected'
}
$status = if ($missing.Count -eq 0 -and $untracked.Count -eq 0) { 'ready' } else { 'incomplete' }
$validatorPath = Join-Path $RepoRoot ([string]$ops.validator)
$nextCommand = 'pwsh -NoLogo -NoProfile -File "' + $validatorPath + '"'
$result = [ordered]@{
    schema = 'agentswitchboard.machine-profile-operational-status.v1'
    generatedAt = $now.ToUniversalTime().ToString('o')
    status = $status
    environmentRoleId = if ($roleStatus -eq 'selected') { $EnvironmentRoleId } else { $null }
    roleStatus = $roleStatus
    availableRoles = $roleIds
    repositoryRootSource = 'current machine-profile detector/pathRoles.developmentCheckout'
    missing = @($missing)
    untracked = @($untracked)
    proofCeiling = [string]$ops.proofCeiling
    nextActionOwner = 'repository validation owner'
    nextActionDependency = 'tracked operational harness at the resolved repository root'
    nextCommand = $nextCommand
    tracked = $false
}
$jsonPath = Join-Path $OutputRoot 'machine-profile-operational-status.json'
$mdPath = Join-Path $OutputRoot 'machine-profile-operational-status.md'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8
@(
    '# Machine-Profile Operational Status',
    '',
    "- Harness: **$status**",
    "- Role selection: **$roleStatus**",
    "- Environment role: $(if($result.environmentRoleId){$result.environmentRoleId}else{'unresolved'})",
    "- Repository-root source: $($result.repositoryRootSource)",
    "- Missing: $(if($missing.Count){$missing -join ', '}else{'none'})",
    "- Untracked: $(if($untracked.Count){$untracked -join ', '}else{'none'})",
    '',
    '## Proof ceiling',
    '',
    $result.proofCeiling,
    '',
    '## Exact next action',
    '',
    "- Owner: $($result.nextActionOwner)",
    "- Dependency: $($result.nextActionDependency)",
    '',
    '```powershell',
    $nextCommand,
    '```'
) | Set-Content -LiteralPath $mdPath -Encoding utf8

if ($Emit -eq 'Json') { $result | ConvertTo-Json -Depth 8 }
else {
    Write-Host "Machine-profile operational harness: $status"
    Write-Host "Role: $roleStatus $(if($EnvironmentRoleId){$EnvironmentRoleId}else{''})"
    Write-Host "JSON: $jsonPath"
    Write-Host "Report: $mdPath"
    Write-Host "NEXT COMMAND: $nextCommand"
}
if ($status -ne 'ready') { throw "Machine-profile operational harness is incomplete. Review $mdPath" }
