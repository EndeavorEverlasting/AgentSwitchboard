[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [ValidateSet("maximize-sprint-completion", "maximize-token-efficiency")][string]$Mode,
    [string]$UsageSnapshotPath,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pathHelpersPath = Join-Path $PSScriptRoot "GnhfFleet.Paths.ps1"
$policyPath = Join-Path $PSScriptRoot "GnhfBimodal.Policy.ps1"
foreach ($requiredPath in @($pathHelpersPath, $policyPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required scheduler dependency not found: $requiredPath"
    }
}
. $pathHelpersPath
. $policyPath

function Invoke-RouterGit {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $lines = @(& git -C $Repository @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') failed in '$Repository':`n$($lines -join [Environment]::NewLine)"
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = $lines
        Text = ($lines -join [Environment]::NewLine)
    }
}

function Get-RouterGitScalar {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $result = Invoke-RouterGit -Repository $Repository -Arguments $Arguments
    $value = @($result.Output | Where-Object { $null -ne $_ } | Select-Object -First 1)
    if ($value.Count -eq 0) {
        return ""
    }
    return ([string]$value[0]).Trim()
}

function Get-RequiredProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Description
    )

    $property = $Object.PSObject.Properties[$Name]
    if (-not $property -or $null -eq $property.Value -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        throw "$Description is missing required property '$Name'."
    }
    $property.Value
}

function Get-UsageSnapshot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$ConsumedByProfile,
        [Parameter(Mandatory)][hashtable]$BlockedProfiles
    )

    $resolved = Resolve-GnhfFleetFile -Path $Path -Description "GNHF usage snapshot"
    $snapshot = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json -Depth 30
    if ([string]$snapshot.schemaVersion -ne "agentswitchboard-gnhf-usage/v1") {
        throw "Unsupported usage snapshot schemaVersion: $($snapshot.schemaVersion)"
    }

    foreach ($record in @($snapshot.profiles)) {
        $profileId = [string]$record.profileId
        if ($BlockedProfiles.ContainsKey($profileId)) {
            $record.ready = $false
            $record.blockedReason = [string]$BlockedProfiles[$profileId]
        }
        if ($ConsumedByProfile.ContainsKey($profileId) -and $record.PSObject.Properties["tokensRemaining"] -and $null -ne $record.tokensRemaining) {
            $record.tokensRemaining = [Math]::Max(0, [long]$record.tokensRemaining - [long]$ConsumedByProfile[$profileId])
        }
    }

    [pscustomobject]@{
        Path = $resolved
        Hash = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
        Data = $snapshot
    }
}

function ConvertTo-SafeSlug {
    param([Parameter(Mandatory)][string]$Value)

    $slug = ($Value.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-")
    if ($slug.Length -gt 48) {
        $slug = $slug.Substring(0, 48).Trim("-")
    }
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "bimodal-sprint"
    }
    $slug
}

function Write-RoutingDecision {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][int]$Segment,
        [Parameter(Mandatory)][string]$EffectiveMode,
        [Parameter(Mandatory)]$Selection,
        [Parameter(Mandatory)][long]$TokenCap,
        [Parameter(Mandatory)][string]$SnapshotHash
    )

    $selected = if ($Selection.selected) {
        [ordered]@{
            profileId = $Selection.selected.profileId
            agent = $Selection.selected.agent
            agentSpec = $Selection.selected.agentSpec
            model = $Selection.selected.model
        }
    }
    else {
        $null
    }

    $decision = [ordered]@{
        schemaVersion = "agentswitchboard-gnhf-routing-decision/v1"
        decidedAt = (Get-Date).ToString("o")
        runId = $RunId
        segment = $Segment
        mode = $EffectiveMode
        reason = [string]$Selection.reason
        selectedProfile = $selected
        segmentBudget = if ($Selection.selected) { $TokenCap } else { $null }
        usageSnapshotHash = $SnapshotHash
        candidates = @(
            foreach ($candidate in @($Selection.states)) {
                [ordered]@{
                    profileId = $candidate.profileId
                    eligible = [bool]$candidate.eligible
                    eligibilityReason = $candidate.eligibilityReason
                    tokensRemaining = $candidate.tokensRemaining
                    reserveTokens = $candidate.reserveTokens
                    usableTokens = $candidate.usableTokens
                }
            }
        )
    }
    $decision | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
    [pscustomobject]$decision
}

