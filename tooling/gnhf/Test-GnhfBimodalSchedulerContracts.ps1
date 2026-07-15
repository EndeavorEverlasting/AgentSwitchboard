[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$FailureMessage = "contract failed"
    )

    if ($Passed) {
        [void]$passes.Add($Name)
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    else {
        [void]$failures.Add("$Name`: $FailureMessage")
        Write-Host "[FAIL] $Name - $FailureMessage" -ForegroundColor Red
    }
}

function Read-Text {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$failures.Add("required-file/$RelativePath`: file missing")
        return $null
    }
    return Get-Content -LiteralPath $path -Raw
}

$requiredFiles = @(
    "GnhfBimodal.Policy.ps1",
    "GnhfBimodal.Policy.psm1",
    "Invoke-GnhfBimodalScheduler.ps1",
    "Test-GnhfBimodalSchedulerContracts.ps1",
    "gnhf-bimodal.example.json",
    "schemas/gnhf-usage-snapshot.schema.json",
    "schemas/gnhf-routing-decision.schema.json",
    "schemas/gnhf-bimodal-run.schema.json",
    "fixtures/gnhf-usage-completion.json",
    "fixtures/gnhf-usage-efficiency.json"
)
foreach ($relativePath in $requiredFiles) {
    Add-Check -Passed (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf) -Name "required-file/$relativePath" -FailureMessage "file missing"
}

foreach ($relativePath in @(
    "GnhfBimodal.Policy.ps1",
    "GnhfBimodal.Policy.psm1",
    "Invoke-GnhfBimodalScheduler.ps1",
    "Start-GnhfSprint.ps1",
    "Test-GnhfBimodalSchedulerContracts.ps1"
)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $RootPath $relativePath),
        [ref]$tokens,
        [ref]$parseErrors
    )
    Add-Check -Passed ($parseErrors.Count -eq 0) -Name "powershell-parse/$relativePath" -FailureMessage (($parseErrors | ForEach-Object { $_.Message }) -join "; ")
}

foreach ($relativePath in @(
    "gnhf-bimodal.example.json",
    "schemas/gnhf-usage-snapshot.schema.json",
    "schemas/gnhf-routing-decision.schema.json",
    "schemas/gnhf-bimodal-run.schema.json",
    "fixtures/gnhf-usage-completion.json",
    "fixtures/gnhf-usage-efficiency.json"
)) {
    try {
        [void](Get-Content -LiteralPath (Join-Path $RootPath $relativePath) -Raw | ConvertFrom-Json -Depth 50)
        Add-Check -Passed $true -Name "json-parse/$relativePath"
    }
    catch {
        Add-Check -Passed $false -Name "json-parse/$relativePath" -FailureMessage $_.Exception.Message
    }
}

$policyModule = Join-Path $RootPath "GnhfBimodal.Policy.psm1"
Import-Module $policyModule -Force
$config = Get-Content -LiteralPath (Join-Path $RootPath "gnhf-bimodal.example.json") -Raw | ConvertFrom-Json -Depth 30
$completionSnapshot = Get-Content -LiteralPath (Join-Path $RootPath "fixtures/gnhf-usage-completion.json") -Raw | ConvertFrom-Json -Depth 30
$efficiencySnapshot = Get-Content -LiteralPath (Join-Path $RootPath "fixtures/gnhf-usage-efficiency.json") -Raw | ConvertFrom-Json -Depth 30
$profiles = @($config.profiles)
$policy = $config.policy

$completion = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $completionSnapshot -Policy $policy
Add-Check -Passed ($completion.selected.profileId -eq "opencode-primary") -Name "policy/completion-prefers-primary" -FailureMessage "expected opencode-primary"

$completionContinues = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $completionSnapshot -Policy $policy -PreviousProfileId "opencode-primary" -PreviousOutcome "progressed"
Add-Check -Passed ($completionContinues.selected.profileId -eq "opencode-primary" -and $completionContinues.reason -eq "continue-current-profile-until-exhausted") -Name "policy/completion-stays-until-exhausted" -FailureMessage "completion mode switched before exhaustion"

$exhaustedSnapshot = ($completionSnapshot | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30)
($exhaustedSnapshot.profiles | Where-Object profileId -eq "opencode-primary").tokensRemaining = 0
$completionSwitch = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $exhaustedSnapshot -Policy $policy -PreviousProfileId "opencode-primary" -PreviousOutcome "quota-exhausted"
Add-Check -Passed ($completionSwitch.selected.profileId -eq "copilot-secondary") -Name "policy/completion-switches-after-exhaustion" -FailureMessage "expected copilot-secondary"

