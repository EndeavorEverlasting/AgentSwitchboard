[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [ValidateRange(1, 16)][int]$MaxParallelRepos,
    [switch]$PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ExpandedPath {
    param([Parameter(Mandatory)][string]$Path)
    [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
}

function Get-GitSnapshot {
    param([Parameter(Mandatory)][string]$Repository)
    $branch = @(& git -C $Repository branch --show-current 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Unable to read branch for '$Repository'." }
    $head = @(& git -C $Repository rev-parse HEAD 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Unable to read HEAD for '$Repository'." }
    $status = @(& git -C $Repository status --porcelain=v1 2>&1 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($LASTEXITCODE -ne 0) { throw "Unable to read status for '$Repository'." }
    [pscustomobject][ordered]@{ branch = ([string]$branch[0]).Trim(); head = ([string]$head[0]).Trim(); dirty = ($status.Count -gt 0); status = @($status) }
}


function New-OpenCodeRuntimeConfig {
    param(
        [Parameter(Mandatory)][string]$ModelId,
        [string]$ExistingConfig
    )

    $config = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($ExistingConfig)) {
        try {
            $existing = $ExistingConfig | ConvertFrom-Json -Depth 40
            foreach ($property in $existing.PSObject.Properties) {
                $config[$property.Name] = $property.Value
            }
        }
        catch {
            throw "Existing OPENCODE_CONFIG_CONTENT is not valid JSON and cannot be safely merged."
        }
    }
    $config["model"] = $ModelId
    $config["small_model"] = $ModelId
    $config["share"] = "disabled"
    $config["autoupdate"] = $false
    $config | ConvertTo-Json -Depth 40 -Compress
}

function Start-TandemLane {
    param([Parameter(Mandatory)]$Lane, [Parameter(Mandatory)][string]$LauncherPath, [Parameter(Mandatory)][string]$FleetRoot)
    $resultRoot = Split-Path -Parent ([string]$Lane.handoff.resultPath)
    if (-not (Test-Path -LiteralPath $resultRoot -PathType Container)) { [void](New-Item -ItemType Directory -Path $resultRoot -Force) }
    $stdoutPath = Join-Path $resultRoot "launcher-stdout.txt"
    $stderrPath = Join-Path $resultRoot "launcher-stderr.txt"
    $before = Get-GitSnapshot -Repository ([string]$Lane.repoPath)
    if ($before.dirty) { throw "Lane '$($Lane.laneId)' repository became dirty before launch." }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    $startInfo.WorkingDirectory = [string]$Lane.repoPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $LauncherPath,
        "-RepoPath", [string]$Lane.repoPath,
        "-Agent", [string]$Lane.agent,
        "-PromptPath", [string]$Lane.objectivePath,
        "-Name", "tandem-$($Lane.laneId)",
        "-MaxIterations", [string]$Lane.maxIterations,
        "-MaxTokens", [string]$Lane.maxTokens,
        "-StopWhen", [string]$Lane.stopWhen,
        "-InstallRoot", $FleetRoot,
        "-ModelProfileId", [string]$Lane.modelProfileId,
        "-ModelId", [string]$Lane.modelId
    )) { [void]$startInfo.ArgumentList.Add($argument) }
    $startInfo.Environment["AGENTSWITCHBOARD_HANDOFF_INPUT"] = [string]$Lane.handoff.inputPath
    $startInfo.Environment["AGENTSWITCHBOARD_HANDOFF_RESULT"] = [string]$Lane.handoff.resultPath
    $startInfo.Environment["AGENTSWITCHBOARD_HANDOFF_SUMMARY"] = [string]$Lane.handoff.summaryPath
    if ([string]$Lane.agent -eq "opencode") {
        $startInfo.Environment["OPENCODE_CONFIG_CONTENT"] = New-OpenCodeRuntimeConfig -ModelId ([string]$Lane.modelId) -ExistingConfig $env:OPENCODE_CONFIG_CONTENT
        $startInfo.Environment["OPENCODE_AUTO_SHARE"] = "false"
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    [pscustomobject][ordered]@{
        lane = $Lane
        process = $process
        stdoutTask = $process.StandardOutput.ReadToEndAsync()
        stderrTask = $process.StandardError.ReadToEndAsync()
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        startedAt = Get-Date
        before = $before
    }
}

function Complete-TandemLane {
    param([Parameter(Mandatory)]$Running, [Parameter(Mandatory)][bool]$TimedOut)
    $lane = $Running.lane
    if ($TimedOut) {
        try { $Running.process.Kill($true); $Running.process.WaitForExit() } catch {}
    }
    $stdout = $Running.stdoutTask.GetAwaiter().GetResult()
    $stderr = $Running.stderrTask.GetAwaiter().GetResult()
    $stdout | Set-Content -LiteralPath $Running.stdoutPath -Encoding utf8NoBOM
    $stderr | Set-Content -LiteralPath $Running.stderrPath -Encoding utf8NoBOM
    $exitCode = if ($TimedOut) { 124 } else { $Running.process.ExitCode }
    $after = Get-GitSnapshot -Repository ([string]$lane.repoPath)
    $launcherSummaryPath = $null
    if ($stdout -match '(?m)^Launcher summary:\s*(.+)$') { $launcherSummaryPath = $Matches[1].Trim() }
    $modelActivationState = "requested-only"
    if ($launcherSummaryPath -and (Test-Path -LiteralPath $launcherSummaryPath -PathType Leaf)) {
        try {
            $launcherSummary = Get-Content -LiteralPath $launcherSummaryPath -Raw | ConvertFrom-Json -Depth 30
            if ($launcherSummary.modelActivation -and $launcherSummary.modelActivation.state) { $modelActivationState = [string]$launcherSummary.modelActivation.state }
        } catch {}
    }
    $proofLevel = if ($modelActivationState -eq "observed-response") { "provider-response-observed" } elseif ($exitCode -eq 0) { "launcher-exit-observed" } else { "launcher-failure-observed" }
    $result = [ordered]@{
        schemaVersion = "agentswitchboard-gnhf-handoff-result/v1"
        recordedAt = (Get-Date).ToString("o")
        laneId = [string]$lane.laneId
        repository = [string]$lane.repository
        repoPath = [string]$lane.repoPath
        status = if ($exitCode -eq 0) { "completed" } elseif ($TimedOut) { "timed-out" } else { "failed" }
        exitCode = $exitCode
        timedOut = $TimedOut
        agent = [string]$lane.agent
        modelProfileId = [string]$lane.modelProfileId
        modelId = [string]$lane.modelId
        modelActivationState = $modelActivationState
        runtimeModelConfiguration = if ([string]$lane.agent -eq "opencode") { "applied" } else { "not-managed" }
        proofLevel = $proofLevel
        before = $Running.before
        after = $after
        launcherSummaryPath = $launcherSummaryPath
        stdoutPath = $Running.stdoutPath
        stderrPath = $Running.stderrPath
        changedBaseCheckout = ($Running.before.head -ne $after.head -or $Running.before.branch -ne $after.branch -or $after.dirty)
        automaticPush = $false
        automaticMerge = $false
    }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath ([string]$lane.handoff.resultPath) -Encoding utf8NoBOM
    @(
        "# GNHF tandem handoff — $($lane.laneId)",
        "",
        "- Repository: ``$($lane.repository)``",
        "- Agent: ``$($lane.agent)``",
        "- Model: ``$($lane.modelId)``",
        "- Runtime model configuration: ``$($result.runtimeModelConfiguration)``",
        "- Status: ``$($result.status)``",
        "- Exit code: ``$exitCode``",
        "- Proof level: ``$proofLevel``",
        "- Model activation: ``$modelActivationState``",
        "- Launcher summary: ``$launcherSummaryPath``",
        "- Result packet: ``$($lane.handoff.resultPath)``",
        "- Base checkout changed: ``$($result.changedBaseCheckout)``",
        "- Automatic push: ``false``",
        "- Automatic merge: ``false``"
    ) | Set-Content -LiteralPath ([string]$lane.handoff.summaryPath) -Encoding utf8NoBOM
    [pscustomobject]$result
}

$PlanPath = Resolve-ExpandedPath $PlanPath
$InstallRoot = Resolve-ExpandedPath $InstallRoot
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "Tandem plan not found: $PlanPath" }
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json -Depth 40
if ([string]$plan.schemaVersion -ne "agentswitchboard-gnhf-tandem-plan/v1") { throw "Unsupported tandem plan schemaVersion: $($plan.schemaVersion)" }
$parallelCap = if ($PSBoundParameters.ContainsKey("MaxParallelRepos")) { $MaxParallelRepos } else { [int]$plan.maxParallelRepos }
$parallelCap = [Math]::Min($parallelCap, [int]$plan.maxParallelRepos)
$launcherPath = Join-Path $PSScriptRoot "Start-GnhfSprint.ps1"
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) { throw "Repo-owned GNHF launcher not found: $launcherPath" }

$laneIds = @($plan.lanes | ForEach-Object { [string]$_.laneId })
if ($laneIds.Count -ne @($laneIds | Sort-Object -Unique).Count) { throw "Tandem plan contains duplicate lane IDs." }
$repoPaths = @($plan.lanes | ForEach-Object { (Resolve-ExpandedPath ([string]$_.repoPath)).ToLowerInvariant() })
if ($repoPaths.Count -ne @($repoPaths | Sort-Object -Unique).Count) { throw "Tandem plan targets the same repository path more than once." }

if ($PlanOnly) {
    [ordered]@{
        schemaVersion = "agentswitchboard-gnhf-tandem-execution-plan/v1"
        planPath = $PlanPath
        maxParallelRepos = $parallelCap
        lanes = @($plan.lanes | ForEach-Object { [ordered]@{ laneId = $_.laneId; repository = $_.repository; agent = $_.agent; modelId = $_.modelId; dependsOn = @($_.dependsOn); resultPath = $_.handoff.resultPath } })
        automaticPush = $false
        automaticMerge = $false
    } | ConvertTo-Json -Depth 12
    exit 0
}

$pending = [System.Collections.Generic.List[object]]::new()
foreach ($lane in @($plan.lanes)) { [void]$pending.Add($lane) }
$running = [System.Collections.Generic.List[object]]::new()
$results = @{}

while ($pending.Count -gt 0 -or $running.Count -gt 0) {
    $startedOne = $true
    while ($startedOne -and $running.Count -lt $parallelCap) {
        $startedOne = $false
        for ($index = 0; $index -lt $pending.Count; $index++) {
            $lane = $pending[$index]
            $dependencyStates = @($lane.dependsOn | ForEach-Object { $results[[string]$_] })
            if (@($dependencyStates | Where-Object { $null -eq $_ }).Count -gt 0) { continue }
            if (@($dependencyStates | Where-Object { $_.status -ne "completed" }).Count -gt 0) {
                [ordered]@{
                    schemaVersion = "agentswitchboard-gnhf-handoff-result/v1"
                    recordedAt = (Get-Date).ToString("o")
                    laneId = [string]$lane.laneId
                    repository = [string]$lane.repository
                    status = "blocked-by-dependency"
                    dependencies = @($lane.dependsOn)
                    automaticPush = $false
                    automaticMerge = $false
                } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ([string]$lane.handoff.resultPath) -Encoding utf8NoBOM
                $results[[string]$lane.laneId] = [pscustomobject]@{ status = "blocked-by-dependency" }
                $pending.RemoveAt($index)
                $startedOne = $true
                break
            }
            [void]$running.Add((Start-TandemLane -Lane $lane -LauncherPath $launcherPath -FleetRoot $InstallRoot))
            $pending.RemoveAt($index)
            $startedOne = $true
            break
        }
    }

    if ($running.Count -eq 0 -and $pending.Count -gt 0) { throw "Tandem plan dependency graph cannot make progress." }

    Start-Sleep -Milliseconds 500
    for ($index = $running.Count - 1; $index -ge 0; $index--) {
        $active = $running[$index]
        $timedOut = ((Get-Date) - $active.startedAt).TotalMinutes -ge [int]$active.lane.timeoutMinutes
        if ($active.process.HasExited -or $timedOut) {
            $result = Complete-TandemLane -Running $active -TimedOut $timedOut
            $results[[string]$active.lane.laneId] = $result
            $running.RemoveAt($index)
        }
    }
}

$failed = @($results.Values | Where-Object { $_.status -ne "completed" })
Write-Host "Tandem execution complete: $($results.Count) lane(s)" -ForegroundColor Cyan
foreach ($entry in $results.GetEnumerator() | Sort-Object Name) { Write-Host "  $($entry.Name): $($entry.Value.status)" }
if ($failed.Count -gt 0) { exit 1 }
exit 0
