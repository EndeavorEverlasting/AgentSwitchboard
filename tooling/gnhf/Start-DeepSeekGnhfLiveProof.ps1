[CmdletBinding()]
param(
    [string]$ModelId = "deepseek/deepseek-v4-pro",
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [ValidateRange(1, 10)][int]$MaxIterations = 2,
    [ValidateRange(1000, 250000)][long]$MaxTokens = 60000,
    [ValidateRange(1, 60)][int]$TimeoutMinutes = 20,
    [switch]$KeepDisposableState
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "DeepSeek live proof requires PowerShell 7."
}

$marker = "AGENTSWITCHBOARD_DEEPSEEK_LIVE_OK"
$profileId = "deepseek-live-proof"
$startedAt = Get-Date
$timestamp = $startedAt.ToString("yyyyMMdd-HHmmss")
$InstallRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallRoot))
$proofRoot = Join-Path $InstallRoot "live-proofs\deepseek-$timestamp"
$targetRepo = Join-Path $proofRoot "target-repository"
$promptPath = Join-Path $proofRoot "gnhf-objective.md"
$smokeLogPath = Join-Path $proofRoot "opencode-smoke.jsonl"
$smokeErrorPath = Join-Path $proofRoot "opencode-smoke.stderr.txt"
$modelListPath = Join-Path $proofRoot "opencode-models.txt"
$authListPath = Join-Path $proofRoot "opencode-auth.txt"
$activationPath = Join-Path $proofRoot "model-activation-observed.json"
$gnhfConsolePath = Join-Path $proofRoot "gnhf-console.txt"
$summaryPath = Join-Path $proofRoot "deepseek-live-proof-summary.json"

New-Item -ItemType Directory -Path $proofRoot, $targetRepo -Force | Out-Null

$summary = [ordered]@{
    schemaVersion = "agentswitchboard-deepseek-live-proof/v1"
    startedAt = $startedAt.ToString("o")
    completedAt = $null
    proofLevel = "preflight-only"
    status = "running"
    model = $ModelId
    runtimeState = [ordered]@{
        disposableRepository = $targetRepo
        installRoot = $InstallRoot
        personalDataMutation = $false
        stopRequired = $false
        stopReason = "No persistent app or service is used; the proof creates a disposable Git repository."
    }
    chain = [ordered]@{
        safeStartCompleted = $false
        launcherAttached = $false
        targetSurfaceReady = $false
        commandIssued = $false
        commandAcknowledged = $false
        behaviorObserved = $false
        runtimeArtifactCollected = $false
    }
    artifacts = [ordered]@{
        proofRoot = $proofRoot
        authList = $authListPath
        modelList = $modelListPath
        smokeOutput = $smokeLogPath
        smokeError = $smokeErrorPath
        activation = $activationPath
        gnhfConsole = $gnhfConsolePath
        launcherSummary = $null
        executionWorktree = $null
        behaviorArtifact = $null
    }
    failureReason = $null
}

function Save-ProofSummary {
    $summary.completedAt = (Get-Date).ToString("o")
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
}

function Invoke-ProcessBounded {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [string]$WorkingDirectory,
        [hashtable]$Environment = @{}
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($WorkingDirectory) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }
    foreach ($argument in $ArgumentList) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    foreach ($entry in $Environment.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            [void]$startInfo.Environment.Remove([string]$entry.Key)
        }
        else {
            $startInfo.Environment[[string]$entry.Key] = [string]$entry.Value
        }
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try {
            $process.Kill($true)
            $process.WaitForExit()
        }
        catch {}
    }

    [pscustomobject]@{
        ExitCode = if ($timedOut) { 124 } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = $stdoutTask.GetAwaiter().GetResult()
        Stderr = $stderrTask.GetAwaiter().GetResult()
    }
}

