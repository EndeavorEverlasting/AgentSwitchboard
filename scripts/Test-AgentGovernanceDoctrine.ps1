[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$FailureMessage = ''
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("${Name}: $FailureMessage")
    }
}

$relativePath = 'AGENTS.md'
$governancePath = Join-Path $RootPath $relativePath
$exists = Test-Path -LiteralPath $governancePath -PathType Leaf
Add-Result -Passed $exists -Name 'governance/file-exists' -FailureMessage 'AGENTS.md is missing'

$tracked = $false
if ($exists) {
    $null = & git -C $RootPath ls-files --error-unmatch -- $relativePath 2>$null
    $tracked = $LASTEXITCODE -eq 0
}
Add-Result -Passed $tracked -Name 'governance/file-tracked' -FailureMessage 'AGENTS.md is not tracked by Git'

if ($exists) {
    $text = Get-Content -LiteralPath $governancePath -Raw

    foreach ($heading in @(
        '# Agent Operating Contract',
        '## Agent operating principles',
        '## Instruction precedence',
        '## Mandatory sprint declaration',
        '## Launch order and dependency gates',
        '## Broad-stride execution and principle reuse',
        '## Environment capability and continuity',
        '## Agent-facing interface doctrine (AXI)',
        '## Multi-agent and local-model governance',
        '## Forbidden behaviors',
        '## Completion standard'
    )) {
        Add-Result -Passed $text.Contains($heading) -Name "governance/heading/$heading" -FailureMessage 'required governance section is missing'
    }

    foreach ($principle in @(
        'Evidence before action',
        'Floor before furniture',
        'Bounded sprints with declared scope',
        'One writer per branch',
        'Reuse before replacing',
        'No completion without proof'
    )) {
        Add-Result -Passed $text.Contains($principle) -Name "governance/principle/$principle" -FailureMessage 'required operating principle is missing'
    }

    $precedence = @(
        'Platform, security, legal, and repository-owner instructions.',
        'This governance contract.',
        'Task-specific prompts.',
        'Generic defaults.'
    )
    $previousIndex = -1
    foreach ($item in $precedence) {
        $index = $text.IndexOf($item, [StringComparison]::Ordinal)
        Add-Result -Passed ($index -ge 0) -Name "governance/precedence/present/$item" -FailureMessage 'precedence item is missing'
        Add-Result -Passed ($index -gt $previousIndex) -Name "governance/precedence/order/$item" -FailureMessage 'instruction precedence is out of order'
        if ($index -ge 0) { $previousIndex = $index }
    }

    foreach ($field in @(
        'repository and branch',
        'lane and mission',
        'owned scope and forbidden scope',
        'expected artifacts and validation commands',
        'proof ceiling'
    )) {
        Add-Result -Passed $text.Contains($field) -Name "governance/sprint-declaration/$field" -FailureMessage 'mandatory sprint declaration field is missing'
    }

    foreach ($rule in @(
        'One prompt panel goes into one new chat.',
        'Run them in this exact order.',
        'A dependency gate is hard',
        'Parallel-group panels remain contiguous',
        'disjoint branches or worktrees',
        'named convergence owner',
        'Downstream work is blocked',
        'Each panel is self-contained',
        'A launch order coordinates work; it does not grant authority'
    )) {
        Add-Result -Passed $text.Contains($rule) -Name "governance/launch-order/$rule" -FailureMessage 'required launch-order rule is missing'
    }

    foreach ($rule in @(
        'Broad strides are encouraged',
        'one coherent vertical slice',
        'Classify every requirement as',
        '`reuse`',
        '`extend`',
        '`repair`',
        '`retire`',
        '`create`',
        'Declare the boundary map',
        'one canonical owner',
        'Complete the owned vertical slice',
        'Principles stay canonical',
        'Skills describe reusable workflow guidance',
        'Capabilities expose reusable operations',
        'Triggers deterministically route conditions',
        'Application behavior remains in code',
        'verified, inferred, or unresolved',
        'Do not weaken a gate',
        'does not grant merge, release, deployment, authentication, or live-target authority'
    )) {
        Add-Result -Passed $text.Contains($rule) -Name "governance/broad-stride/$rule" -FailureMessage 'required broad-stride or principle-reuse rule is missing'
    }

    foreach ($rule in @(
        'Every cross-environment request must classify five layers independently',
        '**Frontend**',
        '**Transport**',
        '**Workspace host**',
        '**Orchestration runtime**',
        '**Agent runtime**',
        'One registered topology and one role ceiling must be selected',
        '`full-runtime-host`',
        '`workspace-host`',
        '`terminal-client`',
        '`local-shell-only`',
        '`transport-only`',
        '`unsupported`',
        'matching tmux session names on different hosts equal one workspace',
        'phone-local tmux equals cross-device continuity',
        'Termux equals generic Linux',
        'Auto-configuration is not a universal installer',
        'observe -> classify layers -> select topology -> report blockers -> bounded mutation -> effective-state readback -> focused validation -> authorized runtime certification -> proof report',
        'A lower-role topology must not be substituted',
        'terminal-client-implemented',
        'Native Android AgentSwitchboard orchestration is `unimplemented`',
        'native agent/provider runtime is `unproved`'
    )) {
        Add-Result -Passed $text.Contains($rule) -Name "governance/environment/$rule" -FailureMessage 'required environment-capability rule is missing'
    }

    foreach ($rule in @(
        'Token-efficient output',
        'Minimal default schemas',
        'Content truncation',
        'Pre-computed aggregates',
        'Definitive empty states',
        'Structured errors and exit codes',
        'Ambient context',
        'Content first',
        'Contextual disclosure',
        'Consistent help',
        'https://axi.md/'
    )) {
        Add-Result -Passed $text.Contains($rule) -Name "governance/axi/$rule" -FailureMessage 'required agent-interface rule is missing'
    }

    foreach ($rule in @(
        'Verify the upstream contract',
        'Treat extensions as executable code',
        'Prove privacy; do not infer it',
        'Declare orchestration roles',
        'Preserve independent evidence',
        'Make divergence visible',
        'Separate test authority from implementation',
        'Bound every loop',
        'One designated writer',
        'Log actual execution identity',
        'official source for the pinned version',
        'privacy claim requires evidence',
        'maximum attempts',
        'provider, model, endpoint class'
    )) {
        Add-Result -Passed $text.Contains($rule) -Name "governance/multi-agent/$rule" -FailureMessage 'required multi-agent or local-model rule is missing'
    }

    foreach ($behavior in @(
        'Acknowledgment without mutation',
        'Plans without execution',
        'Summaries without proof',
        'Completion claims without running checks',
        'Secret or credential exposure',
        'Re-inventing an established principle',
        'Trivial-only progress',
        'Installing or executing unverified third-party agent snippets',
        'Claiming privacy, model independence, successful fusion, continuous validation, cross-device continuity, remote compatibility, or full runtime readiness from configuration intent, repository presence, package presence, session-name equality, transport reachability, command acknowledgement, or hosted CI alone'
    )) {
        Add-Result -Passed $text.Contains($behavior) -Name "governance/forbidden/$behavior" -FailureMessage 'required forbidden behavior is missing'
    }

    foreach ($completion in @(
        'files changed are named',
        'validation was actually run',
        'commit SHA exists',
        'push or PR state is reported',
        'one exact next command is given'
    )) {
        Add-Result -Passed $text.Contains($completion) -Name "governance/completion/$completion" -FailureMessage 'minimum completion evidence is missing'
    }
}

Write-Host 'AGENT GOVERNANCE DOCTRINE' -ForegroundColor Cyan
foreach ($pass in $passes) {
    Write-Host "[PASS] $pass" -ForegroundColor Green
}
foreach ($failure in $failures) {
    Write-Host "[FAIL] $failure" -ForegroundColor Red
}
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) {
    exit 1
}
exit 0
