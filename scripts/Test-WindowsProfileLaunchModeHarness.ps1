[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$Message = ''
    )
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $Message") }
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
    'tooling/profiles/windows/harness/launch-modes/codebase-map.json',
    'tooling/profiles/windows/harness/launch-modes/launch-mode.registry.json',
    'tooling/profiles/windows/harness/launch-modes/artifact-registry.json',
    'tooling/profiles/windows/harness/launch-modes/workflows/launch-request-intake.workflow.json',
    'tooling/profiles/windows/harness/launch-modes/workflows/open-or-activate-verification.workflow.json',
    'tooling/profiles/windows/harness/launch-modes/workflows/new-instance-verification.workflow.json',
    'tooling/profiles/windows/harness/launch-modes/workflows/duplicate-window-diagnosis.workflow.json',
    'tooling/profiles/windows/harness/launch-modes/schemas/windows-launch-mode-harness.schema.json',
    'tooling/profiles/windows/harness/launch-modes/fixtures/valid-open-or-activate.fixture.json',
    'tooling/profiles/windows/harness/launch-modes/fixtures/valid-new-instance.fixture.json',
    'tooling/profiles/windows/harness/launch-modes/fixtures/invalid-duplicate-burst.fixture.json',
    '.ai/skills/windows-profile-launch-mode-validation/SKILL.md',
    'tooling/profiles/windows/Get-WindowsProfileLaunchModeStatus.ps1',
    'tooling/profiles/windows/hooks/Invoke-WindowsProfileLaunchModePreCommit.ps1',
    'tests/test_windows_profile_launch_mode_harness.py',
    'docs/harness/windows-profile-launch-mode-harness.md',
    '.github/workflows/windows-profile-launch-mode-harness.yml',
    '.ai/harness/manifest.json',
    '.ai/harness/artifact-registry.json',
    '.ai/harness/app-composition.graph.json',
    'CODEBASE_MAP.md',
    'SKILLS.md',
    'TRIGGERS.md'
)

$text = @{}
foreach ($relativePath in $requiredFiles) {
    $text[$relativePath] = Read-Tracked -RelativePath $relativePath
}

$jsonPaths = @($requiredFiles | Where-Object { $_ -like '*.json' })
foreach ($relativePath in $jsonPaths) {
    try {
        $null = $text[$relativePath] | ConvertFrom-Json
        Check $true "json/$relativePath" ''
    }
    catch {
        Check $false "json/$relativePath" $_.Exception.Message
    }
}

try {
    $registry = $text['tooling/profiles/windows/harness/launch-modes/launch-mode.registry.json'] | ConvertFrom-Json
    $modes = @($registry.modes)
    $open = @($modes | Where-Object modeId -eq 'open-or-activate')[0]
    $new = @($modes | Where-Object modeId -eq 'new-instance')[0]

    Check ($registry.schema -eq 'agentswitchboard.windows-profile-launch-mode-registry.v1') 'registry/schema' 'unexpected schema'
    Check ($registry.status -eq 'contract-only') 'registry/status' 'runtime implementation is overclaimed'
    Check ($registry.defaultMode -eq 'open-or-activate') 'registry/default' 'default mode differs'
    Check ([bool]$registry.sameCanonicalLauncherForAllModes) 'registry/one-launcher' 'competing launchers are allowed'
    Check (-not ([bool]$registry.rawFrontendInvocationAllowed)) 'registry/no-raw' 'raw frontend invocation is allowed'
    Check (($modes.modeId | Sort-Object) -join ',' -eq 'new-instance,open-or-activate') 'registry/modes' 'expected exactly two modes'
    Check ([bool]$open.sameIdentityConverges) 'registry/open-converges' 'open-or-activate does not converge'
    Check ([int]$open.maximumNewTopLevelWindows -eq 1) 'registry/open-window-cap' 'open-or-activate may create multiple windows'
    Check ([bool]$new.requiresExplicitRequest) 'registry/new-explicit' 'new-instance is implicit'
    Check ([bool]$new.requiresInstanceId) 'registry/new-id' 'new-instance ID is optional'
    Check ([bool]$new.tmuxSessionIdentityMustBeUnique) 'registry/new-tmux' 'new-instance may reuse the canonical tmux session'
    Check ([bool]$new.separateFrontendProcessRequired) 'registry/new-process' 'new-instance lacks process isolation'
    Check ([int]$new.maximumNewTopLevelWindows -eq 1) 'registry/new-window-cap' 'one request may create multiple windows'
    Check ([bool]$registry.duplicateDetection.oneRequestMayCreateAtMostOneTopLevelWindow) 'registry/duplicate-cap' 'duplicate burst is allowed'
    Check ([bool]$registry.duplicateDetection.rawProcessCountAloneIsInsufficient) 'registry/process-count' 'process count is treated as sufficient'
    Check (-not ([bool]$registry.runtimeEvidence.generatedEvidenceTracked)) 'registry/untracked' 'runtime evidence is tracked'
}
catch { [void]$failures.Add("registry/semantic: $($_.Exception.Message)") }

