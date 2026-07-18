[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$FailureMessage = ""
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("$Name`: $FailureMessage")
    }
}

function Get-RequiredText {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$failures.Add("required-file/$RelativePath`: file is missing")
        return $null
    }

    return Get-Content -LiteralPath $path -Raw
}

function Test-ActionCommitmentPrompt {
    param([Parameter(Mandatory)][string]$Text)

    $claimsAction = $Text -match '(?i)\b(install|set\s*up|build|execute|repair|configure|upgrade|deploy|merge|release)\b'
    if (-not $claimsAction) {
        return $true
    }

    $forbidsMutation = $Text -match '(?i)\b(do not|don''t|without)\s+(change|modify|write|commit|push|mutate)\b'
    $acknowledgmentOnly = $Text -match '(?i)\b(acknowledg(e|ment)|summary only|plan only|advice only|handoff only)\b'
    $requiresMutation = $Text -match '(?i)\b(modify|create|write|update|commit|push|open or update|open a pull request|mutate)\b'
    $requiresProof = $Text -match '(?i)\b(validate|validation|tests?|commit sha|push confirmation|pull request|\bPR\b)\b'

    return ($requiresMutation -and $requiresProof -and -not $forbidsMutation -and -not $acknowledgmentOnly)
}

function Test-GnhfTestBounds {
    param(
        [Parameter(Mandatory)][int]$WallClockSeconds,
        [Parameter(Mandatory)][int]$IterationSeconds,
        [Parameter(Mandatory)][int]$MaxIterations
    )

    return (
        $WallClockSeconds -gt 0 -and
        $WallClockSeconds -le 30 -and
        $IterationSeconds -gt 0 -and
        $IterationSeconds -le 30 -and
        $MaxIterations -gt 0
    )
}

function Test-DeepSeekRateGate {
    param(
        [Parameter(Mandatory)][string]$RateClass,
        [Parameter(Mandatory)][double]$Multiplier,
        [Parameter(Mandatory)][bool]$ScheduleVerified
    )

    if (-not $ScheduleVerified) {
        return $false
    }

    return ($RateClass -in @('standard', 'discounted') -and $Multiplier -le 1.0)
}

$policyText = Get-RequiredText -RelativePath ".ai/harness/harness-doctrine.policy.json"
$templatePolicyText = Get-RequiredText -RelativePath "templates/repository-agent-contract/.ai/harness/harness-doctrine.policy.json"
$doctrineText = Get-RequiredText -RelativePath "docs/governance/harness-doctrine.md"
$agentsText = Get-RequiredText -RelativePath "AGENTS.md"
$templateAgentsText = Get-RequiredText -RelativePath "templates/repository-agent-contract/AGENTS.md"
$gnhfSkillText = Get-RequiredText -RelativePath ".ai/skills/gnhf-prompt-compilation/SKILL.md"

