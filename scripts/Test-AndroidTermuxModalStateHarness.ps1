[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$required = @(
    'tooling/profiles/android/harness/termux/Inspect-TerminalState.sh',
    'tooling/profiles/android/harness/termux/workflows/recover-modal-terminal-state.workflow.json',
    'tooling/profiles/android/harness/termux/fixtures/nano-modal-editor.fixture.txt',
    'tooling/profiles/android/harness/termux/manifest.json',
    'tooling/profiles/android/harness/termux/codebase-map.json',
    'tooling/profiles/android/harness/termux/artifact-registry.json',
    'tooling/profiles/android/harness/termux/operator-report.template.md',
    '.ai/skills/android-termux-terminal-recovery/SKILL.md',
    'docs/harness/android-termux-operational-harness.md',
    'tests/test_android_termux_modal_state_harness.py',
    'scripts/Test-AndroidTermuxModalStateHarness.ps1'
)

foreach ($relative in $required) {
    $path = Join-Path $RootPath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing modal-state harness component: $relative" }
    & git -C $RootPath ls-files --error-unmatch -- $relative *> $null
    if ($LASTEXITCODE -ne 0) { throw "Modal-state harness component is not tracked: $relative" }
}

$manifest = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/termux/manifest.json') -Raw | ConvertFrom-Json
$workflow = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/termux/workflows/recover-modal-terminal-state.workflow.json') -Raw | ConvertFrom-Json
$artifacts = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/termux/artifact-registry.json') -Raw | ConvertFrom-Json

if ($manifest.components.terminalStateInspector -ne 'tooling/profiles/android/harness/termux/Inspect-TerminalState.sh') { throw 'terminalStateInspector is not registered' }
if (@($manifest.components.workflows) -notcontains 'tooling/profiles/android/harness/termux/workflows/recover-modal-terminal-state.workflow.json') { throw 'modal-state workflow is not registered' }
if (@($manifest.components.fixtures) -notcontains 'tooling/profiles/android/harness/termux/fixtures/nano-modal-editor.fixture.txt') { throw 'nano fixture is not registered' }
if ($workflow.workflowId -ne 'android-termux-recover-modal-terminal-state') { throw 'unexpected modal-state workflow id' }

$workflowText = $workflow | ConvertTo-Json -Depth 20
foreach ($token in @('expected next screen', 'pane_current_command=nano', 'Ctrl+X', 'N to discard', 'Y then Enter', 'shell-bootstrap-text', 'PHONE_SHELL_READY', 'agentswitchboard-android sprint --prompt-file')) {
    if (-not $workflowText.Contains($token)) { throw "modal-state workflow missing token: $token" }
}

$artifactIds = @($artifacts.artifacts | ForEach-Object { [string]$_.artifactId })
if ($artifactIds -notcontains 'terminal-state-report') { throw 'terminal-state-report artifact is not registered' }

$inspector = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/termux/Inspect-TerminalState.sh') -Raw
foreach ($token in @('CLASSIFICATION=modal-editor:nano', 'HUNG_CLAIM=no', 'Ctrl+X', 'PROMPT_FILE_RULE')) {
    if (-not $inspector.Contains($token)) { throw "terminal-state inspector missing token: $token" }
}

$fixture = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/termux/fixtures/nano-modal-editor.fixture.txt') -Raw
foreach ($token in @('CLASSIFICATION=modal-editor:nano', 'HUNG_CLAIM=no', '^X Exit', 'N=discard', 'Y then Enter=save', 'PROMPT_FILE_RULE', 'REQUIRED_RECOVERY')) {
    if (-not $fixture.Contains($token)) { throw "nano fixture missing token: $token" }
}

$skill = Get-Content -LiteralPath (Join-Path $RootPath '.ai/skills/android-termux-terminal-recovery/SKILL.md') -Raw
$guide = Get-Content -LiteralPath (Join-Path $RootPath 'docs/harness/android-termux-operational-harness.md') -Raw
$report = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/termux/operator-report.template.md') -Raw
foreach ($token in @('version: 1.1.0', 'Inspect-TerminalState.sh', 'modal-editor:nano', 'PHONE_SHELL_READY')) {
    if (-not $skill.Contains($token)) { throw "terminal recovery skill missing token: $token" }
}
foreach ($token in @('Modal terminal state is not a hang by default', 'Sprint prompt boundary', 'Ctrl+X', 'PHONE_SHELL_READY')) {
    if (-not $guide.Contains($token)) { throw "Android operator guide missing token: $token" }
}
foreach ($token in @('Foreground command', 'Terminal state', 'Hung claim', 'Exit contract', 'Prompt file classification')) {
    if (-not $report.Contains($token)) { throw "operator report missing token: $token" }
}

if (Get-Command bash -ErrorAction SilentlyContinue) {
    & bash -n (Join-Path $RootPath 'tooling/profiles/android/harness/termux/Inspect-TerminalState.sh')
    if ($LASTEXITCODE -ne 0) { throw 'Inspect-TerminalState.sh failed bash -n' }
}

Write-Host '[PASS] Android Termux modal-state harness completeness' -ForegroundColor Green