try {
    $manifest = $text['.ai/harness/manifest.json'] | ConvertFrom-Json
    Check ($manifest.entrypoints.windowsLaunchModeRegistry -eq 'tooling/profiles/windows/harness/launch-modes/launch-mode.registry.json') 'manifest/registry' 'registry entrypoint is missing'
    Check ($manifest.entrypoints.windowsLaunchModeValidator -eq 'scripts/Test-WindowsProfileLaunchModeHarness.ps1') 'manifest/validator' 'validator entrypoint is missing'
    Check ($manifest.entrypoints.windowsLaunchModeSkill -eq '.ai/skills/windows-profile-launch-mode-validation/SKILL.md') 'manifest/skill' 'skill entrypoint is missing'
    Check ($manifest.windowsProfileLaunchModes.status -eq 'contract-only') 'manifest/status' 'runtime behavior is overclaimed'
    Check ($manifest.windowsProfileLaunchModes.defaultMode -eq 'open-or-activate') 'manifest/default' 'default mode differs'
    Check ($manifest.windowsProfileLaunchModes.explicitNewInstanceAllowed -eq $true) 'manifest/new-instance' 'explicit new-instance is missing'
    Check ($manifest.windowsProfileLaunchModes.generatedEvidenceTracked -eq $false) 'manifest/untracked' 'generated evidence is tracked'
    Check ($manifest.windowsProfileLaunchModes.runtimeExecutionAllowed -eq $false) 'manifest/no-runtime' 'contract validation permits runtime'
}
catch { [void]$failures.Add("manifest/semantic: $($_.Exception.Message)") }

try {
    $artifacts = @((($text['.ai/harness/artifact-registry.json'] | ConvertFrom-Json).artifacts))
    $byId = @{}
    foreach ($artifact in $artifacts) { $byId[[string]$artifact.artifactId] = $artifact }
    foreach ($artifactId in @(
        'windows-launch-mode-run-context',
        'windows-launch-before-snapshot',
        'windows-launch-after-snapshot',
        'windows-launch-mode-result',
        'windows-launch-mode-operator-report',
        'windows-launch-mode-final-handoff'
    )) {
        Check $byId.ContainsKey($artifactId) "artifact/$artifactId" 'artifact is not centrally registered'
        if ($byId.ContainsKey($artifactId)) {
            Check ($byId[$artifactId].tracked -eq $false) "artifact/$artifactId/untracked" 'artifact is tracked'
            Check ($byId[$artifactId].sensitivity -eq 'local-operational') "artifact/$artifactId/sensitivity" 'unexpected sensitivity'
        }
    }
}
catch { [void]$failures.Add("artifacts/semantic: $($_.Exception.Message)") }

try {
    $graph = $text['.ai/harness/app-composition.graph.json'] | ConvertFrom-Json
    $nodeIds = @($graph.nodes | ForEach-Object { [string]$_.id })
    $edgeIds = @($graph.edges | ForEach-Object { [string]$_.id })
    foreach ($nodeId in @(
        'skill.windows-launch-modes',
        'registry.windows-launch-modes',
        'workflow.windows-launch-mode-intake',
        'validator.windows-launch-modes',
        'artifact.windows-launch-mode-result',
        'artifact.windows-launch-mode-report'
    )) {
        Check ($nodeIds -contains $nodeId) "graph/node/$nodeId" 'node is missing'
    }
    foreach ($edgeId in @(
        'edge.windows-launch-trigger-skill',
        'edge.windows-launch-skill-workflow',
        'edge.observe-windows-launch-registry',
        'edge.observe-windows-launch-validator',
        'edge.windows-launch-result',
        'edge.windows-launch-report'
    )) {
        Check ($edgeIds -contains $edgeId) "graph/edge/$edgeId" 'edge is missing'
    }
}
catch { [void]$failures.Add("graph/semantic: $($_.Exception.Message)") }

$skill = $text['.ai/skills/windows-profile-launch-mode-validation/SKILL.md']
foreach ($token in @(
    'id: windows-profile-launch-mode-validation',
    'status: canonical',
    '## Trigger',
    '## Inputs',
    '## Procedure',
    '## Outputs',
    '## Deterministic validation',
    '## Forbidden scope',
    '## Stop and escalate',
    'exactly one new top-level WezTerm window',
    'unique tmux session',
    'duplicate-window-diagnosis.workflow.json',
    'No launcher product-code mutation in a harness-only sprint'
)) {
    Check ($skill.Contains($token)) "skill/$token" 'required skill rule is missing'
}

Check ($text['CODEBASE_MAP.md'].Contains('Windows Profile launch-mode harness')) 'catalog/codebase-map' 'codebase map entry is missing'
Check ($text['SKILLS.md'].Contains('windows-profile-launch-mode-validation')) 'catalog/skill' 'skill catalog entry is missing'
Check ($text['TRIGGERS.md'].Contains('profile.launch-mode-request')) 'catalog/trigger-request' 'launch-mode trigger is missing'
Check ($text['TRIGGERS.md'].Contains('profile.duplicate-window-observed')) 'catalog/trigger-duplicate' 'duplicate-window trigger is missing'

$deployablePaths = @(
    'tooling/profiles/windows/harness/launch-modes/codebase-map.json',
    'tooling/profiles/windows/harness/launch-modes/launch-mode.registry.json',
    'tooling/profiles/windows/harness/launch-modes/artifact-registry.json',
    '.ai/skills/windows-profile-launch-mode-validation/SKILL.md',
    'tooling/profiles/windows/Get-WindowsProfileLaunchModeStatus.ps1',
    'docs/harness/windows-profile-launch-mode-harness.md'
)
$deployableText = ($deployablePaths | ForEach-Object { $text[$_] }) -join "`n"
foreach ($forbidden in @('Start-Process','wezterm start','wezterm-gui.exe start','Invoke-WebRequest','Invoke-RestMethod','C:\Users\','/home/cheex')) {
    Check (-not $deployableText.Contains($forbidden)) "forbidden/$forbidden" 'product execution, network access, or machine-local data is embedded'
}

if ($failures.Count -eq 0) {
    & python (Join-Path $RootPath 'tests/test_windows_profile_launch_mode_harness.py')
    Check ($LASTEXITCODE -eq 0) 'python/contracts' 'dependency-free contracts failed'
}

Write-Host 'WINDOWS PROFILE LAUNCH MODE HARNESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) { exit 1 }
exit 0
