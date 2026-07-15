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
    "GnhfModelActivation.ps1",
    "Start-GnhfSprint.ps1",
    "GnhfBimodal.Policy.ps1",
    "GnhfBimodal.Policy.psm1",
    "Invoke-GnhfBimodalScheduler.ps1",
    "Install-GnhfBimodalScheduler.ps1",
    "Test-GnhfBimodalSchedulerContracts.ps1",
    "gnhf-bimodal.example.json",
    "schemas/gnhf-usage-snapshot.schema.json",
    "schemas/gnhf-model-activation.schema.json",
    "schemas/gnhf-routing-decision.schema.json",
    "schemas/gnhf-bimodal-run.schema.json",
    "fixtures/gnhf-usage-completion.json",
    "fixtures/gnhf-usage-efficiency.json",
    "fixtures/gnhf-model-activation-acknowledged.json",
    "BIMODAL_SCHEDULER.md"
)
foreach ($relativePath in $requiredFiles) {
    Add-Check -Passed (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf) -Name "required-file/$relativePath" -FailureMessage "file missing"
}

foreach ($relativePath in @(
    "GnhfModelActivation.ps1",
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
    "schemas/gnhf-model-activation.schema.json",
    "schemas/gnhf-routing-decision.schema.json",
    "schemas/gnhf-bimodal-run.schema.json",
    "fixtures/gnhf-usage-completion.json",
    "fixtures/gnhf-usage-efficiency.json",
    "fixtures/gnhf-model-activation-acknowledged.json"
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
. (Join-Path $RootPath "GnhfModelActivation.ps1")

$config = Get-Content -LiteralPath (Join-Path $RootPath "gnhf-bimodal.example.json") -Raw | ConvertFrom-Json -Depth 30
$completionSnapshot = Get-Content -LiteralPath (Join-Path $RootPath "fixtures/gnhf-usage-completion.json") -Raw | ConvertFrom-Json -Depth 30
$efficiencySnapshot = Get-Content -LiteralPath (Join-Path $RootPath "fixtures/gnhf-usage-efficiency.json") -Raw | ConvertFrom-Json -Depth 30
$capturedNow = [DateTimeOffset]::UtcNow
$completionSnapshot.capturedAt = $capturedNow.ToString("o")
$efficiencySnapshot.capturedAt = $capturedNow.ToString("o")
$profiles = @($config.profiles)
$policy = $config.policy

$completionOrder = @($profiles | Sort-Object completionPriority | ForEach-Object id)
$expectedCompletionOrder = @("deepseek-primary", "opencode-secondary", "agy-tertiary", "copilot-fallback", "goose-efficient")
Add-Check -Passed (($completionOrder -join "|") -eq ($expectedCompletionOrder -join "|")) -Name "manifest/deepseek-opencode-agy-fallback-order" -FailureMessage "actual order: $($completionOrder -join ', ')"
$agyDefault = $profiles | Where-Object id -eq "agy-tertiary" | Select-Object -First 1
Add-Check -Passed (-not [bool]$agyDefault.enabled -and [string]::IsNullOrWhiteSpace([string]$agyDefault.agentSpec)) -Name "manifest/agy-requires-detected-adapter"

$freshness = Get-GnhfSnapshotFreshness -Snapshot $completionSnapshot -Policy $policy -Now $capturedNow
Add-Check -Passed ($freshness.acceptable -and $freshness.reason -eq "usage-snapshot-fresh") -Name "policy/accepts-fresh-usage-snapshot"

$staleSnapshot = $completionSnapshot | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
$staleSnapshot.capturedAt = $capturedNow.AddMinutes(-([double]$policy.maxUsageSnapshotAgeMinutes + 1)).ToString("o")
$staleSelection = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $staleSnapshot -Policy $policy -Now $capturedNow
Add-Check -Passed ($null -eq $staleSelection.selected -and $staleSelection.reason -eq "usage-snapshot-stale") -Name "policy/rejects-stale-usage-snapshot"

$futureSnapshot = $completionSnapshot | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
$futureSnapshot.capturedAt = $capturedNow.AddMinutes(([double]$policy.maxUsageSnapshotFutureSkewMinutes + 1)).ToString("o")
$futureSelection = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $futureSnapshot -Policy $policy -Now $capturedNow
Add-Check -Passed ($null -eq $futureSelection.selected -and $futureSelection.reason -eq "usage-snapshot-from-future") -Name "policy/rejects-future-usage-snapshot"

$completion = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $completionSnapshot -Policy $policy -Now $capturedNow
Add-Check -Passed ($completion.selected.profileId -eq "deepseek-primary") -Name "policy/completion-prefers-deepseek"

$completionContinues = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $completionSnapshot -Policy $policy -PreviousProfileId "deepseek-primary" -PreviousOutcome "progressed" -Now $capturedNow
Add-Check -Passed ($completionContinues.selected.profileId -eq "deepseek-primary" -and $completionContinues.reason -eq "continue-current-profile-until-exhausted") -Name "policy/completion-stays-on-deepseek-until-exhausted"

$exhaustedSnapshot = $completionSnapshot | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
($exhaustedSnapshot.profiles | Where-Object profileId -eq "deepseek-primary").tokensRemaining = 0
$completionSwitch = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $exhaustedSnapshot -Policy $policy -PreviousProfileId "deepseek-primary" -PreviousOutcome "quota-exhausted" -Now $capturedNow
Add-Check -Passed ($completionSwitch.selected.profileId -eq "opencode-secondary") -Name "policy/completion-falls-back-to-opencode"

$failedFallback = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles $profiles -Snapshot $completionSnapshot -Policy $policy -PreviousProfileId "deepseek-primary" -PreviousOutcome "failed" -Now $capturedNow
Add-Check -Passed ($failedFallback.selected.profileId -eq "opencode-secondary" -and $failedFallback.reason -eq "switch-after-exhaustion-or-block") -Name "policy/completion-switches-to-opencode-after-deepseek-failure"

$agyConfig = $config | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
($agyConfig.profiles | Where-Object id -eq "agy-tertiary").enabled = $true
$agySnapshot = $completionSnapshot | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
($agySnapshot.profiles | Where-Object profileId -eq "deepseek-primary").tokensRemaining = 0
($agySnapshot.profiles | Where-Object profileId -eq "opencode-secondary").tokensRemaining = 0
$agySwitch = Select-GnhfRoutingProfile -Mode "maximize-sprint-completion" -Profiles @($agyConfig.profiles) -Snapshot $agySnapshot -Policy $agyConfig.policy -PreviousProfileId "opencode-secondary" -PreviousOutcome "quota-exhausted" -Now $capturedNow
Add-Check -Passed ($agySwitch.selected.profileId -eq "agy-tertiary") -Name "policy/completion-uses-agy-third-when-enabled"

$efficiency = Select-GnhfRoutingProfile -Mode "maximize-token-efficiency" -Profiles $profiles -Snapshot $efficiencySnapshot -Policy $policy -Now $capturedNow
Add-Check -Passed ($efficiency.selected.profileId -eq "goose-efficient") -Name "policy/efficiency-prefers-efficient-profile"
$primaryEfficiencyState = $efficiency.states | Where-Object profileId -eq "deepseek-primary"
Add-Check -Passed (-not $primaryEfficiencyState.eligible -and $primaryEfficiencyState.eligibilityReason -eq "reserve-floor-reached") -Name "policy/efficiency-preserves-deepseek-reserve"

$rotation = Select-GnhfRoutingProfile -Mode "maximize-token-efficiency" -Profiles $profiles -Snapshot $efficiencySnapshot -Policy $policy -PreviousProfileId "goose-efficient" -PreviousOutcome "progressed" -SegmentCounts @{ "goose-efficient" = 1 } -Now $capturedNow
Add-Check -Passed ($rotation.selected.profileId -eq "copilot-fallback" -and $rotation.reason -eq "rotate-to-preserve-usage") -Name "policy/efficiency-rotates-profiles"

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
$agyNotReady = Get-GnhfSegmentOutcome -ExitCode 1 -LogText "Agent 'agy' is not ready. Evidence: readiness probe failed." -CommitDelta 0
Add-Check -Passed ($agyNotReady.status -eq "permanent-error" -and $agyNotReady.switchProfile) -Name "outcome/agy-not-ready-switches-and-blocks"
$timeout = Get-GnhfSegmentOutcome -ExitCode 124 -LogText "" -CommitDelta 0 -TimedOut
Add-Check -Passed ($timeout.status -eq "timed-out" -and $timeout.switchProfile) -Name "outcome/timeout-switches-profile"

$ackPath = Join-Path ([IO.Path]::GetTempPath()) ("agent-switchboard-model-ack-{0}.json" -f [guid]::NewGuid().ToString("N"))
try {
    Copy-Item -LiteralPath (Join-Path $RootPath "fixtures\gnhf-model-activation-acknowledged.json") -Destination $ackPath
    $ack = Get-GnhfModelActivationResult `
        -AcknowledgementPath $ackPath `
        -ExpectedProfileId "deepseek-primary" `
        -ExpectedAgent "opencode" `
        -ExpectedModel "deepseek/configured-primary-model" `
        -ExpectedRoutingDecisionHash "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    Add-Check -Passed ($ack.state -eq "acknowledged" -and $ack.acknowledgedModel -eq "deepseek/configured-primary-model") -Name "activation/accepts-exact-model-acknowledgement"

    $mismatch = Get-GnhfModelActivationResult `
        -AcknowledgementPath $ackPath `
        -ExpectedProfileId "deepseek-primary" `
        -ExpectedAgent "opencode" `
        -ExpectedModel "deepseek/other-model" `
        -ExpectedRoutingDecisionHash "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    Add-Check -Passed ($mismatch.state -eq "invalid-acknowledgement" -and $mismatch.validationError -match "requestedModel mismatch") -Name "activation/rejects-model-mismatch"
}
finally {
    Remove-Item -LiteralPath $ackPath -Force -ErrorAction SilentlyContinue
}

$missingAck = Get-GnhfModelActivationResult `
    -AcknowledgementPath (Join-Path ([IO.Path]::GetTempPath()) "missing-agent-switchboard-ack.json") `
    -ExpectedProfileId "deepseek-primary" `
    -ExpectedAgent "opencode" `
    -ExpectedModel "deepseek/configured-primary-model" `
    -ExpectedRoutingDecisionHash $null
Add-Check -Passed ($missingAck.state -eq "requested-only") -Name "activation/request-is-not-activation-proof"

Add-Check -Passed ($config.mode -eq "maximize-sprint-completion") -Name "manifest/default-mode-completion"
Add-Check -Passed ($config.policy.reservePercent -gt 0) -Name "manifest/efficiency-reserve"
Add-Check -Passed ($config.policy.maxUsageSnapshotAgeMinutes -gt 0 -and $config.policy.maxUsageSnapshotFutureSkewMinutes -ge 0) -Name "manifest/usage-freshness-bounds"
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
    Add-Check -Passed ($launcher.Contains('AGENTSWITCHBOARD_MODEL_ACK_PATH') -and $launcher.Contains('AGENTSWITCHBOARD_ROUTING_DECISION_HASH')) -Name "launcher/model-ack-context"
    Add-Check -Passed ($launcher.Contains('Get-GnhfModelActivationResult') -and $launcher.Contains('modelActivation')) -Name "launcher/distinguishes-request-from-acknowledgement"
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
    Add-Check -Passed ($installer.Contains('GnhfModelActivation.ps1') -and $installer.Contains('gnhf-model-activation.schema.json')) -Name "installer/copies-model-activation-contract"
    Add-Check -Passed ($installer.Contains('BIMODAL_SCHEDULER.md')) -Name "installer/copies-operator-guide"
}

$guide = Read-Text "BIMODAL_SCHEDULER.md"
if ($guide) {
    Add-Check -Passed ($guide.Contains('maximize-sprint-completion')) -Name "docs/completion-mode"
    Add-Check -Passed ($guide.Contains('maximize-token-efficiency')) -Name "docs/efficiency-mode"
    Add-Check -Passed ($guide.Contains('DeepSeek') -and $guide.Contains('OpenCode') -and $guide.Contains('Anti-Gravity')) -Name "docs/completion-hierarchy"
    Add-Check -Passed ($guide.Contains('usage snapshot') -and $guide.Contains('maxUsageSnapshotAgeMinutes')) -Name "docs/usage-freshness-contract"
    Add-Check -Passed ($guide.Contains('AGENTSWITCHBOARD_MODEL_ACK_PATH') -and $guide.Contains('requested-only')) -Name "docs/model-ack-contract"
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
