[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$FailureMessage = ''
    )

    if ($Passed) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $FailureMessage") }
}

function Get-TrackedText {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $RootPath $RelativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    Add-Result -Passed $exists -Name "file/$RelativePath" -FailureMessage 'required file is missing'
    if (-not $exists) { return $null }

    $null = & git -C $RootPath ls-files --error-unmatch -- $RelativePath 2>$null
    Add-Result -Passed ($LASTEXITCODE -eq 0) -Name "tracked/$RelativePath" -FailureMessage 'required file is not tracked'
    return Get-Content -LiteralPath $path -Raw
}

$paths = @(
    'AGENTS.md',
    'SKILLS.md',
    'TRIGGERS.md',
    '.ai/agent-contract.json',
    '.ai/skills/runtime-proof/SKILL.md',
    '.ai/skills/end-to-end-runtime-validation/SKILL.md'
)

$text = @{}
foreach ($path in $paths) {
    $text[$path] = Get-TrackedText -RelativePath $path
}

$skillPath = '.ai/skills/end-to-end-runtime-validation/SKILL.md'
$skill = $text[$skillPath]
if ($null -ne $skill) {
    foreach ($token in @(
        'id: end-to-end-runtime-validation',
        'version: 1.0.0',
        'status: canonical',
        '## Trigger',
        '## Inputs',
        '## Procedure',
        '## Outputs',
        '## Deterministic validation',
        '## Forbidden scope',
        '## Stop and escalate',
        'Freeze the operator path',
        'Prove the lower floors',
        'Enumerate every boundary',
        'Preflight boundaries independently',
        'Execute the exact operator command once',
        'Preserve stage output',
        'Read back effective state',
        'Observe the user experience',
        'Prove idempotence and rollback',
        'Classify and repair in the same context',
        'PowerShell -> pwsh child -> wsl.exe -> Ubuntu -> bash -lc -> tmux server -> sourced configuration -> WezTerm readback',
        'Never collapse a failed child process into only',
        'tmux verification failed with exit code 1',
        'Process creation, command acknowledgement, configuration-file presence, a zero parent exit code',
        'No manual operator workaround presented as proof',
        'Do not ask the operator to rerun an opaque failing script merely to recover evidence'
    )) {
        Add-Result -Passed $skill.Contains($token) -Name "skill/$token" -FailureMessage 'required end-to-end rule is missing'
    }

    $validationOrder = @(
        'parser, schema, lint, and static checks',
        'focused unit and contract checks',
        'plan or dry-run behavior',
        'independent boundary preflights',
        'exact operator invocation',
        'effective-state and user-experience readback',
        'idempotence and rollback checks when required',
        'broader safe repository validators',
        'clean-state, diff-hygiene, commit, push, and PR evidence'
    )
    $lastIndex = -1
    foreach ($token in $validationOrder) {
        $index = $skill.IndexOf($token, [System.StringComparison]::Ordinal)
        Add-Result -Passed ($index -gt $lastIndex) -Name "skill/validation-order/$token" -FailureMessage 'validation order is missing or out of order'
        if ($index -ge 0) { $lastIndex = $index }
    }
}

$agents = $text['AGENTS.md']
if ($null -ne $agents) {
    Add-Result -Passed $agents.Contains('.ai/skills/end-to-end-runtime-validation/SKILL.md') -Name 'agents/route' -FailureMessage 'AGENTS.md does not route end-to-end work to the project skill'
    Add-Result -Passed $agents.Contains('child stdout and stderr evidence') -Name 'agents/completion-evidence' -FailureMessage 'end-to-end completion evidence is missing'
    Add-Result -Passed (-not $agents.Contains('Freeze the operator path.')) -Name 'agents/procedure-extracted' -FailureMessage 'detailed skill procedure remains duplicated in AGENTS.md'
}

$skills = $text['SKILLS.md']
if ($null -ne $skills) {
    Add-Result -Passed $skills.Contains('[`end-to-end-runtime-validation`](.ai/skills/end-to-end-runtime-validation/SKILL.md)') -Name 'catalog/skill' -FailureMessage 'skill is missing from SKILLS.md'
    Add-Result -Passed $skills.Contains('A parent exception containing only an exit code is not a complete end-to-end failure report.') -Name 'catalog/failure-distinction' -FailureMessage 'runtime-proof distinction is incomplete'
}

$triggers = $text['TRIGGERS.md']
if ($null -ne $triggers) {
    foreach ($token in @(
        'runtime.end-to-end-request',
        'end-to-end-runtime-validation',
        'per-stage diagnostics',
        'A parent process error that reports only a child exit code is incomplete evidence.'
    )) {
        Add-Result -Passed $triggers.Contains($token) -Name "triggers/$token" -FailureMessage 'end-to-end trigger routing is missing'
    }
}

try {
    $contract = $text['.ai/agent-contract.json'] | ConvertFrom-Json
    Add-Result -Passed ($contract.contractVersion -eq '1.5.0') -Name 'contract/version' -FailureMessage 'contract version was not advanced'
    Add-Result -Passed ($contract.entrypoints.endToEndRuntimeValidation -eq $skillPath) -Name 'contract/entrypoint' -FailureMessage 'skill entrypoint is missing'
    Add-Result -Passed (@($contract.canonicalSkills) -contains 'end-to-end-runtime-validation') -Name 'contract/canonical-skill' -FailureMessage 'skill is not canonically registered'
    Add-Result -Passed ($contract.endToEndRuntimeValidation.validator -eq 'scripts/Test-EndToEndRuntimeValidationSkill.ps1') -Name 'contract/validator' -FailureMessage 'focused validator is not registered'
    Add-Result -Passed ($contract.endToEndRuntimeValidation.exactOperatorInvocationRequired -eq $true) -Name 'contract/operator-path' -FailureMessage 'exact operator invocation is not required'
    Add-Result -Passed ($contract.endToEndRuntimeValidation.boundaryStageDiagnosticsRequired -eq $true) -Name 'contract/stage-diagnostics' -FailureMessage 'per-boundary diagnostics are not required'
    Add-Result -Passed ($contract.endToEndRuntimeValidation.effectiveStateReadbackRequired -eq $true) -Name 'contract/readback' -FailureMessage 'effective-state readback is not required'
    Add-Result -Passed ($contract.endToEndRuntimeValidation.parentExitCodeAloneIsProof -eq $false) -Name 'contract/no-exit-only-proof' -FailureMessage 'parent exit code is incorrectly accepted as proof'
    Add-Result -Passed ($contract.endToEndRuntimeValidation.generatedEvidenceTracked -eq $false) -Name 'contract/untracked-evidence' -FailureMessage 'runtime evidence must remain untracked'
}
catch {
    [void]$failures.Add("contract/json`: $($_.Exception.Message)")
}

$runtimeProof = $text['.ai/skills/runtime-proof/SKILL.md']
if ($null -ne $runtimeProof) {
    Add-Result -Passed $runtimeProof.Contains('id: runtime-proof') -Name 'runtime-proof/preserved' -FailureMessage 'generic runtime-proof skill was replaced or corrupted'
}

Write-Host 'END-TO-END RUNTIME VALIDATION SKILL' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) { exit 1 }
exit 0
