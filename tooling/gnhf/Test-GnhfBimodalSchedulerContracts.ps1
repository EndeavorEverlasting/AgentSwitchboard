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
    "GnhfFleet.Paths.ps1",
    "Start-GnhfSprint.ps1",
    "GnhfBimodal.Policy.ps1",
    "GnhfBimodal.Policy.psm1",
    "Invoke-GnhfBimodalScheduler.ps1",
    "Install-GnhfBimodalScheduler.ps1",
    "Test-GnhfBimodalSchedulerContracts.ps1",
    "gnhf-bimodal.example.json",
    "schemas/gnhf-usage-snapshot.schema.json",
    "schemas/gnhf-routing-decision.schema.json",
    "schemas/gnhf-bimodal-run.schema.json",
    "fixtures/gnhf-usage-completion.json",
    "fixtures/gnhf-usage-efficiency.json",
    "BIMODAL_SCHEDULER.md"
)
foreach ($relativePath in $requiredFiles) {
    Add-Check -Passed (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf) -Name "required-file/$relativePath" -FailureMessage "file missing"
}

foreach ($relativePath in @(
    "GnhfBimodal.Policy.ps1",
    "GnhfBimodal.Policy.psm1",
    "Invoke-GnhfBimodalScheduler.ps1",
    "Install-GnhfBimodalScheduler.ps1",
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
    Add-Check -Passed ($parseErrors.Count -eq 0) -Name "powershell-parse/$relativePath" -FailureMessage (($parseErrors | ForEach-Object Message) -join "; ")
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

Import-Module (Join-Path $RootPath "GnhfBimodal.Policy.psm1") -Force
$config = Get-Content -LiteralPath (Join-Path $RootPath "gnhf-bimodal.example.json") -Raw | ConvertFrom-Json -Depth 30
$completionSnapshot = Get-Content -LiteralPath (Join-Path $RootPath "fixtures/gnhf-usage-completion.json") -Raw | ConvertFrom-Json -Depth 30
$efficiencySnapshot = Get-Content -LiteralPath (Join-Path $RootPath "fixtures/gnhf-usage-efficiency.json") -Raw | ConvertFrom-Json -Depth 30
$profiles = @($config.profiles)
$policy = $config.policy

$completion = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $completionSnapshot -Policy $policy
Add-Check -Passed ($completion.selected.profileId -eq "opencode-primary") -Name "policy/completion-prefers-primary"

$completionContinues = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $completionSnapshot -Policy $policy -PreviousProfileId "opencode-primary" -PreviousOutcome "progressed"
Add-Check -Passed ($completionContinues.selected.profileId -eq "opencode-primary" -and $completionContinues.reason -eq "continue-current-profile-until-exhausted") -Name "policy/completion-stays-until-exhausted"

$exhaustedSnapshot = $completionSnapshot | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
($exhaustedSnapshot.profiles | Where-Object profileId -eq "opencode-primary").tokensRemaining = 0
$completionSwitch = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $exhaustedSnapshot -Policy $policy -PreviousProfileId "opencode-primary" -PreviousOutcome "quota-exhausted"
Add-Check -Passed ($completionSwitch.selected.profileId -eq "copilot-secondary") -Name "policy/completion-switches-after-exhaustion"

$failedFallback = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $completionSnapshot -Policy $policy -PreviousProfileId "opencode-primary" -PreviousOutcome "failed"
Add-Check -Passed ($failedFallback.selected.profileId -eq "copilot-secondary" -and $failedFallback.reason -eq "switch-after-exhaustion-or-block") -Name "policy/completion-switches-after-generic-failure"

$efficiency = Select-GnhfRoutingProfile -Mode "maximize-token-efficiency" -Profiles $profiles -Snapshot $efficiencySnapshot -Policy $policy
Add-Check -Passed ($efficiency.selected.profileId -eq "goose-efficient") -Name "policy/efficiency-prefers-efficient-profile"
$primaryEfficiencyState = $efficiency.states | Where-Object profileId -eq "opencode-primary"
Add-Check -Passed (-not $primaryEfficiencyState.eligible -and $primaryEfficiencyState.eligibilityReason -eq "reserve-floor-reached") -Name "policy/efficiency-preserves-reserve"

$rotation = Select-GnhfRoutingProfile -Mode "maximize-token-efficiency" -Profiles $profiles -Snapshot $efficiencySnapshot -Policy $policy -PreviousProfileId "goose-efficient" -PreviousOutcome "progressed" -SegmentCounts @{ "goose-efficient" = 1 }
Add-Check -Passed ($rotation.selected.profileId -eq "copilot-secondary" -and $rotation.reason -eq "rotate-to-preserve-usage") -Name "policy/efficiency-rotates-profiles"

$efficiencyCap = Get-GnhfSegmentTokenCap -SelectedState $efficiency.selected -Mode "maximize-token-efficiency" -Policy $policy -DefaultSegmentMaxTokens 300000
Add-Check -Passed ($efficiencyCap -eq 75000) -Name "policy/efficiency-bounds-segment-share" -FailureMessage "expected 75000, got $efficiencyCap"
$completionCap = Get-GnhfSegmentTokenCap -SelectedState $completion.selected -Mode "maximize-sprint-completion" -Policy $policy -DefaultSegmentMaxTokens 300000
Add-Check -Passed ($completionCap -eq 300000) -Name "policy/completion-uses-full-bounded-segment"

$declarationOnly = Get-GnhfSegmentOutcome -ExitCode 0 -LogText "Stop when: The objective is complete." -CommitDelta 1
Add-Check -Passed ($declarationOnly.status -eq "progressed" -and -not $declarationOnly.objectiveComplete) -Name "outcome/no-stop-text-inflation"
$completed = Get-GnhfSegmentOutcome -ExitCode 0 -LogText "The stop condition was satisfied after validation." -CommitDelta 1
Add-Check -Passed ($completed.status -eq "objective-complete" -and $completed.objectiveComplete) -Name "outcome/observes-stop-condition"
$negativeStop = Get-GnhfSegmentOutcome -ExitCode 0 -LogText "The stop condition was not satisfied after validation." -CommitDelta 1
Add-Check -Passed ($negativeStop.status -eq "progressed" -and -not $negativeStop.objectiveComplete) -Name "outcome/rejects-negated-stop-condition"
$negativeCondition = Get-GnhfSegmentOutcome -ExitCode 0 -LogText "The condition was never satisfied." -CommitDelta 0
Add-Check -Passed ($negativeCondition.status -eq "no-progress" -and -not $negativeCondition.objectiveComplete) -Name "outcome/rejects-never-satisfied-condition"
$budgetDeclaration = Get-GnhfSegmentOutcome -ExitCode 0 -LogText "Token cap: 500000" -CommitDelta 1
Add-Check -Passed ($budgetDeclaration.status -eq "progressed" -and -not $budgetDeclaration.switchProfile) -Name "outcome/token-budget-is-not-exhaustion"
$quota = Get-GnhfSegmentOutcome -ExitCode 1 -LogText "Permanent agent error: usage limit reached." -CommitDelta 0
Add-Check -Passed ($quota.status -eq "quota-exhausted" -and $quota.switchProfile) -Name "outcome/quota-switches-profile"
$auth = Get-GnhfSegmentOutcome -ExitCode 1 -LogText "Authentication required; login required." -CommitDelta 0
Add-Check -Passed ($auth.status -eq "authentication-blocked" -and $auth.switchProfile) -Name "outcome/auth-switches-profile"
$timeout = Get-GnhfSegmentOutcome -ExitCode 124 -LogText "" -CommitDelta 0 -TimedOut
Add-Check -Passed ($timeout.status -eq "timed-out" -and $timeout.switchProfile) -Name "outcome/timeout-switches-profile"

Add-Check -Passed ($config.mode -eq "maximize-sprint-completion") -Name "manifest/default-mode-completion"
Add-Check -Passed ($config.policy.reservePercent -gt 0) -Name "manifest/efficiency-reserve"
Add-Check -Passed ($config.session.maxSegments -gt 0 -and $config.session.segmentMaxIterations -gt 0 -and $config.session.segmentMaxTokens -gt 0 -and $config.session.segmentWallMinutes -gt 0) -Name "manifest/bounded-segments"

$scheduler = Read-Text "Invoke-GnhfBimodalScheduler.ps1"
if ($scheduler) {
    Add-Check -Passed ($scheduler.Contains('"maximize-sprint-completion", "maximize-token-efficiency"')) -Name "scheduler/bimodal-enum"
    Add-Check -Passed ($scheduler.Contains('worktree", "add", "-b"')) -Name "scheduler/isolated-integration-worktree"
    Add-Check -Passed ($scheduler.Contains('Get-UsageSnapshot -Path $resolvedUsagePath')) -Name "scheduler/reloads-usage"
    Add-Check -Passed ($scheduler.Contains('Start-BoundedSchedulerSegment')) -Name "scheduler/bounded-child"
    Add-Check -Passed ($scheduler.Contains('router-handoff.md') -and $scheduler.Contains('stable-objective.md')) -Name "scheduler/log-informed-handoff"
    Add-Check -Passed ($scheduler.Contains('routing-decision-') -and $scheduler.Contains('usageSnapshotHash')) -Name "scheduler/decision-evidence"
    Add-Check -Passed (-not $scheduler.Contains('git merge') -and -not $scheduler.Contains('git push')) -Name "scheduler/no-auto-merge-push"
}

$launcher = Read-Text "Start-GnhfSprint.ps1"
if ($launcher) {
    Add-Check -Passed ($launcher.Contains('[switch]$CurrentBranch')) -Name "launcher/current-branch-segments"
    Add-Check -Passed ($launcher.Contains('switchboard/gnhf-')) -Name "launcher/scheduler-branch-guard"
    Add-Check -Passed ($launcher.Contains('AGENTSWITCHBOARD_MODEL_PROFILE') -and $launcher.Contains('AGENTSWITCHBOARD_MODEL')) -Name "launcher/model-context"
    Add-Check -Passed ($launcher.Contains('routingDecisionHash')) -Name "launcher/decision-hash"
    Add-Check -Passed ($launcher.Contains('Get-SafeAgentSpecLabel')) -Name "launcher/redacts-custom-acp"
    Add-Check -Passed (-not $launcher.Contains('Write-Host "Token cap:') -and $launcher.Contains('Write-Host "Budget:')) -Name "launcher/token-budget-not-usage-log"
}

$installer = Read-Text "Install-GnhfBimodalScheduler.ps1"
if ($installer) {
    Add-Check -Passed ($installer.Contains('$planMode = -not $Apply')) -Name "installer/plan-default"
    Add-Check -Passed ($installer.Contains('Preserving existing customized bimodal manifest')) -Name "installer/preserves-manifest"
    Add-Check -Passed ($installer.Contains('Start-GnhfBimodal.cmd')) -Name "installer/clickable-launcher"
    Add-Check -Passed ($installer.Contains('automaticPush = $false') -and $installer.Contains('automaticMerge = $false')) -Name "installer/no-auto-push-merge"
    Add-Check -Passed ($installer.Contains('BIMODAL_SCHEDULER.md')) -Name "installer/copies-operator-guide"
}

$guide = Read-Text "BIMODAL_SCHEDULER.md"
if ($guide) {
    Add-Check -Passed ($guide.Contains('maximize-sprint-completion')) -Name "docs/completion-mode"
    Add-Check -Passed ($guide.Contains('maximize-token-efficiency')) -Name "docs/efficiency-mode"
    Add-Check -Passed ($guide.Contains('usage snapshot')) -Name "docs/usage-contract"
    Add-Check -Passed ($guide.Contains('AGENTSWITCHBOARD_MODEL_PROFILE')) -Name "docs/wrapper-contract"
    Add-Check -Passed ($guide.Contains('does not merge or push automatically') -or $guide.Contains('No automatic push, merge')) -Name "docs/review-boundary"
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Result: $($passes.Count) passed / $($failures.Count) failed" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
Write-Host "Result: $($passes.Count) passed / 0 failed" -ForegroundColor Green
exit 0