$efficiency = Select-GnhfRoutingProfile -Mode "maximize-token-efficiency" -Profiles $profiles -Snapshot $efficiencySnapshot -Policy $policy
Add-Check -Passed ($efficiency.selected.profileId -eq "goose-efficient") -Name "policy/efficiency-prefers-efficient-profile" -FailureMessage "expected goose-efficient"
$opencodeEfficiencyState = $efficiency.states | Where-Object profileId -eq "opencode-primary"
Add-Check -Passed (-not $opencodeEfficiencyState.eligible -and $opencodeEfficiencyState.eligibilityReason -eq "reserve-floor-reached") -Name "policy/efficiency-preserves-reserve" -FailureMessage "near-reserve profile remained eligible"

$rotation = Select-GnhfRoutingProfile -Mode "maximize-token-efficiency" -Profiles $profiles -Snapshot $efficiencySnapshot -Policy $policy -PreviousProfileId "goose-efficient" -PreviousOutcome "progressed" -SegmentCounts @{ "goose-efficient" = 1 }
Add-Check -Passed ($rotation.selected.profileId -eq "copilot-secondary" -and $rotation.reason -eq "rotate-to-preserve-usage") -Name "policy/efficiency-rotates-models" -FailureMessage "efficiency mode did not rotate"

$efficiencyCap = Get-GnhfSegmentTokenCap -SelectedState $efficiency.selected -Mode "maximize-token-efficiency" -Policy $policy -DefaultSegmentMaxTokens 300000
Add-Check -Passed ($efficiencyCap -eq 75000) -Name "policy/efficiency-bounds-segment-share" -FailureMessage "expected 75000, got $efficiencyCap"
$completionCap = Get-GnhfSegmentTokenCap -SelectedState $completion.selected -Mode "maximize-sprint-completion" -Policy $policy -DefaultSegmentMaxTokens 300000
Add-Check -Passed ($completionCap -eq 300000) -Name "policy/completion-uses-full-bounded-segment" -FailureMessage "expected 300000, got $completionCap"

$declarationOnly = Get-GnhfSegmentOutcome -ExitCode 0 -LogText "Stop when: The objective is complete." -CommitDelta 1
Add-Check -Passed ($declarationOnly.status -eq "progressed" -and -not $declarationOnly.objectiveComplete) -Name "outcome/does-not-inflate-configured-stop-text" -FailureMessage "declared stop text was treated as observed completion"
$completed = Get-GnhfSegmentOutcome -ExitCode 0 -LogText "The stop condition was satisfied after validation." -CommitDelta 1
Add-Check -Passed ($completed.status -eq "objective-complete" -and $completed.objectiveComplete) -Name "outcome/observes-stop-condition" -FailureMessage "observed stop condition was not recognized"
$quota = Get-GnhfSegmentOutcome -ExitCode 1 -LogText "Permanent agent error: usage limit reached." -CommitDelta 0
Add-Check -Passed ($quota.status -eq "quota-exhausted" -and $quota.switchProfile) -Name "outcome/quota-switches-profile" -FailureMessage "quota exhaustion did not trigger switch"
$auth = Get-GnhfSegmentOutcome -ExitCode 1 -LogText "Authentication required; login required." -CommitDelta 0
Add-Check -Passed ($auth.status -eq "authentication-blocked" -and $auth.switchProfile) -Name "outcome/auth-switches-profile" -FailureMessage "authentication block did not trigger switch"
$timeout = Get-GnhfSegmentOutcome -ExitCode 124 -LogText "" -CommitDelta 0 -TimedOut
Add-Check -Passed ($timeout.status -eq "timed-out" -and $timeout.switchProfile) -Name "outcome/timeout-switches-profile" -FailureMessage "timeout did not trigger switch"

$manifest = $config
Add-Check -Passed ($manifest.mode -eq "maximize-sprint-completion") -Name "manifest/default-mode-completion" -FailureMessage "default mode must maximize sprint completion"
Add-Check -Passed ($manifest.policy.reservePercent -gt 0) -Name "manifest/efficiency-reserve" -FailureMessage "efficiency reserve missing"
Add-Check -Passed ($manifest.session.maxSegments -gt 0 -and $manifest.session.segmentMaxIterations -gt 0 -and $manifest.session.segmentMaxTokens -gt 0) -Name "manifest/bounded-segments" -FailureMessage "scheduler caps missing"