function Get-NewGnhfLogFiles {
    param(
        [Parameter(Mandatory)][string]$WorktreePath,
        [Parameter(Mandatory)][datetime]$Since
    )

    $runRoot = Join-Path $WorktreePath ".gnhf\runs"
    if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) {
        return @()
    }

    @(
        Get-ChildItem -LiteralPath $runRoot -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $Since.ToUniversalTime() -and $_.Name -in @("gnhf.log", "notes.md") } |
            Sort-Object LastWriteTimeUtc
    )
}

function Get-EstimatedTokensFromText {
    param([AllowEmptyString()][string]$Text)

    $matches = [regex]::Matches($Text, '(?im)(?:tokens?|token total|total tokens)[^0-9]{0,24}([0-9][0-9,]*)')
    if ($matches.Count -eq 0) {
        return $null
    }

    $values = @(
        foreach ($match in $matches) {
            $raw = $match.Groups[1].Value.Replace(",", "")
            $parsed = 0L
            if ([long]::TryParse($raw, [ref]$parsed)) {
                $parsed
            }
        }
    )
    if ($values.Count -eq 0) {
        return $null
    }
    [long]($values | Measure-Object -Maximum).Maximum
}

function Start-BoundedSchedulerSegment {
    param(
        [Parameter(Mandatory)][string]$WorkerScript,
        [Parameter(Mandatory)][string]$WorktreePath,
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)][string]$PromptPath,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$MaxIterations,
        [Parameter(Mandatory)][long]$MaxTokens,
        [Parameter(Mandatory)][string]$StopWhen,
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][int]$TimeoutMinutes,
        [Parameter(Mandatory)][string]$DecisionPath
    )

    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwsh
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $arguments = @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $WorkerScript,
        "-RepoPath", $WorktreePath,
        "-Agent", [string]$Profile.agent,
        "-AgentSpecOverride", [string]$Profile.agentSpec,
        "-PromptPath", $PromptPath,
        "-Name", $Name,
        "-MaxIterations", [string]$MaxIterations,
        "-MaxTokens", [string]$MaxTokens,
        "-StopWhen", $StopWhen,
        "-InstallRoot", $InstallRoot,
        "-CurrentBranch",
        "-ModelProfileId", [string]$Profile.profileId,
        "-RoutingDecisionPath", $DecisionPath
    )
    if ($null -ne $Profile.model -and -not [string]::IsNullOrWhiteSpace([string]$Profile.model)) {
        $arguments += @("-ModelId", [string]$Profile.model)
    }
    foreach ($argument in $arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutMinutes * 60 * 1000)
    if ($timedOut) {
        try {
            $process.Kill($true)
            $process.WaitForExit()
        }
        catch {}
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    [pscustomobject]@{
        ExitCode = if ($timedOut) { 124 } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = $stdout
        Stderr = $stderr
        Text = (($stdout, $stderr) -join [Environment]::NewLine)
    }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "The bimodal scheduler requires PowerShell 7."
}

$ConfigPath = Resolve-GnhfFleetFile -Path $ConfigPath -Description "bimodal scheduler config"
$configDirectory = Split-Path -Parent $ConfigPath
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 40
if ([int]$config.schemaVersion -ne 1) {
    throw "Unsupported scheduler schemaVersion: $($config.schemaVersion)"
}

