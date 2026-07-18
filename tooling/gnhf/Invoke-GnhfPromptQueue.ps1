[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [switch]$PlanOnly,
    [string]$RuntimeEntrypoint,
    [switch]$AllowAlternateRuntimeEntrypoint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$queueSupportRoot = Join-Path $PSScriptRoot "queue"
. (Join-Path $queueSupportRoot "GnhfPromptQueue.Repository.ps1")
. (Join-Path $queueSupportRoot "GnhfPromptQueue.Triggers.ps1")
. (Join-Path $queueSupportRoot "GnhfPromptQueue.Execution.ps1")

$PlanPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($PlanPath))
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) {
    throw "Prompt queue plan not found: $PlanPath"
}
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json -Depth 50
if ([string]$plan.schemaVersion -cne "agentswitchboard-gnhf-prompt-queue-plan/v1") {
    throw "Unsupported prompt queue plan schemaVersion: $($plan.schemaVersion)"
}
if ($plan.automaticPush -ne $false -or $plan.automaticMerge -ne $false) {
    throw "Prompt queue plan cannot authorize automatic push or merge."
}
if (-not ($plan.PSObject.Properties.Name -contains 'preAwarenessFlagging') -or
    $plan.preAwarenessFlagging.required -ne $true -or
    $plan.preAwarenessFlagging.completed -ne $true) {
    throw "Prompt queue plan did not complete required pre-awareness trigger flagging."
}
$laneIds = @($plan.lanes | ForEach-Object { [string]$_.laneId })
if ($laneIds.Count -ne @($laneIds | Sort-Object -Unique).Count) {
    throw "Prompt queue plan contains duplicate lane IDs."
}
if ([int]$plan.preAwarenessFlagging.laneSnapshotCount -ne $laneIds.Count) {
    throw "Prompt queue plan trigger snapshot count does not match its lanes."
}
$repoPaths = @($plan.lanes | ForEach-Object { [IO.Path]::GetFullPath([string]$_.repository.path).ToLowerInvariant() })
if ($repoPaths.Count -ne @($repoPaths | Sort-Object -Unique).Count) {
    throw "Prompt queue plan targets a repository path more than once."
}
$laneById = @{}
$triggerSnapshotByLane = @{}
foreach ($lane in @($plan.lanes)) {
    $laneById[[string]$lane.laneId] = $lane
    $triggerSnapshotByLane[[string]$lane.laneId] = Test-QueueTriggerGate -Lane $lane -QueueId ([string]$plan.queueId)
}
foreach ($lane in @($plan.lanes)) {
    foreach ($dependency in @($lane.dependsOn)) {
        if (-not $laneById.ContainsKey([string]$dependency)) {
            throw "Lane '$($lane.laneId)' depends on unknown lane '$dependency'."
        }
    }
}

$canonicalEntrypoint = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "Invoke-CursorGnhfSprint.ps1"))
$selectedEntrypoint = if ([string]::IsNullOrWhiteSpace($RuntimeEntrypoint)) {
    $canonicalEntrypoint
}
else {
    [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($RuntimeEntrypoint))
}
if ($selectedEntrypoint -cne $canonicalEntrypoint -and -not $AllowAlternateRuntimeEntrypoint) {
    throw "An alternate runtime entrypoint requires -AllowAlternateRuntimeEntrypoint."
}
if (-not (Test-Path -LiteralPath $selectedEntrypoint -PathType Leaf)) {
    throw "Cursor runtime entrypoint not found: $selectedEntrypoint"
}

if ($PlanOnly) {
    [pscustomobject][ordered]@{
        schemaVersion = "agentswitchboard-gnhf-prompt-queue-execution-plan/v1"
        queueId = [string]$plan.queueId
        planPath = $PlanPath
        runtimeEntrypoint = $selectedEntrypoint
        maxParallel = [int]$plan.maxParallel
        preAwarenessFlagging = $plan.preAwarenessFlagging
        batches = @($plan.batches | Sort-Object sequence)
        lanes = @($plan.lanes | ForEach-Object {
            [pscustomobject][ordered]@{
                laneId = $_.laneId
                batchId = $_.batchId
                applicationId = $_.application.id
                agentProfileId = $_.agentProfileId
                gnhfAgent = $_.gnhfAgent
                repository = $_.repository.name
                branch = $_.repository.branch
                pullRequest = $_.repository.pullRequest
                dependsOn = @($_.dependsOn)
                triggerFlagsPath = $_.triggerFlags.path
                triggerFlagsSha256 = $_.triggerFlags.sha256
                activeTriggerCount = $_.triggerFlags.activeCount
                criticalTriggerCount = $_.triggerFlags.criticalCount
                awarenessGateSatisfied = $true
                resultPath = $_.result.resultPath
            }
        })
        automaticPush = $false
        automaticMerge = $false
    } | ConvertTo-Json -Depth 30
    exit 0
}

