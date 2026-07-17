function Write-AtomicJson {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $temporary -Encoding utf8NoBOM
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Write-QueueLaneResult {
    param(
        [Parameter(Mandatory)]$Lane,
        [Parameter(Mandatory)][string]$QueueId,
        [Parameter(Mandatory)][string]$Status,
        [AllowNull()][Nullable[int]]$ProcessExitCode,
        [Parameter(Mandatory)][bool]$TimedOut,
        [Parameter(Mandatory)][string]$ProofLevel,
        [Parameter(Mandatory)][bool]$ObservedCommit,
        [Parameter(Mandatory)][bool]$ObservedArtifacts,
        [Parameter(Mandatory)][datetime]$StartedAt,
        [Parameter(Mandatory)][datetime]$CompletedAt,
        [AllowNull()][string]$RuntimeEvidencePath,
        [AllowNull()][string]$RuntimeResultPath,
        [AllowNull()][string]$Blocker
    )

    $result = [pscustomobject][ordered]@{
        schemaVersion = "agentswitchboard-gnhf-prompt-queue-lane-result/v1"
        queueId = $QueueId
        laneId = [string]$Lane.laneId
        batchId = [string]$Lane.batchId
        status = $Status
        dependencies = @($Lane.dependsOn)
        runtimeFamily = [string]$Lane.runtimeFamily
        agentProfileId = [string]$Lane.agentProfileId
        gnhfAgent = [string]$Lane.gnhfAgent
        repoPath = [string]$Lane.repository.path
        requestPath = [string]$Lane.contracts.requestPath
        compiledPromptPath = [string]$Lane.contracts.compiledPromptPath
        runtimeEvidencePath = $RuntimeEvidencePath
        runtimeResultPath = $RuntimeResultPath
        processExitCode = if ($null -eq $ProcessExitCode) { $null } else { [int]$ProcessExitCode }
        timedOut = $TimedOut
        proofLevel = $ProofLevel
        observedCommit = $ObservedCommit
        observedArtifacts = $ObservedArtifacts
        startedAt = $StartedAt.ToString("o")
        completedAt = $CompletedAt.ToString("o")
        blocker = $Blocker
        stdoutPath = [string]$Lane.result.stdoutPath
        stderrPath = [string]$Lane.result.stderrPath
        automaticPush = $false
        automaticMerge = $false
    }
    Write-AtomicJson -Value $result -Path ([string]$Lane.result.resultPath)
    $result
}

function Start-QueueLane {
    param(
        [Parameter(Mandatory)]$Lane,
        [Parameter(Mandatory)][string]$Entrypoint,
        [Parameter(Mandatory)][string]$QueueId
    )

    foreach ($required in @(
        [string]$Lane.contracts.requestPath,
        [string]$Lane.contracts.compiledPromptPath,
        [string]$Lane.repository.path
    )) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Lane '$($Lane.laneId)' required path is missing: $required"
        }
    }
    $compiled = Get-Content -LiteralPath ([string]$Lane.contracts.compiledPromptPath) -Raw | ConvertFrom-Json -Depth 50
    if ([string]$compiled.agentRoute.agent -cne [string]$Lane.gnhfAgent) {
        throw "Lane '$($Lane.laneId)' compiled agent route no longer matches the queue plan."
    }
    $timeoutSeconds = [int]$compiled.bounds.timeoutSeconds
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwsh
    $startInfo.WorkingDirectory = [string]$Lane.repository.path
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $Entrypoint,
        "-RequestPath",
        [string]$Lane.contracts.requestPath,
        "-CompiledPromptPath",
        [string]$Lane.contracts.compiledPromptPath,
        "-TargetRepo",
        [string]$Lane.repository.path,
        "-Run"
    )) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    $startInfo.Environment["AGENTSWITCHBOARD_QUEUE_ID"] = $QueueId
    $startInfo.Environment["AGENTSWITCHBOARD_QUEUE_LANE"] = [string]$Lane.laneId
    $startInfo.Environment["AGENTSWITCHBOARD_AGENT_PROFILE"] = [string]$Lane.agentProfileId

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Failed to start queue lane '$($Lane.laneId)'."
    }
    [pscustomobject][ordered]@{
        lane = $Lane
        process = $process
        stdoutTask = $process.StandardOutput.ReadToEndAsync()
        stderrTask = $process.StandardError.ReadToEndAsync()
        startedAt = Get-Date
        timeoutSeconds = $timeoutSeconds
    }
}

