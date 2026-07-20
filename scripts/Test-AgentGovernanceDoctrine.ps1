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
        'Installing or executing unverified third-party agent snippets',
        'Claiming privacy, model independence, successful fusion, or continuous validation from configuration intent alone'
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