if ($null -ne $policyText) {
    try {
        $policy = $policyText | ConvertFrom-Json
        Add-Result -Passed ($policy.schemaVersion -eq 1) -Name "policy/schema-version" -FailureMessage "expected schemaVersion 1"
        Add-Result -Passed ($policy.policyId -eq "agentswitchboard.harness-doctrine.v1") -Name "policy/id" -FailureMessage "unexpected policy ID"

        $expectedFields = @(
            "repository",
            "branchOrWorktree",
            "prOrSprint",
            "lane",
            "ownedScope",
            "forbiddenScope",
            "expectedArtifacts",
            "validationOrder"
        )
        foreach ($field in $expectedFields) {
            Add-Result -Passed (@($policy.requiredSprintFields) -contains $field) -Name "policy/sprint-field/$field" -FailureMessage "required sprint field missing"
        }

        $expectedLoop = @(
            "request",
            "evidence-review",
            "bounded-decision",
            "repository-or-git-or-github-mutation",
            "artifacts",
            "validation",
            "report",
            "next-decision"
        )
        Add-Result `
            -Passed ((@($policy.executableLoop) -join "|") -eq ($expectedLoop -join "|")) `
            -Name "policy/executable-loop" `
            -FailureMessage "executable loop changed or is incomplete"

        Add-Result -Passed ([bool]$policy.actionCommitment.requiresTrackedMutation) -Name "policy/action/requires-mutation" -FailureMessage "action prompts may avoid mutation"
        Add-Result -Passed ([bool]$policy.actionCommitment.requiresValidationEvidence) -Name "policy/action/requires-validation" -FailureMessage "action prompts may avoid validation"
        Add-Result -Passed ([bool]$policy.actionCommitment.requiresCommitOrGitHubEvidence) -Name "policy/action/requires-git-proof" -FailureMessage "action prompts may avoid commit or GitHub proof"
        Add-Result -Passed ([bool]$policy.actionCommitment.forbidAcknowledgmentOnly) -Name "policy/action/rejects-ack-only" -FailureMessage "acknowledgment-only setup is not rejected"
        Add-Result -Passed ([bool]$policy.actionCommitment.forbidPlanSubstitution) -Name "policy/action/rejects-plan-substitution" -FailureMessage "plan substitution is allowed"

        Add-Result -Passed ($policy.gnhfTestOnly.maxWallClockSeconds -eq 30) -Name "policy/gnhf-test/wall-clock" -FailureMessage "test-only wall-clock cap must be 30 seconds"
        Add-Result -Passed ($policy.gnhfTestOnly.maxIterationSeconds -eq 30) -Name "policy/gnhf-test/iteration" -FailureMessage "test-only iteration cap must be 30 seconds"
        Add-Result -Passed ($policy.gnhfTestOnly.defaultMaxIterations -eq 1) -Name "policy/gnhf-test/default-iterations" -FailureMessage "test-only default must be one iteration"
        Add-Result -Passed ([bool]$policy.gnhfTestOnly.requireProcessTreeTermination) -Name "policy/gnhf-test/process-tree" -FailureMessage "test timeout must terminate the process tree"

        $allowedRateClasses = @($policy.deepseekUsageGate.allowedRateClasses)
        $blockedRateClasses = @($policy.deepseekUsageGate.blockedRateClasses)
        Add-Result -Passed ($allowedRateClasses -contains "standard") -Name "policy/deepseek/allows-standard" -FailureMessage "standard rate class missing"
        Add-Result -Passed ($allowedRateClasses -contains "discounted") -Name "policy/deepseek/allows-discounted" -FailureMessage "discounted rate class missing"
        Add-Result -Passed ($blockedRateClasses -contains "double-usage") -Name "policy/deepseek/blocks-double" -FailureMessage "double-usage class is not blocked"
        Add-Result -Passed ($blockedRateClasses -contains "unknown") -Name "policy/deepseek/blocks-unknown" -FailureMessage "unknown schedule state is not blocked"
        Add-Result -Passed ([double]$policy.deepseekUsageGate.maximumAllowedMultiplier -eq 1.0) -Name "policy/deepseek/multiplier-ceiling" -FailureMessage "DeepSeek multiplier ceiling must be 1.0"
        Add-Result -Passed ($policy.deepseekUsageGate.defaultAction -eq "deny") -Name "policy/deepseek/fail-closed" -FailureMessage "unknown schedule must deny"
        Add-Result -Passed ([bool]$policy.deepseekUsageGate.requireVerifiedSchedule) -Name "policy/deepseek/requires-schedule" -FailureMessage "verified schedule is not required"
        Add-Result -Passed (-not [bool]$policy.deepseekUsageGate.officialPricingReference.activeTimeOfDayWindowPublished) -Name "policy/deepseek/current-official-window" -FailureMessage "policy incorrectly claims an active official time window"
        Add-Result -Passed (-not [bool]$policy.deepseekUsageGate.officialPricingReference.historicalOffPeakWindowUtc.active) -Name "policy/deepseek/historical-window-disabled" -FailureMessage "expired historical window is active"
    }
    catch {
        [void]$failures.Add("policy/json`: $($_.Exception.Message)")
    }
}

if ($null -ne $templatePolicyText) {
    try {
        $templatePolicy = $templatePolicyText | ConvertFrom-Json
        Add-Result -Passed ($templatePolicy.policyId -eq "agentswitchboard.harness-doctrine.v1") -Name "template-policy/id" -FailureMessage "template policy does not inherit the canonical doctrine"
        Add-Result -Passed ($templatePolicy.localRulesMayWeaken -eq $false) -Name "template-policy/no-weakening" -FailureMessage "template policy may be weakened"
        Add-Result -Passed ($templatePolicy.gnhfTestOnly.maxWallClockSeconds -eq 30) -Name "template-policy/test-wall-clock" -FailureMessage "template test cap is not 30 seconds"
        Add-Result -Passed ($templatePolicy.deepseekUsageGate.defaultAction -eq "deny") -Name "template-policy/deepseek-fail-closed" -FailureMessage "template DeepSeek gate is not fail-closed"
    }
    catch {
        [void]$failures.Add("template-policy/json`: $($_.Exception.Message)")
    }
}