function Complete-QueueLane {
    param(
        [Parameter(Mandatory)]$Running,
        [Parameter(Mandatory)][string]$QueueId,
        [Parameter(Mandatory)][bool]$TimedOut
    )

    $lane = $Running.lane
    if ($TimedOut -and -not $Running.process.HasExited) {
        try {
            $Running.process.Kill($true)
        }
        catch {
            throw "Timed-out lane '$($lane.laneId)' could not be terminated: $($_.Exception.Message)"
        }
        if (-not $Running.process.WaitForExit(5000)) {
            throw "Timed-out lane '$($lane.laneId)' did not terminate within the bounded cleanup window."
        }
    }
    elseif (-not $Running.process.HasExited) {
        throw "Lane '$($lane.laneId)' completion was requested before process exit."
    }
    else {
        [void]$Running.process.WaitForExit(5000)
    }

    $stdout = $Running.stdoutTask.GetAwaiter().GetResult()
    $stderr = $Running.stderrTask.GetAwaiter().GetResult()
    $stdoutParent = Split-Path -Parent ([string]$lane.result.stdoutPath)
    if (-not (Test-Path -LiteralPath $stdoutParent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $stdoutParent -Force)
    }
    $stdout | Set-Content -LiteralPath ([string]$lane.result.stdoutPath) -Encoding utf8NoBOM
    $stderr | Set-Content -LiteralPath ([string]$lane.result.stderrPath) -Encoding utf8NoBOM

    $exitCode = if ($TimedOut) { 124 } else { [int]$Running.process.ExitCode }
    $runtimeEvidencePath = $null
    $runtimeResultPath = $null
    $runtimeResult = $null
    $match = [regex]::Match($stdout, '(?m)^Local evidence:\s*(.+?)\s*$')
    if ($match.Success) {
        $runtimeEvidencePath = $match.Groups[1].Value.Trim()
        $candidate = Join-Path $runtimeEvidencePath "launch-result.json"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $runtimeResultPath = $candidate
            try {
                $runtimeResult = Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json -Depth 50
            }
            catch {
                $runtimeResult = $null
            }
        }
    }

    $observedCommit = $false
    $observedArtifacts = $false
    $validationPassed = $false
    $proofLevel = "preflight-only"
    $runtimeStatus = ""
    $blocker = $null
    if ($runtimeResult) {
        $runtimeStatus = [string]$runtimeResult.status
        if ($runtimeResult.PSObject.Properties.Name -contains "proofLevel") {
            $proofLevel = [string]$runtimeResult.proofLevel
        }
        if ($runtimeResult.PSObject.Properties.Name -contains "commitProof") {
            $observedCommit = ($runtimeResult.commitProof.observed -eq $true -and [int]$runtimeResult.commitProof.commitsAhead -gt 0)
        }
        if ($runtimeResult.PSObject.Properties.Name -contains "artifacts") {
            $artifacts = @($runtimeResult.artifacts)
            $observedArtifacts = ($artifacts.Count -gt 0 -and @($artifacts | Where-Object { $_.observed -ne $true }).Count -eq 0)
        }
        if ($runtimeResult.PSObject.Properties.Name -contains "validation") {
            $validationPassed = @($runtimeResult.validation | Where-Object { $_.result -eq "passed" }).Count -gt 0
        }
        if ($runtimeResult.PSObject.Properties.Name -contains "blocker") {
            $blocker = [string]$runtimeResult.blocker.evidence
        }
    }

    $succeeded = (-not $TimedOut -and
        $exitCode -eq 0 -and
        $runtimeStatus -eq "succeeded" -and
        $observedCommit -and
        $observedArtifacts -and
        $validationPassed)

    $status = if ($TimedOut) {
        "timed-out"
    }
    elseif ($succeeded) {
        "succeeded"
    }
    elseif ($runtimeStatus -eq "blocked") {
        "blocked"
    }
    else {
        "failed"
    }
    if (-not $blocker -and -not $succeeded) {
        $blocker = if (-not $runtimeResultPath) {
            "Canonical Cursor runtime result was not observed."
        }
        else {
            "Runtime result did not satisfy process, commit, artifact, and validation proof gates."
        }
    }

    Write-QueueLaneResult `
        -Lane $lane `
        -QueueId $QueueId `
        -Status $status `
        -ProcessExitCode $exitCode `
        -TimedOut $TimedOut `
        -ProofLevel $proofLevel `
        -ObservedCommit $observedCommit `
        -ObservedArtifacts $observedArtifacts `
        -StartedAt $Running.startedAt `
        -CompletedAt (Get-Date) `
        -RuntimeEvidencePath $runtimeEvidencePath `
        -RuntimeResultPath $runtimeResultPath `
        -Blocker $blocker
}