$scheduler = Read-Text "Invoke-GnhfBimodalScheduler.ps1"
if ($scheduler) {
    Add-Check -Passed ($scheduler.Contains('"maximize-sprint-completion", "maximize-token-efficiency"')) -Name "scheduler/bimodal-enum" -FailureMessage "both modes are not explicit"
    Add-Check -Passed ($scheduler.Contains('worktree", "add", "-b"')) -Name "scheduler/isolated-integration-worktree" -FailureMessage "scheduler does not create one isolated worktree"
    Add-Check -Passed ($scheduler.Contains('Get-UsageSnapshot -Path $resolvedUsagePath')) -Name "scheduler/reloads-usage-before-selection" -FailureMessage "usage snapshot is not refreshed"
    Add-Check -Passed ($scheduler.Contains('Start-BoundedSchedulerSegment')) -Name "scheduler/bounded-child-process" -FailureMessage "GNHF segment process is not bounded"
    Add-Check -Passed ($scheduler.Contains('router-handoff.md') -and $scheduler.Contains('stable-objective.md')) -Name "scheduler/log-informed-stable-prompt" -FailureMessage "stable prompt and handoff are not separated"
    Add-Check -Passed ($scheduler.Contains('routing-decision-') -and $scheduler.Contains('usageSnapshotHash')) -Name "scheduler/decision-evidence" -FailureMessage "routing decisions lack snapshot evidence"
    Add-Check -Passed (-not $scheduler.Contains('git merge') -and -not $scheduler.Contains('git push')) -Name "scheduler/no-auto-merge-push" -FailureMessage "scheduler contains automatic merge or push"
    Add-Check -Passed ($scheduler.Contains('The scheduler does not merge or push automatically.')) -Name "scheduler/review-boundary" -FailureMessage "human review boundary missing"
}

$sprintLauncher = Read-Text "Start-GnhfSprint.ps1"
if ($sprintLauncher) {
    Add-Check -Passed ($sprintLauncher.Contains('[switch]$CurrentBranch')) -Name "launcher/current-branch-segments" -FailureMessage "scheduler cannot reuse one branch"
    Add-Check -Passed ($sprintLauncher.Contains('switchboard/gnhf-*') -or $sprintLauncher.Contains('switchboard/gnhf-')) -Name "launcher/scheduler-owned-branch-guard" -FailureMessage "current branch ownership is not enforced"
    Add-Check -Passed ($sprintLauncher.Contains('AGENTSWITCHBOARD_MODEL_PROFILE') -and $sprintLauncher.Contains('AGENTSWITCHBOARD_MODEL')) -Name "launcher/model-profile-context" -FailureMessage "model profile context is not passed"
    Add-Check -Passed ($sprintLauncher.Contains('routingDecisionHash')) -Name "launcher/routing-decision-hash" -FailureMessage "routing decision evidence is not hashed"
    Add-Check -Passed ($sprintLauncher.Contains('Get-SafeAgentSpecLabel')) -Name "launcher/redacts-custom-acp" -FailureMessage "custom ACP commands can leak into summaries"
}

$installer = Read-Text "Install-AgentSwitchboardGnhf.ps1"
if ($installer) {
    Add-Check -Passed ($installer.Contains('Invoke-GnhfBimodalScheduler.ps1')) -Name "installer/copies-bimodal-scheduler" -FailureMessage "scheduler is not installed"
    Add-Check -Passed ($installer.Contains('Test-GnhfBimodalSchedulerContracts.ps1')) -Name "installer/copies-bimodal-validator" -FailureMessage "bimodal validator is not installed"
    Add-Check -Passed ($installer.Contains('gnhf-bimodal.example.json')) -Name "installer/copies-bimodal-manifest" -FailureMessage "bimodal manifest is not installed"
}

$readme = Read-Text "README.md"
if ($readme) {
    Add-Check -Passed ($readme.Contains('maximize-sprint-completion')) -Name "docs/completion-mode" -FailureMessage "completion mode undocumented"
    Add-Check -Passed ($readme.Contains('maximize-token-efficiency')) -Name "docs/efficiency-mode" -FailureMessage "efficiency mode undocumented"
    Add-Check -Passed ($readme.Contains('usage snapshot')) -Name "docs/usage-contract" -FailureMessage "usage snapshot handoff undocumented"
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Result: $($passes.Count) passed / $($failures.Count) failed" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
Write-Host "Result: $($passes.Count) passed / 0 failed" -ForegroundColor Green
exit 0