if ($null -ne $doctrineText) {
    foreach ($token in @(
        "request -> evidence review -> bounded decision -> repo or Git or GitHub mutation -> artifacts -> validation -> report -> next decision",
        "Action-commitment rule",
        "Test-only GNHF timing rule",
        "DeepSeek usage-window rule",
        "30 seconds",
        "double-usage",
        "standard",
        "discounted"
    )) {
        Add-Result -Passed ($doctrineText.Contains($token)) -Name "doctrine/content/$token" -FailureMessage "required doctrine content missing"
    }
}

$entrypointTokens = @(
    "docs/governance/harness-doctrine.md",
    ".ai/harness/harness-doctrine.policy.json",
    "PR or sprint",
    "validation order"
)
foreach ($document in @(
    @{ Name = "AGENTS.md"; Text = $agentsText },
    @{ Name = "templates/repository-agent-contract/AGENTS.md"; Text = $templateAgentsText }
)) {
    if ($null -eq $document.Text) {
        continue
    }
    foreach ($token in $entrypointTokens) {
        Add-Result -Passed ($document.Text.Contains($token)) -Name "entrypoint/$($document.Name)/$token" -FailureMessage "doctrine reference missing"
    }
}

if ($null -ne $gnhfSkillText) {
    foreach ($token in @(
        "Test-only timing contract",
        "30 seconds wall clock",
        "30 seconds per iteration",
        "DeepSeek rate-window contract",
        "double-usage",
        "standard",
        "discounted",
        "unknown or stale schedule state blocks DeepSeek"
    )) {
        Add-Result -Passed ($gnhfSkillText.Contains($token)) -Name "gnhf-skill/$token" -FailureMessage "GNHF doctrine token missing"
    }
}

$invalidActionPrompt = "Install the harness. Return an acknowledgment and a plan only. Do not change or commit files."
$validActionPrompt = "Install the harness by modifying tracked files, validating the doctrine, committing the change, pushing the branch, and opening a pull request with the commit SHA."
Add-Result -Passed (-not (Test-ActionCommitmentPrompt -Text $invalidActionPrompt)) -Name "fixture/reject-acknowledgment-only" -FailureMessage "acknowledgment-only installation prompt was accepted"
Add-Result -Passed (Test-ActionCommitmentPrompt -Text $validActionPrompt) -Name "fixture/accept-committed-install" -FailureMessage "commit-required installation prompt was rejected"

Add-Result -Passed (Test-GnhfTestBounds -WallClockSeconds 30 -IterationSeconds 30 -MaxIterations 1) -Name "fixture/test-bounds-30" -FailureMessage "30-second test profile was rejected"
Add-Result -Passed (-not (Test-GnhfTestBounds -WallClockSeconds 31 -IterationSeconds 30 -MaxIterations 1)) -Name "fixture/reject-wall-clock-31" -FailureMessage "31-second test wall clock was accepted"
Add-Result -Passed (-not (Test-GnhfTestBounds -WallClockSeconds 30 -IterationSeconds 31 -MaxIterations 1)) -Name "fixture/reject-iteration-31" -FailureMessage "31-second iteration was accepted"

Add-Result -Passed (Test-DeepSeekRateGate -RateClass "standard" -Multiplier 1.0 -ScheduleVerified $true) -Name "fixture/deepseek-standard" -FailureMessage "verified standard DeepSeek window was rejected"
Add-Result -Passed (Test-DeepSeekRateGate -RateClass "discounted" -Multiplier 0.5 -ScheduleVerified $true) -Name "fixture/deepseek-discounted" -FailureMessage "verified discounted DeepSeek window was rejected"
Add-Result -Passed (-not (Test-DeepSeekRateGate -RateClass "double-usage" -Multiplier 2.0 -ScheduleVerified $true)) -Name "fixture/deepseek-double-blocked" -FailureMessage "double-usage DeepSeek window was accepted"
Add-Result -Passed (-not (Test-DeepSeekRateGate -RateClass "standard" -Multiplier 1.0 -ScheduleVerified $false)) -Name "fixture/deepseek-unknown-blocked" -FailureMessage "unverified DeepSeek schedule was accepted"

Write-Host "HARNESS DOCTRINE CONTRACT" -ForegroundColor Cyan
foreach ($pass in $passes) {
    Write-Host "[PASS] $pass" -ForegroundColor Green
}
foreach ($failure in $failures) {
    Write-Host "[FAIL] $failure" -ForegroundColor Red
}
Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