function Invoke-GitChecked {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $output = @(& git -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in '$Repository':`n$($output -join [Environment]::NewLine)"
    }
    @($output)
}

function Get-WorktreePaths {
    param([Parameter(Mandatory)][string]$Repository)
    @(
        Invoke-GitChecked -Repository $Repository -Arguments @("worktree", "list", "--porcelain") |
            Where-Object { $_ -like "worktree *" } |
            ForEach-Object { $_.Substring(9).Trim() }
    )
}

try {
    foreach ($commandName in @("git", "opencode", "gnhf", "pwsh")) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            throw "Required command is unavailable: $commandName"
        }
    }

    $launcherPath = Join-Path $PSScriptRoot "Start-GnhfSprint.ps1"
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
        throw "Repo-owned GNHF launcher not found: $launcherPath"
    }
    $statePath = Join-Path $InstallRoot "state.json"
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "AgentSwitchboard fleet state is missing: $statePath. Run the fleet installer first."
    }

    $authResult = Invoke-ProcessBounded `
        -FilePath (Get-Command opencode).Source `
        -ArgumentList @("auth", "list") `
        -TimeoutSeconds 30
    ($authResult.Stdout, $authResult.Stderr) -join [Environment]::NewLine |
        Set-Content -LiteralPath $authListPath -Encoding utf8NoBOM
    if ($authResult.ExitCode -ne 0 -or $authResult.Stdout -notmatch "(?i)deepseek") {
        throw "OpenCode does not report an authenticated DeepSeek provider. Run 'opencode auth login --provider deepseek' without sharing the key."
    }

    $modelsResult = Invoke-ProcessBounded `
        -FilePath (Get-Command opencode).Source `
        -ArgumentList @("models", "deepseek", "--refresh") `
        -TimeoutSeconds 90
    ($modelsResult.Stdout, $modelsResult.Stderr) -join [Environment]::NewLine |
        Set-Content -LiteralPath $modelListPath -Encoding utf8NoBOM
    if ($modelsResult.ExitCode -ne 0) {
        throw "OpenCode could not refresh the DeepSeek model registry. See $modelListPath"
    }
    if ($modelsResult.Stdout -notmatch [regex]::Escape($ModelId)) {
        throw "Requested model '$ModelId' is not in OpenCode's DeepSeek model list. See $modelListPath and rerun with -ModelId."
    }

    [void](& git init $targetRepo 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git init failed for disposable target repository." }
    [void](Invoke-GitChecked -Repository $targetRepo -Arguments @("config", "user.name", "AgentSwitchboard Live Proof"))
    [void](Invoke-GitChecked -Repository $targetRepo -Arguments @("config", "user.email", "live-proof@example.invalid"))
    Set-Content -LiteralPath (Join-Path $targetRepo "README.md") -Value "# Disposable DeepSeek GNHF live proof" -Encoding utf8NoBOM
    [void](Invoke-GitChecked -Repository $targetRepo -Arguments @("add", "README.md"))
    [void](Invoke-GitChecked -Repository $targetRepo -Arguments @("commit", "-m", "test: create disposable live proof floor"))
    $summary.chain.safeStartCompleted = $true
    $summary.chain.targetSurfaceReady = $true

    $runtimeConfig = [ordered]@{
        '$schema' = "https://opencode.ai/config.json"
        model = $ModelId
        small_model = $ModelId
        share = "disabled"
        autoupdate = $false
    } | ConvertTo-Json -Depth 8 -Compress

    $smokePrompt = "Return exactly $marker and nothing else. Do not call tools, read files, or modify anything."
    $summary.chain.commandIssued = $true
    $smokeResult = Invoke-ProcessBounded `
        -FilePath (Get-Command opencode).Source `
        -ArgumentList @(
            "run",
            "--model", $ModelId,
            "--format", "json",
            "--dir", $targetRepo,
            "--title", "AgentSwitchboard DeepSeek live proof",
            $smokePrompt
        ) `
        -TimeoutSeconds 180 `
        -Environment @{
            OPENCODE_CONFIG_CONTENT = $runtimeConfig
            OPENCODE_AUTO_SHARE = "false"
        }
    $smokeResult.Stdout | Set-Content -LiteralPath $smokeLogPath -Encoding utf8NoBOM
    $smokeResult.Stderr | Set-Content -LiteralPath $smokeErrorPath -Encoding utf8NoBOM
    if ($smokeResult.TimedOut) {
        throw "The direct DeepSeek response probe timed out after 180 seconds."
    }
    if ($smokeResult.ExitCode -ne 0) {
        throw "The direct DeepSeek response probe failed with exit code $($smokeResult.ExitCode). See $smokeErrorPath"
    }
    if ($smokeResult.Stdout -notmatch [regex]::Escape($marker)) {
        throw "OpenCode exited successfully, but the required DeepSeek response marker was not observed."
    }

    $summary.chain.commandAcknowledged = $true
    $summary.proofLevel = "live-provider-response-observed"
    $smokeHash = (Get-FileHash -LiteralPath $smokeLogPath -Algorithm SHA256).Hash
    [ordered]@{
        schemaVersion = "agentswitchboard-model-activation/v1"
        recordedAt = (Get-Date).ToString("o")
        profileId = $profileId
        agent = "opencode"
        requestedModel = $ModelId
        activationState = "observed-response"
        acknowledgedModel = $ModelId
        routingDecisionHash = $null
        evidenceKind = "provider-response"
        evidence = "OpenCode returned the controlled response marker under explicit --model selection. Sanitized output SHA-256: $smokeHash"
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $activationPath -Encoding utf8NoBOM

    Set-Content -LiteralPath $promptPath -Encoding utf8NoBOM -Value @"
You are running in a disposable Git repository created only for controlled live proof.

Create a file named deepseek-live-proof.json containing valid JSON with:
- schemaVersion: agentswitchboard-deepseek-behavior/v1
- marker: $marker
- modelRequested: $ModelId
- behavior: created-and-committed-by-gnhf-agent

Do not read or modify anything outside this repository.
Do not use network access.
Do not create additional files.
Validate the JSON, add it to Git, and commit it with message:
test: prove DeepSeek GNHF live behavior

The stop condition is satisfied only after the file exists in the active GNHF worktree and the commit succeeds.
"@

    $worktreesBefore = @(Get-WorktreePaths -Repository $targetRepo)
    $gnhfStartedAt = Get-Date
    $gnhfResult = Invoke-ProcessBounded `
        -FilePath (Get-Command pwsh).Source `
        -ArgumentList @(
            "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", $launcherPath,
            "-RepoPath", $targetRepo,
            "-Agent", "opencode",
            "-PromptPath", $promptPath,
            "-Name", "deepseek-live-proof",
            "-MaxIterations", [string]$MaxIterations,
            "-MaxTokens", [string]$MaxTokens,
            "-StopWhen", "deepseek-live-proof.json exists, contains $marker, and is committed",
            "-InstallRoot", $InstallRoot,
            "-ModelProfileId", $profileId,
            "-ModelId", $ModelId
        ) `
        -TimeoutSeconds ($TimeoutMinutes * 60) `
        -WorkingDirectory $targetRepo `
        -Environment @{
            OPENCODE_CONFIG_CONTENT = $runtimeConfig
            OPENCODE_AUTO_SHARE = "false"
        }
    ($gnhfResult.Stdout, $gnhfResult.Stderr) -join [Environment]::NewLine |
        Set-Content -LiteralPath $gnhfConsolePath -Encoding utf8NoBOM
    $summary.chain.launcherAttached = $true

    if ($gnhfResult.TimedOut) {
        throw "The bounded GNHF proof was terminated after $TimeoutMinutes minutes."
    }
    if ($gnhfResult.ExitCode -ne 0) {
        throw "The bounded GNHF proof exited with code $($gnhfResult.ExitCode). See $gnhfConsolePath"
    }

    $worktreesAfter = @(Get-WorktreePaths -Repository $targetRepo)
    $executionWorktree = @($worktreesAfter | Where-Object { $_ -notin $worktreesBefore } | Select-Object -First 1)
    if ($executionWorktree.Count -eq 0) {
        throw "GNHF exited successfully, but no new execution worktree was registered."
    }
    $executionWorktree = [string]$executionWorktree[0]
    $summary.artifacts.executionWorktree = $executionWorktree

    $behaviorArtifact = Join-Path $executionWorktree "deepseek-live-proof.json"
    if (-not (Test-Path -LiteralPath $behaviorArtifact -PathType Leaf)) {
        throw "GNHF exited successfully, but the behavior artifact was not found in '$executionWorktree'."
    }
    $behavior = Get-Content -LiteralPath $behaviorArtifact -Raw | ConvertFrom-Json
    if ([string]$behavior.marker -ne $marker -or [string]$behavior.modelRequested -ne $ModelId) {
        throw "The runtime artifact exists, but its marker or model request does not match the proof contract."
    }
    $committedPaths = @(Invoke-GitChecked -Repository $executionWorktree -Arguments @("show", "--name-only", "--format=", "HEAD"))
    if ($committedPaths -notcontains "deepseek-live-proof.json") {
        throw "The behavior artifact was observed but not included in the execution worktree's HEAD commit."
    }

    $launcherSummary = Get-ChildItem -LiteralPath (Join-Path $InstallRoot "logs") -Filter "launcher-summary.json" -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $gnhfStartedAt } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($launcherSummary) {
        $summary.artifacts.launcherSummary = $launcherSummary.FullName
        $launcherActivationPath = Join-Path $launcherSummary.Directory.FullName "model-activation.json"
        Copy-Item -LiteralPath $activationPath -Destination $launcherActivationPath -Force
        $launcherRecord = Get-Content -LiteralPath $launcherSummary.FullName -Raw | ConvertFrom-Json -Depth 30
        $launcherRecord.modelActivation = [pscustomobject][ordered]@{
            state = "observed-response"
            requestedModel = $ModelId
            acknowledgedModel = $ModelId
            acknowledgementPath = $launcherActivationPath
            evidenceKind = "provider-response"
            evidence = "Controlled OpenCode provider response observed before the bounded GNHF segment."
            recordedAt = (Get-Date).ToString("o")
            validationError = $null
        }
        $launcherRecord | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $launcherSummary.FullName -Encoding utf8NoBOM
    }

    $summary.chain.behaviorObserved = $true
    $summary.chain.runtimeArtifactCollected = $true
    $summary.artifacts.behaviorArtifact = $behaviorArtifact
    $summary.proofLevel = "live-gnhf-behavior-observed"
    $summary.status = "passed"
    Save-ProofSummary

    Write-Host "`nDeepSeek GNHF live proof: PASS" -ForegroundColor Green
    Write-Host "Proof level: $($summary.proofLevel)"
    Write-Host "Summary:     $summaryPath"
    Write-Host "Worktree:    $executionWorktree"
    Write-Host "Artifact:    $behaviorArtifact"
    exit 0
}
catch {
    $summary.status = "failed"
    $summary.failureReason = $_.Exception.Message
    Save-ProofSummary
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    Write-Host "`nDeepSeek GNHF live proof: FAILED" -ForegroundColor Red
    Write-Host "Proof level reached: $($summary.proofLevel)"
    Write-Host "Summary: $summaryPath"
    exit 1
}
finally {
    if (-not $KeepDisposableState -and $summary.status -ne "passed") {
        # Preserve failure evidence. Cleanup is intentionally manual after diagnosis.
    }
}