$effectiveMode = if ($Mode) {
    $Mode
}
else {
    [string](Get-RequiredProperty -Object $config -Name "mode" -Description "scheduler config")
}
if ($effectiveMode -notin @("maximize-sprint-completion", "maximize-token-efficiency")) {
    throw "Unsupported scheduler mode: $effectiveMode"
}

$repoPath = Resolve-GnhfFleetDirectory -Path ([string](Get-RequiredProperty -Object $config -Name "repoPath" -Description "scheduler config")) -BaseDirectory $configDirectory -Description "target repository"
$objectivePath = Resolve-GnhfFleetFile -Path ([string](Get-RequiredProperty -Object $config -Name "objectivePath" -Description "scheduler config")) -BaseDirectory $configDirectory -Description "sprint objective"
$resolvedUsagePath = if ($UsageSnapshotPath) {
    Resolve-GnhfFleetFile -Path $UsageSnapshotPath -BaseDirectory $configDirectory -Description "usage snapshot"
}
else {
    Resolve-GnhfFleetFile -Path ([string](Get-RequiredProperty -Object $config -Name "usageSnapshotPath" -Description "scheduler config")) -BaseDirectory $configDirectory -Description "usage snapshot"
}
$stopWhen = [string](Get-RequiredProperty -Object $config -Name "stopWhen" -Description "scheduler config")
$profiles = @($config.profiles)
if ($profiles.Count -lt 1) {
    throw "Scheduler config contains no model profiles."
}

$InstallRoot = Ensure-GnhfFleetDirectory -Path $InstallRoot
$statePath = Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "state.json") -Description "fleet state"
$workerScript = Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "Start-GnhfSprint.ps1") -Description "bounded sprint launcher"
[void](Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -Depth 30)

$statusResult = Invoke-RouterGit -Repository $repoPath -Arguments @("status", "--porcelain=v1")
$dirty = @($statusResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($dirty.Count -gt 0) {
    throw "The target repository is dirty. Preserve unknown work and rerun from a clean checkout.`n$($dirty -join [Environment]::NewLine)"
}
$baseBranch = Get-RouterGitScalar -Repository $repoPath -Arguments @("branch", "--show-current")
if ([string]::IsNullOrWhiteSpace($baseBranch)) {
    throw "Detached HEAD is not allowed."
}
if ($baseBranch.StartsWith("gnhf/") -or $baseBranch.StartsWith("switchboard/gnhf-")) {
    throw "Start the bimodal scheduler from a clean non-GNHF base branch. Current branch: $baseBranch"
}

$objective = Get-Content -LiteralPath $objectivePath -Raw
if ([string]::IsNullOrWhiteSpace($objective)) {
    throw "The sprint objective is empty."
}
$objectiveSlug = ConvertTo-SafeSlug -Value (($objective -split '\r?\n' | Select-Object -First 1))
$runId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$runRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "bimodal-runs\$runId")
$decisionsRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $runRoot "decisions")
$segmentsRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $runRoot "segments")
$handoffPath = Join-Path $runRoot "router-handoff.md"
$stablePromptPath = Join-Path $runRoot "stable-objective.md"
$summaryPath = Join-Path $runRoot "bimodal-run.json"
$eventsPath = Join-Path $runRoot "events.jsonl"

$worktreeRootRaw = [string]$config.session.worktreeRoot
$worktreeRoot = if ($worktreeRootRaw -and $worktreeRootRaw -ne "__WORKTREE_ROOT__") {
    Get-GnhfFleetAbsolutePath -Path $worktreeRootRaw -BaseDirectory $configDirectory
}
else {
    "$repoPath-agent-switchboard-worktrees"
}
$worktreePath = Join-Path $worktreeRoot $runId
$routerBranch = "switchboard/gnhf-$objectiveSlug-$($runId.Substring(0, 15))"

$stablePrompt = @"
You are continuing a bounded unattended sprint on one scheduler-owned integration branch.

Primary objective:
$objective

Before each segment, read the current routing handoff at:
$handoffPath

