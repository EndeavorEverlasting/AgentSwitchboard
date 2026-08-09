[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check {
    param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Name,[AllowEmptyString()][string]$Message='')
    if ($Condition) { [void]$passes.Add($Name) } else { [void]$failures.Add("$Name`: $Message") }
}

function Read-Tracked {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $RootPath $RelativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    Check $exists "file/$RelativePath" 'required file is missing'
    if (-not $exists) { return $null }
    $null = & git -C $RootPath ls-files --error-unmatch -- $RelativePath 2>$null
    Check ($LASTEXITCODE -eq 0) "tracked/$RelativePath" 'required file is not tracked'
    return Get-Content -LiteralPath $path -Raw
}

$requiredFiles = @(
    'CODEBASE_MAP.md',
    'SKILLS.md',
    'TRIGGERS.md',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/codebase-map.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/runtime-resolution.registry.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/artifact-registry.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/composition.graph.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/workflows/runtime-resolution-intake.workflow.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/workflows/path-collision-diagnosis.workflow.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/schemas/opencode-runtime-resolution.schema.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/fixtures/valid-native-windows.fixture.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/fixtures/valid-declared-wsl.fixture.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/fixtures/invalid-shim-shadowing.fixture.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/fixtures/invalid-wsl-missing-target.fixture.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/fixtures/invalid-wsl-state-drift.fixture.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/operator-report.template.md',
    '.ai/skills/opencode-runtime-resolution/SKILL.md',
    'tooling/profiles/windows/Get-OpenCodeRuntimeResolutionStatus.ps1',
    'tooling/profiles/windows/hooks/Invoke-OpenCodeRuntimeResolutionPreCommit.ps1',
    'tests/test_opencode_runtime_resolution_harness.py',
    'docs/harness/opencode-runtime-resolution-harness.md',
    '.github/workflows/opencode-runtime-resolution-harness.yml'
)

$text = @{}
foreach ($relativePath in $requiredFiles) { $text[$relativePath] = Read-Tracked -RelativePath $relativePath }

foreach ($relativePath in @($requiredFiles | Where-Object { $_ -like '*.json' })) {
    if ($null -eq $text[$relativePath]) { continue }
    try { $null = $text[$relativePath] | ConvertFrom-Json; Check $true "json/$relativePath" '' }
    catch { Check $false "json/$relativePath" $_.Exception.Message }
}

try {
    $registry = $text['tooling/profiles/windows/harness/opencode-runtime-resolution/runtime-resolution.registry.json'] | ConvertFrom-Json
    Check ($registry.schema -eq 'agentswitchboard.opencode-runtime-resolution-registry.v1') 'registry/schema' 'unexpected schema'
    Check ($registry.status -eq 'tracked-diagnostic-contract') 'registry/status' 'unexpected status'
    Check (-not ([bool]$registry.evidenceRules.resolvedConfigProvesExecutableIdentity)) 'registry/config-not-proof' 'resolved config is overclaimed'
    Check (-not ([bool]$registry.evidenceRules.parentGetCommandProvesChildIdentity)) 'registry/parent-not-child-proof' 'parent discovery is overclaimed'
    Check ([bool]$registry.evidenceRules.exactOperatorOrAgentLaunchChainRequiredForRuntimeProof) 'registry/exact-chain' 'exact chain is not required'
    Check ([bool]$registry.evidenceRules.wrapperTargetRequiredWhenWrapperSelected) 'registry/wrapper-target' 'wrapper target is optional'
    Check (-not ([bool]$registry.repairBoundary.harnessMayMutatePath)) 'registry/no-path-mutation' 'harness may mutate PATH'
    Check (-not ([bool]$registry.repairBoundary.harnessMayInstallPackages)) 'registry/no-package-install' 'harness may install packages'
    $classificationIds = @($registry.classifications | ForEach-Object { [string]$_.classificationId })
    foreach ($id in @('native-consistent','declared-wsl-consistent','shim-shadowing-native','parent-child-divergence','state-command-drift','unresolved-runtime-identity')) {
        Check ($classificationIds -contains $id) "registry/classification/$id" 'classification is missing'
    }
}
catch { [void]$failures.Add("registry/semantic: $($_.Exception.Message)") }

try {
    $graph = $text['tooling/profiles/windows/harness/opencode-runtime-resolution/composition.graph.json'] | ConvertFrom-Json
    $nodeIds = @($graph.nodes | ForEach-Object { [string]$_.id })
    $edgeIds = @($graph.edges | ForEach-Object { [string]$_.id })
    foreach ($id in @('skill.opencode-runtime-resolution','registry.opencode-runtime-resolution','workflow.opencode-runtime-intake','workflow.opencode-path-collision','validator.opencode-runtime-resolution','artifact.opencode-runtime-classification','report.opencode-runtime-operator','handoff.opencode-runtime')) {
        Check ($nodeIds -contains $id) "graph/node/$id" 'node is missing'
    }
    foreach ($id in @('edge.trigger-skill','edge.skill-registry','edge.skill-intake','edge.intake-collision','edge.registry-validator','edge.collision-classification','edge.classification-report','edge.report-handoff')) {
        Check ($edgeIds -contains $id) "graph/edge/$id" 'edge is missing'
    }
}
catch { [void]$failures.Add("graph/semantic: $($_.Exception.Message)") }

