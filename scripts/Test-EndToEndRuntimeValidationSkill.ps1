[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FailureMessage
    )

    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $FailureMessage") }
}

function Read-RequiredText {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $RootPath $RelativePath
    Add-Check `
        -Condition (Test-Path -LiteralPath $path -PathType Leaf) `
        -Name "required/$RelativePath" `
        -FailureMessage 'file is missing'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $path -Raw
}

$skillPath = '.ai/skills/end-to-end-runtime-validation/SKILL.md'
$skillText = Read-RequiredText $skillPath
$agentsText = Read-RequiredText 'AGENTS.md'
$skillsText = Read-RequiredText 'SKILLS.md'
$triggersText = Read-RequiredText 'TRIGGERS.md'
$contractText = Read-RequiredText '.ai/agent-contract.json'

if ($null -ne $skillText) {
    foreach ($token in @(
        'id: end-to-end-runtime-validation',
        'version: 1.1.0',
        'status: canonical',
        '## Trigger',
        '## Inputs',
        '## Procedure',
        '## Outputs',
        '## Deterministic validation',
        '## Forbidden scope',
        '## Stop and escalate',
        'exact operator command',
        'exact shell',
        'Enumerate every boundary',
        'Capture stdout, stderr, exit code',
        'Read back effective state',
        'Observe the user experience',
        'Prove idempotence and rollback',
        'repo-owned shim',
        'Model interactive input',
        'browser handoff',
        'optional agent',
        'Observed live failure outranks lower-floor success',
        'Process creation, command acknowledgement, configuration-file presence',
        'No runtime success claim from static inspection, CI alone',
        'No blind retry'
    )) {
        Add-Check `
            -Condition $skillText.Contains($token) `
            -Name "skill/$token" `
            -FailureMessage 'required end-to-end runtime contract token is missing'
    }
}

if ($null -ne $agentsText) {
    foreach ($token in @(
        '.ai/skills/end-to-end-runtime-validation/SKILL.md',
        'exact operator command',
        'child stdout and stderr evidence',
        'effective-state readback',
        'user-visible observation',
        'idempotence and rollback result'
    )) {
        Add-Check `
            -Condition $agentsText.Contains($token) `
            -Name "agents/$token" `
            -FailureMessage 'root agent contract does not route or report end-to-end runtime proof'
    }
}

if ($null -ne $skillsText) {
    foreach ($token in @(
        'end-to-end-runtime-validation',
        '.ai/skills/end-to-end-runtime-validation/SKILL.md',
        'A parent exception containing only an exit code is not a complete end-to-end failure report'
    )) {
        Add-Check `
            -Condition $skillsText.Contains($token) `
            -Name "catalog/$token" `
            -FailureMessage 'skills catalog registration is incomplete'
    }
}

if ($null -ne $triggersText) {
    foreach ($token in @(
        'runtime.end-to-end-request',
        'end-to-end-runtime-validation',
        'per-stage diagnostics',
        'effective-state and user-experience readback',
        'A parent process error that reports only a child exit code is incomplete evidence'
    )) {
        Add-Check `
            -Condition $triggersText.Contains($token) `
            -Name "trigger/$token" `
            -FailureMessage 'trigger routing or invariant is incomplete'
    }
}

if ($null -ne $contractText) {
    try {
        $contract = $contractText | ConvertFrom-Json
        Add-Check ($contract.schemaVersion -eq 1) 'contract/schema' 'expected schemaVersion 1'
        Add-Check ([version]$contract.contractVersion -ge [version]'1.5.0') 'contract/version' 'expected contractVersion 1.5.0 or newer'
        Add-Check ($contract.entrypoints.endToEndRuntimeValidation -eq $skillPath) 'contract/entrypoint' 'skill entrypoint is missing or incorrect'
        Add-Check (@($contract.canonicalSkills) -contains 'end-to-end-runtime-validation') 'contract/canonical-skill' 'canonical skill registration is missing'
        Add-Check (@($contract.proofLevels) -contains 'end-to-end-runtime') 'contract/proof-level' 'end-to-end runtime proof level is missing'
        Add-Check ($contract.endToEndRuntimeValidation.skill -eq $skillPath) 'contract/skill-path' 'end-to-end runtime policy skill path is incorrect'
        Add-Check ($contract.endToEndRuntimeValidation.validator -eq 'scripts/Test-EndToEndRuntimeValidationSkill.ps1') 'contract/validator' 'dedicated validator registration is incorrect'
        Add-Check ([bool]$contract.endToEndRuntimeValidation.exactOperatorInvocationRequired) 'contract/exact-operator-command' 'exact operator invocation is not required'
        Add-Check ([bool]$contract.endToEndRuntimeValidation.boundaryStageDiagnosticsRequired) 'contract/stage-diagnostics' 'per-stage diagnostics are not required'
        Add-Check ([bool]$contract.endToEndRuntimeValidation.effectiveStateReadbackRequired) 'contract/effective-state' 'effective-state readback is not required'
        Add-Check ([bool]$contract.endToEndRuntimeValidation.userExperienceObservationRequired) 'contract/user-experience' 'user-experience observation is not required'
        Add-Check ([bool]$contract.endToEndRuntimeValidation.idempotenceAndRollbackWhenApplicable) 'contract/idempotence-rollback' 'idempotence and rollback are not required when applicable'
        Add-Check (-not [bool]$contract.endToEndRuntimeValidation.parentExitCodeAloneIsProof) 'contract/no-parent-exit-only-proof' 'parent exit code alone may claim proof'
        Add-Check (-not [bool]$contract.endToEndRuntimeValidation.staticOrCiProofCanClaimEndToEnd) 'contract/no-static-ci-promotion' 'static or CI proof may claim end-to-end success'
        Add-Check (-not [bool]$contract.endToEndRuntimeValidation.generatedEvidenceTracked) 'contract/untracked-evidence' 'generated end-to-end evidence is marked tracked'
    }
    catch {
        [void]$failures.Add("contract/json`: $($_.Exception.Message)")
    }
}

Write-Host 'END-TO-END RUNTIME VALIDATION SKILL' -ForegroundColor Cyan
foreach ($pass in $passes) { Write-Host "[PASS] $pass" -ForegroundColor Green }
foreach ($failure in $failures) { Write-Host "[FAIL] $failure" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) { exit 1 }
exit 0
