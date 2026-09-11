[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$PromptPath,
    [string]$OutputPath,
    [string]$ReceiptPath,
    [ValidateRange(1000, 16000)][int]$MaxPlanCharsPerLane = 12000,
    [ValidateRange(2000, 32000)][int]$MaxCombinedPlanChars = 28000,
    [ValidateRange(5, 900)][int]$LaneTimeoutSeconds = 300,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$ThinkerLauncherPath = (Join-Path $PSScriptRoot "Start-AgentSwitchboardThinker.ps1")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -lt 7) { throw "PowerShell 7 is required." }

$RepoPath = [IO.Path]::GetFullPath($RepoPath)
$PromptPath = [IO.Path]::GetFullPath($PromptPath)
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$ThinkerLauncherPath = [IO.Path]::GetFullPath($ThinkerLauncherPath)
foreach ($required in @($RepoPath, $PromptPath, $ThinkerLauncherPath)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Tandem thinker dependency not found: $required" }
}
if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) { throw "Repository directory not found: $RepoPath" }
if (-not (Test-Path -LiteralPath $PromptPath -PathType Leaf)) { throw "Tandem objective not found: $PromptPath" }
if (-not (Test-Path -LiteralPath $ThinkerLauncherPath -PathType Leaf)) { throw "Thinker launcher not found: $ThinkerLauncherPath" }

$objective = Get-Content -LiteralPath $PromptPath -Raw
if ([string]::IsNullOrWhiteSpace($objective)) { throw "Tandem objective is empty: $PromptPath" }

