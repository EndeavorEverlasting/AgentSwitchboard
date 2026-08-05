[CmdletBinding()]
param(
    [ValidateSet('Human','Json')][string]$Emit = 'Human',
    [string]$OutputRoot,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$now = Get-Date
$runId = '{0}-{1}' -f $now.ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0,8))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard\machine-profile-harness\$runId"
}
$null = New-Item -ItemType Directory -Path $OutputRoot -Force

$manifestRelative = 'tooling/profiles/windows/harness/machine-profile/manifest.json'
$manifestPath = Join-Path $RepoRoot $manifestRelative
$loadErrors = [System.Collections.Generic.List[string]]::new()
$missing = [System.Collections.Generic.List[string]]::new()
$trackedMissing = [System.Collections.Generic.List[string]]::new()
$required = @()
$roleIds = @()
$proofCeiling = 'Harness status reporting only; runtime behavior is not proven.'
$nextCommand = 'Test-MachineProfileHarness.cmd'
$manifest = $null

try {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        [void]$missing.Add($manifestRelative)
        throw "Harness manifest is missing: $manifestPath"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $keys = @('codebaseMap','machineProfileRegistry','environmentRoleRegistry','knownTrapsRegistry','artifactRegistry','workflowSpecs','schemaPath','skill','operatorDocumentation','operatorReportTemplate','statusReporter','statusCommand','validator','validatorCommand','pythonValidator','candidateValidator','candidateValidatorCommand','preCommitHook','ciWorkflow')
    $required = @($keys | ForEach-Object { [string]$manifest.$_ })
    $proofCeiling = [string]$manifest.proofCeiling
    $nextCommand = [string]$manifest.validatorCommand
}
catch {
    [void]$loadErrors.Add($_.Exception.Message)
}

foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf)) {
        [void]$missing.Add($relative)
    }
}

$git = Get-Command git -ErrorAction SilentlyContinue
if ($git -and $required.Count) {
    foreach ($relative in $required) {
        & $git.Source -C $RepoRoot ls-files --error-unmatch -- $relative *> $null
        if ($LASTEXITCODE -ne 0) { [void]$trackedMissing.Add($relative) }
    }
}

if ($manifest -and -not [string]::IsNullOrWhiteSpace([string]$manifest.environmentRoleRegistry)) {
    $rolePath = Join-Path $RepoRoot ([string]$manifest.environmentRoleRegistry)
    if (Test-Path -LiteralPath $rolePath -PathType Leaf) {
        try {
            $roles = Get-Content -LiteralPath $rolePath -Raw | ConvertFrom-Json
            $roleIds = @($roles.roles | ForEach-Object { [string]$_.roleId })
        }
        catch {
            [void]$loadErrors.Add("Environment-role registry is malformed: $($_.Exception.Message)")
        }
    }
}

$status = if ($missing.Count -eq 0 -and $trackedMissing.Count -eq 0 -and $loadErrors.Count -eq 0) { 'ready' } else { 'incomplete' }
$result = [ordered]@{
    schema = 'agentswitchboard.machine-profile-harness-status.v1'
    generatedAt = $now.ToUniversalTime().ToString('o')
    status = $status
    repositoryRoot = $RepoRoot
    requiredCount = $required.Count
    presentCount = $required.Count - $missing.Count
    missing = @($missing)
    trackedMissing = @($trackedMissing)
    loadErrors = @($loadErrors)
    environmentRoles = $roleIds
    proofCeiling = $proofCeiling
    nextCommand = $nextCommand
}
$jsonPath = Join-Path $OutputRoot 'machine-profile-harness-status.json'
$mdPath = Join-Path $OutputRoot 'machine-profile-harness-status.md'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM
@(
    '# Windows Machine-Profile Harness Status',
    '',
    "- Status: **$status**",
    "- Components: $($result.presentCount)/$($result.requiredCount)",
    "- Roles: $(if($roleIds.Count){$roleIds -join ', '}else{'unavailable'})",
    "- Missing: $(if($missing.Count){$missing -join ', '}else{'none'})",
    "- Untracked: $(if($trackedMissing.Count){$trackedMissing -join ', '}else{'none'})",
    "- Load errors: $(if($loadErrors.Count){$loadErrors -join ' | '}else{'none'})",
    '',
    '## Proof ceiling',
    '',
    $proofCeiling,
    '',
    '## Exact next command',
    '',
    '```cmd',
    $nextCommand,
    '```'
) | Set-Content -LiteralPath $mdPath -Encoding utf8NoBOM

if ($Emit -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-Host "Machine-profile harness: $status"
    Write-Host "Components: $($result.presentCount)/$($result.requiredCount)"
    Write-Host "Roles: $(if($roleIds.Count){$roleIds -join ', '}else{'unavailable'})"
    Write-Host "JSON: $jsonPath"
    Write-Host "Report: $mdPath"
    Write-Host "NEXT COMMAND: $nextCommand"
}

if ($status -ne 'ready') {
    throw "Machine-profile harness is incomplete. Review $mdPath"
}
