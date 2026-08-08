[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Name, [string]$Message) {
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("${Name}: $Message") }
}

function Read-Tracked([string]$RelativePath) {
    $path = Join-Path $RootPath $RelativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    Check $exists "file/$RelativePath" 'required file is missing'
    if (-not $exists) { return $null }
    $null = & git -C $RootPath ls-files --error-unmatch -- $RelativePath 2>$null
    Check ($LASTEXITCODE -eq 0) "tracked/$RelativePath" 'required file is not tracked'
    return Get-Content -LiteralPath $path -Raw
}

$requiredFiles = @(
    'tooling/profiles/android/harness/termux/manifest.json',
    'tooling/profiles/android/harness/termux/codebase-map.json',
    'tooling/profiles/android/harness/termux/artifact-registry.json',
    'tooling/profiles/android/harness/termux/workflows/task-intake.workflow.json',
    'tooling/profiles/android/harness/termux/workflows/validate-terminal-boundary.workflow.json',
    'tooling/profiles/android/harness/termux/workflows/handle-input-boundary-failure.workflow.json',
    'tooling/profiles/android/harness/termux/fixtures/bracketed-paste-corruption.fixture.txt',
    'tooling/profiles/android/harness/termux/operator-report.template.md',
    'tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh',
    '.ai/skills/android-termux-repo-bootstrap/SKILL.md',
    'docs/harness/android-termux-operational-harness.md',
    'tests/test_android_termux_harness.py',
    '.github/workflows/android-termux-harness.yml'
)

$textByPath = @{}
foreach ($relativePath in $requiredFiles) { $textByPath[$relativePath] = Read-Tracked $relativePath }

foreach ($relativePath in @($requiredFiles | Where-Object { $_ -like '*.json' })) {
    try {
        $null = $textByPath[$relativePath] | ConvertFrom-Json
        Check $true "json/$relativePath" ''
    }
    catch { Check $false "json/$relativePath" $_.Exception.Message }
}

try {
    $manifest = $textByPath['tooling/profiles/android/harness/termux/manifest.json'] | ConvertFrom-Json
    Check ($manifest.schema -eq 'agentswitchboard.android-termux-harness.v1') 'manifest/schema' 'unexpected manifest schema'
    Check ($manifest.profile -eq 'android') 'manifest/profile' 'profile must be android'
    Check ($manifest.environment -eq 'termux') 'manifest/environment' 'environment must be termux'
    Check ($manifest.status -eq 'contract-only') 'manifest/proof-status' 'harness overclaims runtime readiness'
    Check ($manifest.canonicalProfileRegistry -eq '.ai/harness/device-profile-registry.json') 'manifest/profile-registry' 'canonical profile registry is not referenced'
    Check ([string]$manifest.proofCeiling -match 'does not claim an Android profile launcher exists') 'manifest/proof-ceiling' 'launcher overclaim is not blocked'
}
catch { [void]$failures.Add("manifest/semantic: $($_.Exception.Message)") }

$expectedWorkflows = @{
    'tooling/profiles/android/harness/termux/workflows/task-intake.workflow.json' = 'android-termux-task-intake'
    'tooling/profiles/android/harness/termux/workflows/validate-terminal-boundary.workflow.json' = 'android-termux-validate-terminal-boundary'
    'tooling/profiles/android/harness/termux/workflows/handle-input-boundary-failure.workflow.json' = 'android-termux-handle-input-boundary-failure'
}
foreach ($relativePath in $expectedWorkflows.Keys) {
    try {
        $workflow = $textByPath[$relativePath] | ConvertFrom-Json
        Check ($workflow.schema -eq 'agentswitchboard.android-termux-workflow.v1') "workflow/schema/$relativePath" 'unexpected workflow schema'
        Check ($workflow.workflowId -eq $expectedWorkflows[$relativePath]) "workflow/id/$relativePath" 'unexpected workflow id'
        Check (@($workflow.steps).Count -ge 5) "workflow/steps/$relativePath" 'workflow is not operationally complete'
        Check (-not [string]::IsNullOrWhiteSpace([string]$workflow.proofCeiling)) "workflow/proof/$relativePath" 'proof ceiling is missing'
    }
    catch { [void]$failures.Add("workflow/$relativePath`: $($_.Exception.Message)") }
}

try {
    $artifacts = $textByPath['tooling/profiles/android/harness/termux/artifact-registry.json'] | ConvertFrom-Json
    Check ($artifacts.tracked -eq $false) 'artifacts/untracked' 'generated evidence must remain untracked'
    $artifactIds = @($artifacts.artifacts | ForEach-Object { [string]$_.artifactId })
    foreach ($artifactId in @('termux-bootstrap-log','tmux-persistence-proof','terminal-input-boundary-report','github-auth-status','repo-clone-proof','android-termux-harness-validation','android-termux-operator-report')) {
        Check ($artifactIds -contains $artifactId) "artifacts/$artifactId" 'artifact is not registered'
    }
}
catch { [void]$failures.Add("artifacts/semantic: $($_.Exception.Message)") }

$fixture = $textByPath['tooling/profiles/android/harness/termux/fixtures/bracketed-paste-corruption.fixture.txt']
Check ($fixture.Contains('[200~gh auth login')) 'fixture/bracketed-paste' 'literal bracketed-paste signature is missing'
Check ($fixture.Contains('[200~gh: command not found')) 'fixture/command-not-found' 'command-not-found signature is missing'

$skill = $textByPath['.ai/skills/android-termux-repo-bootstrap/SKILL.md']
foreach ($token in @('id: android-termux-repo-bootstrap','status: experimental','## Trigger','## Inputs','## Procedure','## Outputs','## Deterministic validation','## Forbidden scope','## Stop and escalate')) {
    Check ($skill.Contains($token)) "skill/$token" 'skill contract token is missing'
}

$deployable = ($requiredFiles | ForEach-Object { $textByPath[$_] }) -join "`n"
foreach ($forbidden in @('BEGIN OPENSSH PRIVATE KEY','gh auth token','git clean -fdx')) {
    Check (-not $deployable.Contains($forbidden)) "forbidden/$forbidden" 'unsafe secret or destructive command literal is embedded in harness contracts'
}

Write-Host 'ANDROID TERMUX HARNESS COMPLETENESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