function Get-Sha256Text {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$runId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"), [guid]::NewGuid().ToString("N")
$runRoot = Join-Path $InstallRoot "logs\tandem-thinkers\$runId"
[void](New-Item -ItemType Directory -Path $runRoot -Force)
if (-not $OutputPath) { $OutputPath = Join-Path $runRoot "TANDEM_PLAN.md" }
else { $OutputPath = [IO.Path]::GetFullPath($OutputPath) }
if (-not $ReceiptPath) { $ReceiptPath = Join-Path $runRoot "tandem-receipt.json" }
else { $ReceiptPath = [IO.Path]::GetFullPath($ReceiptPath) }
foreach ($artifactPath in @($OutputPath, $ReceiptPath)) {
    $parent = Split-Path -Parent $artifactPath
    if ($parent) { [void](New-Item -ItemType Directory -Path $parent -Force) }
}

$pwsh = Get-Command pwsh -ErrorAction Stop
$laneSpecs = @(
    [pscustomobject]@{ id = "standard"; mode = "Standard"; planPath = (Join-Path $runRoot "standard-advisory.md") },
    [pscustomobject]@{ id = "free"; mode = "Free"; planPath = (Join-Path $runRoot "free-advisory.md") }
)
$running = [System.Collections.Generic.List[object]]::new()
$laneRecords = [System.Collections.Generic.List[object]]::new()
$status = "running"
$failureCode = $null
$failureMessage = $null
$combinedSha256 = $null
$overlapObserved = $false

function Write-TandemReceipt {
    $receipt = [ordered]@{
        schema = "agentswitchboard.tandem-thinkers.v1"
        runId = $runId
        status = $status
        failureCode = $failureCode
        failureMessage = $failureMessage
        repository = $RepoPath
        objectivePath = $PromptPath
        objectiveSha256 = Get-Sha256Text -Text $objective
        launchStrategy = "start-all-before-wait"
        parallelLaunchCount = 2
        overlapObserved = $overlapObserved
        maxPlanCharsPerLane = $MaxPlanCharsPerLane
        maxCombinedPlanChars = $MaxCombinedPlanChars
        laneTimeoutSeconds = $LaneTimeoutSeconds
        lanes = @($laneRecords)
        outputPath = if (Test-Path -LiteralPath $OutputPath -PathType Leaf) { $OutputPath } else { $null }
        outputSha256 = $combinedSha256
        mutationAuthority = "none-read-only-advisories"
        downstreamWriterContract = "exactly-one-writer-after-deterministic-rejoin"
        completedAt = if ($status -eq "running") { $null } else { (Get-Date).ToString("o") }
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReceiptPath -Encoding utf8NoBOM
}

function Start-TandemLane {
    param([Parameter(Mandatory)]$Lane)

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh.Source
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $RepoPath
    foreach ($arg in @(
        "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $ThinkerLauncherPath,
        "-RepoPath", $RepoPath,
        "-PromptPath", $PromptPath,
        "-Mode", [string]$Lane.mode,
        "-OutputPath", [string]$Lane.planPath,
        "-MaxPlanChars", [string]$MaxPlanCharsPerLane,
        "-TimeoutSeconds", [string]$LaneTimeoutSeconds,
        "-InstallRoot", $InstallRoot
    )) { [void]$psi.ArgumentList.Add([string]$arg) }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $process.StandardInput.Close()
    return [pscustomobject]@{
        lane = $Lane
        process = $process
        stdoutTask = $process.StandardOutput.ReadToEndAsync()
        stderrTask = $process.StandardError.ReadToEndAsync()
        startedAtUtc = [DateTime]::UtcNow
    }
}

function Complete-TandemLane {
    param([Parameter(Mandatory)]$RunningLane)
    $process = $RunningLane.process
    $parentBoundSeconds = $LaneTimeoutSeconds + 30
    $parentTimedOut = -not $process.WaitForExit($parentBoundSeconds * 1000)
    if ($parentTimedOut) {
        try { $process.Kill($true) } catch {}
        try { $process.WaitForExit(5000) | Out-Null } catch {}
    }
    $stdoutReady = $false; $stderrReady = $false
    try { $stdoutReady = $RunningLane.stdoutTask.Wait(5000) } catch {}
    try { $stderrReady = $RunningLane.stderrTask.Wait(5000) } catch {}
    $stdout = if ($stdoutReady) { [string]$RunningLane.stdoutTask.GetAwaiter().GetResult() } else { "" }
    $stderr = if ($stderrReady) { [string]$RunningLane.stderrTask.GetAwaiter().GetResult() } else { "" }
    $completedAtUtc = if (-not $parentTimedOut -and $process.HasExited) { $process.ExitTime.ToUniversalTime() } else { [DateTime]::UtcNow }
    $route = $null
    $match = [regex]::Match($stdout, '(?m)^Thinker:\s*(?<route>\S+)\s*$')
    if ($match.Success) { $route = [string]$match.Groups['route'].Value }
    $plan = if (Test-Path -LiteralPath $RunningLane.lane.planPath -PathType Leaf) { Get-Content -LiteralPath $RunningLane.lane.planPath -Raw } else { "" }
    $exitCode = if ($parentTimedOut) { -1 } elseif ($process.HasExited) { $process.ExitCode } else { -1 }
    $record = [ordered]@{
        laneId = [string]$RunningLane.lane.id
        requestedMode = [string]$RunningLane.lane.mode
        selectedRoute = $route
        startedAt = $RunningLane.startedAtUtc.ToString("o")
        completedAt = $completedAtUtc.ToString("o")
        exitCode = $exitCode
        parentTimedOut = $parentTimedOut
        stdoutDrainTimedOut = -not $stdoutReady
        stderrDrainTimedOut = -not $stderrReady
        stdoutPresent = -not [string]::IsNullOrWhiteSpace($stdout)
        stderrPresent = -not [string]::IsNullOrWhiteSpace($stderr)
        planPath = [string]$RunningLane.lane.planPath
        planChars = $plan.Length
        planSha256 = if ($plan) { Get-Sha256Text -Text $plan } else { $null }
    }
    return [pscustomobject]@{ record = $record; plan = $plan; completedAtUtc = $completedAtUtc }
}

try {
    # Concurrency contract: every read-only lane starts before the coordinator waits on any lane.
    foreach ($lane in $laneSpecs) { [void]$running.Add((Start-TandemLane -Lane $lane)) }

    $completed = [System.Collections.Generic.List[object]]::new()
    foreach ($lane in $running) { [void]$completed.Add((Complete-TandemLane -RunningLane $lane)) }

    $latestStart = @($running | ForEach-Object { $_.startedAtUtc } | Sort-Object -Descending | Select-Object -First 1)[0]
    $earliestCompletion = @($completed | ForEach-Object { $_.completedAtUtc } | Sort-Object | Select-Object -First 1)[0]
    $overlapObserved = ($latestStart -lt $earliestCompletion)

    foreach ($result in $completed) { [void]$laneRecords.Add($result.record) }
    $failedLanes = @($completed | Where-Object {
        $_.record.exitCode -ne 0 -or $_.record.parentTimedOut -or $_.record.stdoutDrainTimedOut -or $_.record.stderrDrainTimedOut -or
        [string]::IsNullOrWhiteSpace([string]$_.record.selectedRoute) -or [string]::IsNullOrWhiteSpace([string]$_.plan)
    })
    if ($failedLanes.Count -gt 0) {
        $failureCode = "TANDEM_LANE_FAILED"
        throw "One or more tandem advisory lanes failed or produced incomplete evidence."
    }
    if (-not $overlapObserved) {
        $failureCode = "TANDEM_PARALLELISM_NOT_OBSERVED"
        throw "Both advisory lanes completed, but their recorded process lifetimes did not overlap."
    }

    $routes = @($completed | ForEach-Object { [string]$_.record.selectedRoute })
    if (@($routes | Select-Object -Unique).Count -ne $routes.Count) {
        $failureCode = "TANDEM_ROUTE_COLLISION"
        throw "Tandem lanes resolved to the same thinker route. Independent attribution is required before deterministic rejoin."
    }

    $standard = @($completed | Where-Object { $_.record.laneId -eq "standard" })[0]
    $free = @($completed | Where-Object { $_.record.laneId -eq "free" })[0]
    $combined = @"
# TANDEM ADVISORY PACKET

This artifact is a deterministic rejoin of two independently executed read-only thinker lanes. It is advisory input to exactly one downstream writer; it grants no mutation, push, merge, deployment, or validation authority.

## Frozen objective identity
- sha256: $(Get-Sha256Text -Text $objective)

## Standard advisory
- route: $($standard.record.selectedRoute)
- plan_sha256: $($standard.record.planSha256)

$($standard.plan.Trim())

## Free advisory
- route: $($free.record.selectedRoute)
- plan_sha256: $($free.record.planSha256)

$($free.plan.Trim())

## Deterministic builder rejoin contract
- Treat both lane outputs as advisory, not authority.
- Reconcile conflicts against current repository evidence and governing contracts before mutation.
- Preserve one writer for every mutation surface; do not run competing writers against the same branch/worktree.
- Freeze acceptance criteria before implementation and let deterministic validators own pass/fail authority.
- Do not infer consensus merely because both advisers agree.
"@
    if ($combined.Length -gt $MaxCombinedPlanChars) {
        $failureCode = "TANDEM_REJOIN_TOO_LARGE"
        throw "Deterministic tandem rejoin is $($combined.Length) characters; cap is $MaxCombinedPlanChars. Reduce per-lane plan caps."
    }
    Set-Content -LiteralPath $OutputPath -Value $combined -Encoding utf8NoBOM -NoNewline
    $combinedSha256 = Get-Sha256Text -Text $combined
    $status = "success"
}
catch {
    $status = "failed"
    if (-not $failureCode) { $failureCode = "TANDEM_INTERNAL_FAILURE" }
    $failureMessage = $_.Exception.Message
    throw
}
finally {
    foreach ($lane in $running) {
        try { $lane.process.Dispose() } catch {}
    }
    Write-TandemReceipt
    Write-Host "TANDEM_THINKER_RECEIPT=$ReceiptPath"
}

Write-Host "TANDEM THINKERS COMPLETE" -ForegroundColor Green
Write-Host "Parallel lanes: 2"
Write-Host "Overlap:        $overlapObserved"
Write-Host "Plan:           $OutputPath"
Write-Host "Plan SHA:       $combinedSha256"
Write-Host "Receipt:        $ReceiptPath"