$skill = $text['.ai/skills/opencode-runtime-resolution/SKILL.md']
foreach ($token in @(
    'id: opencode-runtime-resolution',
    'status: canonical',
    '## Trigger',
    '## Inputs',
    '## Procedure',
    '## Outputs',
    '## Deterministic validation',
    '## Forbidden scope',
    '## Stop and escalate',
    'opencode debug config',
    'shim-shadowing-native',
    'end-to-end-runtime-validation',
    'No user or machine PATH mutation'
)) { Check ($skill.Contains($token)) "skill/$token" 'required skill rule is missing' }

$skillsCatalog = $text['SKILLS.md']
foreach ($token in @('opencode-runtime-resolution', '.ai/skills/opencode-runtime-resolution/SKILL.md', 'OpenCode', 'WSL')) {
    Check ($skillsCatalog.Contains($token)) "skills-catalog/$token" 'canonical skill is not discoverable'
}
$triggerCatalog = $text['TRIGGERS.md']
foreach ($token in @('opencode.runtime-resolution-divergence', 'opencode-runtime-resolution', 'uv_spawn')) {
    Check ($triggerCatalog.Contains($token)) "trigger-catalog/$token" 'OpenCode runtime-resolution trigger is not registered'
}
$codebaseMap = $text['CODEBASE_MAP.md']
foreach ($token in @('## OpenCode runtime-resolution harness', 'opencode-runtime-resolution', 'Get-OpenCodeRuntimeResolutionStatus.ps1')) {
    Check ($codebaseMap.Contains($token)) "codebase-map/$token" 'OpenCode runtime-resolution harness is not indexed'
}

$guide = $text['docs/harness/opencode-runtime-resolution-harness.md']
foreach ($token in @('## Working','## Broken','## Missing','## Known traps','## Validation','## Proof ceiling','AgentSwitchboard\bin\opencode.cmd','%APPDATA%\npm')) {
    Check ($guide.Contains($token)) "guide/$token" 'operator guide token is missing'
}

$deployableText = @(
    $text['tooling/profiles/windows/harness/opencode-runtime-resolution/codebase-map.json'],
    $text['tooling/profiles/windows/harness/opencode-runtime-resolution/runtime-resolution.registry.json'],
    $text['tooling/profiles/windows/harness/opencode-runtime-resolution/workflows/runtime-resolution-intake.workflow.json'],
    $text['tooling/profiles/windows/harness/opencode-runtime-resolution/workflows/path-collision-diagnosis.workflow.json'],
    $skill,
    $guide
) -join "`n"
foreach ($forbidden in @('SetEnvironmentVariable(','npm install --global','Invoke-WebRequest','Remove-Item -LiteralPath $shim','wsl --install')) {
    Check (-not $deployableText.Contains($forbidden)) "forbidden/$forbidden" 'harness embeds workstation mutation'
}

if ($failures.Count -eq 0) {
    & python (Join-Path $RootPath 'tests/test_opencode_runtime_resolution_harness.py')
    Check ($LASTEXITCODE -eq 0) 'python/contracts' 'dependency-free semantic contracts failed'
}

if ($failures.Count -eq 0) {
    $reportRoot = Join-Path ([IO.Path]::GetTempPath()) ('AgentSwitchboard-OpenCodeRuntimeResolution-contract-' + [guid]::NewGuid().ToString('N'))
    try {
        & pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'tooling\profiles\windows\Get-OpenCodeRuntimeResolutionStatus.ps1') -RootPath $RootPath -RequestedSurface unknown -OutputRoot $reportRoot
        Check ($LASTEXITCODE -eq 0) 'reporter/exit-zero' 'repository-only reporter failed'

        $snapshotPath = Join-Path $reportRoot 'opencode-runtime-resolution-snapshot.json'
        $reportPath = Join-Path $reportRoot 'opencode-runtime-operator-report.md'
        Check (Test-Path -LiteralPath $snapshotPath -PathType Leaf) 'reporter/snapshot-exists' 'snapshot was not generated'
        Check (Test-Path -LiteralPath $reportPath -PathType Leaf) 'reporter/report-exists' 'operator report was not generated'

        if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
            $snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
            Check ($snapshot.schema -eq 'agentswitchboard.opencode-runtime-resolution-snapshot.v1') 'reporter/schema' 'snapshot schema is not registered'
            Check ($snapshot.requestedSurface -eq 'unknown') 'reporter/requested-surface' 'requested surface is missing or rewritten'
            Check ($null -eq $snapshot.parentResolution) 'reporter/parent-null-without-observation' 'repository-only status invented parent resolution'
            Check ($null -eq $snapshot.effectiveLaunchResolution) 'reporter/child-unresolved' 'repository-only status invented child resolution'
            Check (-not [bool]$snapshot.processPathCaptured) 'reporter/path-not-captured' 'repository-only status falsely claims PATH capture'
            Check (-not [bool]$snapshot.tracked) 'reporter/untracked-artifact' 'runtime artifact is marked tracked'
            Check ($snapshot.repositoryHarnessStatus -eq 'ready') 'reporter/readiness' 'reporter did not establish complete tracked harness readiness'
        }
        if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
            $reportText = Get-Content -LiteralPath $reportPath -Raw
            foreach ($heading in @('## Working','## Broken','## Missing','## Proof ceiling')) {
                Check ($reportText.Contains($heading)) "reporter/$heading" 'operator report section is missing'
            }
        }
    }
    catch {
        [void]$failures.Add("reporter/runtime-contract: $($_.Exception.Message)")
    }
    finally {
        if (Test-Path -LiteralPath $reportRoot) { Remove-Item -LiteralPath $reportRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host 'OPENCODE RUNTIME RESOLUTION HARNESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