$results = @{}
foreach ($batch in @($plan.batches | Sort-Object sequence)) {
    $running = [Collections.Generic.List[object]]::new()
    foreach ($laneId in @($batch.laneIds)) {
        $lane = $laneById[[string]$laneId]
        $dependencyResults = @($lane.dependsOn | ForEach-Object { $results[[string]$_] })
        if (@($dependencyResults | Where-Object { $null -eq $_ }).Count -gt 0) {
            throw "Batch '$($batch.batchId)' reached lane '$laneId' before all dependency results were available."
        }
        if (@($dependencyResults | Where-Object { $_.status -ne "succeeded" }).Count -gt 0) {
            foreach ($logPath in @([string]$lane.result.stdoutPath, [string]$lane.result.stderrPath)) {
                $logParent = Split-Path -Parent $logPath
                if (-not (Test-Path -LiteralPath $logParent -PathType Container)) {
                    [void](New-Item -ItemType Directory -Path $logParent -Force)
                }
                "" | Set-Content -LiteralPath $logPath -Encoding utf8NoBOM
            }
            $blocked = Write-QueueLaneResult `
                -Lane $lane `
                -QueueId ([string]$plan.queueId) `
                -Status "blocked-by-dependency" `
                -ProcessExitCode $null `
                -TimedOut $false `
                -ProofLevel "not-run" `
                -ObservedCommit $false `
                -ObservedArtifacts $false `
                -StartedAt (Get-Date) `
                -CompletedAt (Get-Date) `
                -RuntimeEvidencePath $null `
                -RuntimeResultPath $null `
                -Blocker "One or more dependency lanes did not succeed."
            $results[[string]$lane.laneId] = $blocked
            continue
        }
        [void]$running.Add((Start-QueueLane -Lane $lane -Entrypoint $selectedEntrypoint -QueueId ([string]$plan.queueId)))
    }

    while ($running.Count -gt 0) {
        Start-Sleep -Milliseconds 200
        for ($index = $running.Count - 1; $index -ge 0; $index--) {
            $active = $running[$index]
            $timedOut = ((Get-Date) - $active.startedAt).TotalSeconds -ge [int]$active.timeoutSeconds
            if ($active.process.HasExited -or $timedOut) {
                $result = Complete-QueueLane -Running $active -QueueId ([string]$plan.queueId) -TimedOut $timedOut
                $results[[string]$active.lane.laneId] = $result
                $running.RemoveAt($index)
            }
        }
    }
}

$orderedResults = @($plan.lanes | ForEach-Object { $results[[string]$_.laneId] })
$failed = @($orderedResults | Where-Object { $_.status -ne "succeeded" })
$registeredTriggers = @($plan.lanes | Measure-Object -Property { [int]$_.triggerFlags.registeredCount } -Sum).Sum
$activeTriggers = @($plan.lanes | Measure-Object -Property { [int]$_.triggerFlags.activeCount } -Sum).Sum
$criticalTriggers = @($plan.lanes | Measure-Object -Property { [int]$_.triggerFlags.criticalCount } -Sum).Sum
$summary = [pscustomobject][ordered]@{
    schemaVersion = "agentswitchboard-gnhf-prompt-queue-summary/v1"
    queueId = [string]$plan.queueId
    completedAt = (Get-Date).ToString("o")
    status = if ($failed.Count -eq 0) { "succeeded" } else { "completed-with-failures" }
    preAwarenessFlagsPresent = $true
    registeredTriggerCount = [int]$registeredTriggers
    activeTriggerCount = [int]$activeTriggers
    criticalTriggerCount = [int]$criticalTriggers
    succeeded = @($orderedResults | Where-Object { $_.status -eq "succeeded" }).Count
    failed = $failed.Count
    results = @($orderedResults | ForEach-Object {
        [pscustomobject][ordered]@{
            laneId = $_.laneId
            applicationId = $_.applicationId
            status = $_.status
            proofLevel = $_.proofLevel
            activeTriggerCount = $_.activeTriggerCount
            criticalTriggerCount = $_.criticalTriggerCount
            awarenessGateSatisfied = $_.awarenessGateSatisfied
            resultPath = $laneById[[string]$_.laneId].result.resultPath
            blocker = $_.blocker
        }
    })
    automaticPush = $false
    automaticMerge = $false
}
$summaryPath = Join-Path ([string]$plan.outputRoot) "queue-summary.json"
Write-AtomicJson -Value $summary -Path $summaryPath
$summaryMarkdownPath = Join-Path ([string]$plan.outputRoot) "queue-summary.md"
$summaryLines = @(
    "# AgentSwitchboard GNHF prompt queue — $($plan.queueId)",
    "",
    "- Status: ``$($summary.status)``",
    "- Pre-awareness flags present: ``true``",
    "- Registered triggers: ``$($summary.registeredTriggerCount)``",
    "- Active triggers: ``$($summary.activeTriggerCount)``",
    "- Active critical triggers: ``$($summary.criticalTriggerCount)``",
    "- Succeeded: ``$($summary.succeeded)``",
    "- Failed or blocked: ``$($summary.failed)``",
    "- Automatic push: ``false``",
    "- Automatic merge: ``false``",
    "",
    "## Lanes",
    ""
) + @($orderedResults | ForEach-Object {
    "- ``$($_.laneId)`` / ``$($_.applicationId)`` — ``$($_.status)`` — active flags ``$($_.activeTriggerCount)`` — awareness gate ``$($_.awarenessGateSatisfied)``"
})
$summaryLines | Set-Content -LiteralPath $summaryMarkdownPath -Encoding utf8NoBOM

Write-Host "Prompt queue complete: $summaryPath" -ForegroundColor Cyan
foreach ($result in $orderedResults) {
    Write-Host "  $($result.laneId): $($result.status) / $($result.activeTriggerCount) active trigger(s)"
}
if ($failed.Count -gt 0) { exit 1 }
exit 0