Perform the single highest-value bounded task justified by the current repository state, prior commits, validation, and handoff evidence. Preserve prior useful work. Do not broaden scope. Validate before finalizing. Stop when this condition is true:
$stopWhen
"@
Set-Content -LiteralPath $stablePromptPath -Value $stablePrompt -Encoding utf8NoBOM

$events = [System.Collections.Generic.List[object]]::new()
$segments = [System.Collections.Generic.List[object]]::new()
$consumedByProfile = @{}
$blockedProfiles = @{}
$segmentCounts = @{}
$previousProfileId = $null
$previousOutcome = $null
$consecutiveNoProgress = 0
$objectiveComplete = $false
$stopReason = "not-started"
$runStatus = if ($PlanOnly) { "plan-only" } else { "partial" }
$startedAt = Get-Date
$worktreeCreated = $false

try {
    $initialSnapshot = Get-UsageSnapshot -Path $resolvedUsagePath -ConsumedByProfile $consumedByProfile -BlockedProfiles $blockedProfiles
    $initialSelection = Select-GnhfRoutingProfile -Mode $effectiveMode -Profiles $profiles -Snapshot $initialSnapshot.Data -Policy $config.policy -SegmentCounts $segmentCounts
    $initialTokenCap = if ($initialSelection.selected) {
        Get-GnhfSegmentTokenCap -SelectedState $initialSelection.selected -Mode $effectiveMode -Policy $config.policy -DefaultSegmentMaxTokens ([long]$config.session.segmentMaxTokens)
    }
    else {
        1L
    }
    $planDecisionPath = Join-Path $decisionsRoot "routing-decision-000.json"
    [void](Write-RoutingDecision -Path $planDecisionPath -RunId $runId -Segment 1 -EffectiveMode $effectiveMode -Selection $initialSelection -TokenCap $initialTokenCap -SnapshotHash $initialSnapshot.Hash)

    if ($PlanOnly) {
        $stopReason = "plan-only"
        Write-Host "Mode: $effectiveMode" -ForegroundColor Cyan
        Write-Host "Decision: $planDecisionPath"
        if ($initialSelection.selected) {
            Write-Host "Selected: $($initialSelection.selected.profileId) / $($initialSelection.selected.agent) / $($initialSelection.selected.model)" -ForegroundColor Green
            Write-Host "Segment token cap: $initialTokenCap"
        }
        else {
            Write-Warning "No eligible profile: $($initialSelection.reason)"
        }
    }
    else {
        [void](Ensure-GnhfFleetDirectory -Path $worktreeRoot)
        [void](Invoke-RouterGit -Repository $repoPath -Arguments @("worktree", "add", "-b", $routerBranch, $worktreePath, $baseBranch))
        $worktreeCreated = $true

        $maxSegments = [int]$config.session.maxSegments
        $maxWallMinutes = [int]$config.session.maxWallMinutes
        $segmentIterations = [int]$config.session.segmentMaxIterations
        $segmentWallMinutes = [int]$config.session.segmentWallMinutes
        $maxNoProgress = [int]$config.session.maxConsecutiveNoProgress
        $cooldownSeconds = [int]$config.session.cooldownSeconds

        for ($segmentNumber = 1; $segmentNumber -le $maxSegments; $segmentNumber++) {
            if (((Get-Date) - $startedAt).TotalMinutes -ge $maxWallMinutes) {
                $stopReason = "max-wall-time-reached"
                break
            }

            $snapshot = Get-UsageSnapshot -Path $resolvedUsagePath -ConsumedByProfile $consumedByProfile -BlockedProfiles $blockedProfiles
            $selection = Select-GnhfRoutingProfile -Mode $effectiveMode -Profiles $profiles -Snapshot $snapshot.Data -Policy $config.policy -PreviousProfileId $previousProfileId -PreviousOutcome $previousOutcome -SegmentCounts $segmentCounts
            if (-not $selection.selected) {
                $stopReason = [string]$selection.reason
                $runStatus = "blocked"
                break
            }

            $selected = $selection.selected
            $tokenCap = Get-GnhfSegmentTokenCap -SelectedState $selected -Mode $effectiveMode -Policy $config.policy -DefaultSegmentMaxTokens ([long]$config.session.segmentMaxTokens)
            $decisionPath = Join-Path $decisionsRoot ("routing-decision-{0:d3}.json" -f $segmentNumber)
            [void](Write-RoutingDecision -Path $decisionPath -RunId $runId -Segment $segmentNumber -EffectiveMode $effectiveMode -Selection $selection -TokenCap $tokenCap -SnapshotHash $snapshot.Hash)

            $historyText = if ($segments.Count -eq 0) {
                "No prior scheduler segments. Inspect the branch and choose the first bounded task."
            }
            else {
                (@($segments) | Select-Object -Last 5 | ForEach-Object {
                    "- segment $($_.segment): profile=$($_.profileId), status=$($_.status), commits=$($_.commitDelta), estimatedTokens=$($_.estimatedTokens)"
                }) -join [Environment]::NewLine
            }
            $handoff = @"
# AgentSwitchboard GNHF routing handoff

Run: $runId
Mode: $effectiveMode
Segment: $segmentNumber
Selected profile: $($selected.profileId)
Selected agent: $($selected.agent)
Selected model: $($selected.model)
Segment token cap: $tokenCap
Routing reason: $($selection.reason)
Branch: $routerBranch

## Recent scheduler outcomes
$historyText

## Required bounded behavior
- Inspect current commits, validation, GNHF notes, and debug logs.
- Continue from existing branch state; do not redo completed work.
- Perform one coherent bounded task that advances the primary objective.
- Preserve unknown or useful work.
- Validate the task before emitting the final result.
- Do not modify AgentSwitchboard routing policy unless the objective explicitly owns it.
- Report the stop condition only when it is actually satisfied.
"@
            Set-Content -LiteralPath $handoffPath -Value $handoff -Encoding utf8NoBOM

            $commitBefore = [int](Get-RouterGitScalar -Repository $worktreePath -Arguments @("rev-list", "--count", "HEAD"))
            $segmentStarted = Get-Date
            $segmentName = "bimodal-$($segmentNumber.ToString('000'))-$($selected.profileId)"
            $processResult = Start-BoundedSchedulerSegment -WorkerScript $workerScript -WorktreePath $worktreePath -Profile $selected -PromptPath $stablePromptPath -Name $segmentName -MaxIterations $segmentIterations -MaxTokens $tokenCap -StopWhen $stopWhen -InstallRoot $InstallRoot -TimeoutMinutes $segmentWallMinutes -DecisionPath $decisionPath
            $commitAfter = [int](Get-RouterGitScalar -Repository $worktreePath -Arguments @("rev-list", "--count", "HEAD"))
            $commitDelta = [Math]::Max(0, $commitAfter - $commitBefore)

            $newLogs = Get-NewGnhfLogFiles -WorktreePath $worktreePath -Since $segmentStarted
            $logTextParts = [System.Collections.Generic.List[string]]::new()
            [void]$logTextParts.Add($processResult.Text)
            foreach ($logFile in $newLogs) {
                try {
                    [void]$logTextParts.Add((Get-Content -LiteralPath $logFile.FullName -Raw))
                }
                catch {}
            }
            $combinedLogText = $logTextParts -join [Environment]::NewLine
            $outcome = Get-GnhfSegmentOutcome -ExitCode $processResult.ExitCode -LogText $combinedLogText -CommitDelta $commitDelta -TimedOut:$processResult.TimedOut
            $estimatedTokens = Get-EstimatedTokensFromText -Text $combinedLogText

            if ($null -ne $estimatedTokens) {
                if (-not $consumedByProfile.ContainsKey($selected.profileId)) {
                    $consumedByProfile[$selected.profileId] = 0L
                }
                $consumedByProfile[$selected.profileId] = [long]$consumedByProfile[$selected.profileId] + [long]$estimatedTokens
            }
            if ($outcome.status -in @("quota-exhausted", "authentication-blocked", "permanent-error", "timed-out")) {
                $blockedProfiles[$selected.profileId] = $outcome.status
            }
            if (-not $segmentCounts.ContainsKey($selected.profileId)) {
                $segmentCounts[$selected.profileId] = 0
            }
            $segmentCounts[$selected.profileId] = [int]$segmentCounts[$selected.profileId] + 1

            $launcherSummary = Get-ChildItem -LiteralPath (Join-Path $InstallRoot "logs") -Filter "launcher-summary.json" -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $segmentStarted } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

            $segmentRecord = [pscustomobject][ordered]@{
                segment = $segmentNumber
                profileId = $selected.profileId
                agent = $selected.agent
                model = $selected.model
                tokenCap = $tokenCap
                status = $outcome.status
                exitCode = $processResult.ExitCode
                commitDelta = $commitDelta
                estimatedTokens = $estimatedTokens
                decisionPath = $decisionPath
                launcherSummaryPath = if ($launcherSummary) { $launcherSummary.FullName } else { $null }
                logPaths = @($newLogs | ForEach-Object FullName)
            }
            [void]$segments.Add($segmentRecord)
            $segmentRecord | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $segmentsRoot ("segment-{0:d3}.json" -f $segmentNumber)) -Encoding utf8NoBOM
            $segmentRecord | ConvertTo-Json -Depth 8 -Compress | Add-Content -LiteralPath $eventsPath -Encoding utf8NoBOM

            if ($outcome.objectiveComplete) {
                $objectiveComplete = $true
                $runStatus = "completed"
                $stopReason = "objective-complete"
                break
            }

            if ($outcome.status -eq "no-progress") {
                $consecutiveNoProgress++
            }
            else {
                $consecutiveNoProgress = 0
            }
            if ($consecutiveNoProgress -ge $maxNoProgress) {
                $stopReason = "consecutive-no-progress-limit"
                break
            }

            $previousProfileId = [string]$selected.profileId
            $previousOutcome = [string]$outcome.status
            if ($cooldownSeconds -gt 0) {
                Start-Sleep -Seconds $cooldownSeconds
            }
            if ($segmentNumber -eq $maxSegments) {
                $stopReason = "max-segments-reached"
            }
        }

        if ($segments.Count -gt 0 -and $runStatus -notin @("completed", "blocked")) {
            $runStatus = "partial"
        }
    }
}
catch {
    $stopReason = "scheduler-failure: $($_.Exception.Message)"
    $runStatus = "failed"
    Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
    $summary = [ordered]@{
        schemaVersion = "agentswitchboard-gnhf-bimodal-run/v1"
        runId = $runId
        mode = $effectiveMode
        status = $runStatus
        startedAt = $startedAt.ToString("o")
        completedAt = (Get-Date).ToString("o")
        repoPath = $repoPath
        branch = if ($worktreeCreated) { $routerBranch } else { $null }
        worktreePath = if ($worktreeCreated) { $worktreePath } else { $null }
        stopReason = $stopReason
        objectiveComplete = $objectiveComplete
        segments = @($segments)
    }
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    Write-Host "`nBimodal run summary: $summaryPath" -ForegroundColor Cyan
    if ($worktreeCreated) {
        Write-Host "Review branch: $routerBranch" -ForegroundColor Cyan
        Write-Host "Review worktree: $worktreePath" -ForegroundColor Cyan
        Write-Host "The scheduler does not merge or push automatically." -ForegroundColor Yellow
    }
}

if ($runStatus -eq "failed") {
    exit 1
}
if ($runStatus -eq "blocked") {
    exit 2
}
exit 0
