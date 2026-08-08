[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Name, [string]$Message) {
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $Message") }
}

function Finish {
    Write-Host 'ANDROID TERMUX HARNESS COMPLETENESS' -ForegroundColor Cyan
    $passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
    $failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
    Write-Host "`nResult: $($passes.Count) passed / $($failures.Count) failed"
    if ($failures.Count -gt 0) { exit 1 }
    exit 0
}

$required = @(
    'tooling/profiles/android/harness/termux/manifest.json',
    'tooling/profiles/android/harness/termux/codebase-map.json',
    'tooling/profiles/android/harness/termux/artifact-registry.json',
    'tooling/profiles/android/harness/termux/operator-report.template.md',
    'tooling/profiles/android/harness/termux/workflows/task-intake.workflow.json',
    'tooling/profiles/android/harness/termux/workflows/validate-terminal-boundary.workflow.json',
    'tooling/profiles/android/harness/termux/workflows/handle-input-boundary-failure.workflow.json',
    'tooling/profiles/android/harness/termux/workflows/capture-terminal-output.workflow.json',
    'tooling/profiles/android/harness/termux/fixtures/bracketed-paste-corruption.fixture.txt',
    'tooling/profiles/android/harness/termux/fixtures/multi-pane-selection.fixture.txt',
    '.ai/skills/android-termux-repo-bootstrap/SKILL.md',
    '.ai/skills/android-termux-terminal-recovery/SKILL.md',
    'tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh',
    'tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPrePush.sh',
    'docs/harness/android-termux-operational-harness.md',
    'tests/test_android_termux_harness.py',
    '.github/workflows/android-termux-harness.yml',
    'Start-AgentSwitchboard-Android.sh',
    'tooling/profiles/android/AgentSwitchboard-Android.sh',
    '.ai/harness/device-profile-registry.json'
)

$missing = [System.Collections.Generic.List[string]]::new()
foreach ($relative in $required) {
    if (Test-Path -LiteralPath (Join-Path $RootPath $relative) -PathType Leaf) {
        [void]$passes.Add("file/$relative")
    } else {
        [void]$missing.Add($relative)
        [void]$failures.Add("file/$relative`: required file missing")
    }
}
if ($missing.Count -gt 0) { Finish }

$jsonPaths = @(
    'tooling/profiles/android/harness/termux/manifest.json',
    'tooling/profiles/android/harness/termux/codebase-map.json',
    'tooling/profiles/android/harness/termux/artifact-registry.json',
    'tooling/profiles/android/harness/termux/workflows/task-intake.workflow.json',
    'tooling/profiles/android/harness/termux/workflows/validate-terminal-boundary.workflow.json',
    'tooling/profiles/android/harness/termux/workflows/handle-input-boundary-failure.workflow.json',
    'tooling/profiles/android/harness/termux/workflows/capture-terminal-output.workflow.json',
    '.ai/harness/device-profile-registry.json'
)
$json = @{}
foreach ($relative in $jsonPaths) {
    try {
        $json[$relative] = Get-Content -LiteralPath (Join-Path $RootPath $relative) -Raw | ConvertFrom-Json
        [void]$passes.Add("json/$relative")
    } catch {
        [void]$failures.Add("json/$relative`: $($_.Exception.Message)")
    }
}
if ($failures.Count -gt 0) { Finish }

$manifest = $json['tooling/profiles/android/harness/termux/manifest.json']
Check ($manifest.status -eq 'operational-harness-runtime-separate') 'manifest/status' 'unexpected harness status'
Check ($manifest.runtimeEntrypoint -eq 'Start-AgentSwitchboard-Android.sh') 'manifest/runtime-entrypoint' 'runtime entrypoint not indexed'
Check (@($manifest.components.workflows) -contains 'tooling/profiles/android/harness/termux/workflows/capture-terminal-output.workflow.json') 'manifest/capture-workflow' 'capture workflow missing'
Check (@($manifest.components.fixtures) -contains 'tooling/profiles/android/harness/termux/fixtures/multi-pane-selection.fixture.txt') 'manifest/multipane-fixture' 'multi-pane fixture missing'
Check (@($manifest.components.skills) -contains '.ai/skills/android-termux-terminal-recovery/SKILL.md') 'manifest/recovery-skill' 'terminal recovery skill missing'
Check (@($manifest.components.hooks) -contains 'tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPrePush.sh') 'manifest/prepush' 'pre-push hook missing'

$mapText = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/termux/codebase-map.json') -Raw
foreach ($token in @('tmux list-panes', 'tmux capture-pane -p -S -200', 'long-press selection', 'Touch scrolling', 'authentication/device-code')) {
    Check ($mapText.Contains($token)) "map/$token" 'required Android terminal boundary rule missing'
}

$artifactText = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/termux/artifact-registry.json') -Raw
foreach ($token in @('tmux-pane-inventory', 'tmux-pane-capture', 'terminal-interaction-report', 'defaultHistoryLines', 'private SSH keys', 'credential file contents')) {
    Check ($artifactText.Contains($token)) "artifact/$token" 'required artifact or secret boundary missing'
}

$workflowText = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/termux/workflows/capture-terminal-output.workflow.json') -Raw
foreach ($token in @('inventory-panes', 'classify-sensitivity', 'select-exact-pane', 'capture-bounded-history', 'OAuth/device codes', 'QR/live-document/file')) {
    Check ($workflowText.Contains($token)) "workflow/$token" 'required pane recovery step missing'
}

$skillText = Get-Content -LiteralPath (Join-Path $RootPath '.ai/skills/android-termux-terminal-recovery/SKILL.md') -Raw
foreach ($token in @('tmux list-panes', 'tmux capture-pane', 'Ctrl+B', 'Never solve a secrecy problem')) {
    Check ($skillText.Contains($token)) "skill/$token" 'terminal recovery skill incomplete'
}

$registry = $json['.ai/harness/device-profile-registry.json']
$android = @($registry.profiles | Where-Object profileId -eq 'android')[0]
Check ($android.status -eq 'implemented-runtime-unproved') 'runtime/status' 'must reflect current runtime registration without promoting live proof'
Check ($android.canonicalSourcePath -eq 'Start-AgentSwitchboard-Android.sh') 'runtime/source' 'canonical runtime entrypoint differs'

$trackedOutput = & git -C $RootPath ls-files
if ($LASTEXITCODE -ne 0) {
    [void]$failures.Add('git/ls-files: failed')
} else {
    $tracked = @($trackedOutput | ForEach-Object { [string]$_ })
    foreach ($relative in $required) {
        Check ($tracked -contains $relative) "tracked/$relative" 'required harness/runtime-indexed file is not tracked'
    }
}

Finish
