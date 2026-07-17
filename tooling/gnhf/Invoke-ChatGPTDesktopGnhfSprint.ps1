[CmdletBinding(DefaultParameterSetName = "Plan")]
param(
    [Parameter(Mandatory)][string]$RequestPath,
    [Parameter(Mandatory)][string]$CompiledPromptPath,
    [string]$TargetRepo,
    [Parameter(ParameterSetName = "Plan")][switch]$PlanOnly,
    [Parameter(Mandatory, ParameterSetName = "Run")][switch]$Run,
    [switch]$CreateDisposableProofRepo,
    [ValidateSet("Desktop", "Cursor")][string]$RuntimeFamily = "Desktop"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$runtimeRoot = Join-Path $env:LOCALAPPDATA ("AgentSwitchboard\Gnhf{0}" -f $RuntimeFamily)
$runId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$evidenceDirectory = Join-Path $runtimeRoot $runId
$latestRunPath = Join-Path $runtimeRoot "latest-run.txt"
$transcriptPath = Join-Path $evidenceDirectory "terminal-transcript.txt"
$regularEvidencePath = Join-Path $evidenceDirectory "regular-request.txt"
$compiledEvidencePath = Join-Path $evidenceDirectory "compiled-gnhf-prompt.txt"
$promptValidationPath = Join-Path $evidenceDirectory "prompt-validation.json"
$launchResultPath = Join-Path $evidenceDirectory "launch-result.json"
$worktreeProofPath = Join-Path $evidenceDirectory "worktree-proof.json"
$validationSummaryPath = Join-Path $evidenceDirectory "validation-summary.json"
$operatorHandoffPath = Join-Path $evidenceDirectory "operator-handoff.txt"

New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
Set-Content -LiteralPath $latestRunPath -Value $evidenceDirectory -Encoding utf8NoBOM

$script:failureClassification = $null
$script:transcriptStarted = $false
$exitCode = 1
$executionMode = if ($Run) { "run" } else { "plan" }
$nonce = [guid]::NewGuid().ToString("N")
$requestDocument = $null
$compiledDocument = $null
$launchRequest = $null
$launchRequestValidation = $null
$renderedPrompt = $null
$resolvedTargetRepo = $null
$baseBranch = $null
$baseCommit = $null
$workstationPlan = $null
$processResult = $null
$beforeHeads = @{}
$proof = [ordered]@{
    branch = $null
    worktree = $null
    commit = $null
    commitsAhead = 0
    commitMessage = $null
    expectedArtifacts = @()
    changedFiles = @()
    artifactProof = $false
    nonce = $nonce
    baseClean = $false
    worktreeClean = $false
    sourceClean = $false
    failedBranches = @()
    failedWorktreePreserved = $null
    preservationGap = $null
}
$launchResult = [ordered]@{
    schemaVersion = 1
    kind = "gnhf-desktop-runtime-result"
    runId = $runId
    executionMode = $executionMode
    status = "starting"
    classification = "not-started"
    startedAt = (Get-Date).ToString("o")
    completedAt = $null
    sourceRoot = $sourceRoot
    targetRepo = $null
    evidenceDirectory = $evidenceDirectory
    canonicalLauncher = Join-Path $PSScriptRoot "Start-GnhfSprint.ps1"
    workstationPlanEntrypoint = Join-Path $sourceRoot "tooling\wsl\Start-TmuxGnhfWorkspaceSetup.ps1"
    startAcknowledged = $false
    processExitCode = $null
    processTimedOut = $false
    proofLevel = "contract-validation"
    proofCeiling = "Prompt contracts and a local workstation plan can be observed; provider response and repository mutation require a successful bounded run."
    branch = $null
    worktree = $null
    commit = $null
    artifactProof = $false
    baseClean = $false
    error = $null
}
$validationSummary = [ordered]@{
    schemaVersion = 1
    runId = $runId
    requestValid = $false
    compiledPromptValid = $false
    sourceClean = $false
    targetClean = $false
    targetAttached = $false
    workstationPlanPassed = $false
    visiblePromptEmitted = $false
    gnhfStartAcknowledged = $false
    processExitedZero = $false
    branchAhead = $false
    expectedArtifactsCommitted = $false
    exactChangedFiles = $false
    worktreeClean = $false
    baseClean = $false
    resultContractValid = $false
}

function Write-AtomicJson {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $temporaryPath -Encoding utf8NoBOM
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [ValidateRange(1, 7200)][int]$TimeoutSeconds = 30,
        [string]$WorkingDirectory
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    foreach ($argument in $ArgumentList) { [void]$startInfo.ArgumentList.Add($argument) }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try { $process.Kill($true) }
        catch { throw "Timed-out process could not be terminated: $FilePath. $($_.Exception.Message)" }
        if (-not $process.WaitForExit(5000)) {
            throw "Timed-out process tree did not exit within five seconds: $FilePath"
        }
    }
    if (-not $stdoutTask.Wait(5000) -or -not $stderrTask.Wait(5000)) {
        throw "Process output did not drain within five seconds: $FilePath"
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
    $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
    [pscustomobject]@{
        ExitCode = if ($timedOut) { 124 } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = $stdout
        Stderr = $stderr
        Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30,
        [switch]$AllowFailure
    )
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command git -ErrorAction Stop }
    $result = Invoke-BoundedProcess -FilePath $git.Source -ArgumentList (@("-C", $Repository) + $Arguments) -TimeoutSeconds $TimeoutSeconds
    if (-not $AllowFailure -and $result.ExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed in '$Repository'. $($result.Output)"
    }
    $result
}

function Get-GnhfBranchHeads {
    param([Parameter(Mandatory)][string]$Repository)
    $heads = @{}
    $result = Invoke-Git -Repository $Repository -Arguments @("for-each-ref", "--format=%(refname:short)|%(objectname)", "refs/heads/gnhf")
    foreach ($line in @($result.Stdout -split "\r?\n")) {
        if ($line -match '^([^|]+)\|([0-9a-f]{40})$') { $heads[$Matches[1]] = $Matches[2] }
    }
    $heads
}

function Get-WorktreeForBranch {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$Branch)
    $listing = Invoke-Git -Repository $Repository -Arguments @("worktree", "list", "--porcelain")
    $candidate = $null
    foreach ($line in @($listing.Stdout -split "\r?\n")) {
        if ($line.StartsWith("worktree ")) { $candidate = $line.Substring(9) }
        elseif ($line -eq "branch refs/heads/$Branch") { return $candidate }
        elseif ([string]::IsNullOrWhiteSpace($line)) { $candidate = $null }
    }
    $null
}

function New-DisposableRepository {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) { throw "Disposable proof repository path already exists: $Path" }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command git -ErrorAction Stop }
    foreach ($arguments in @(
        @("init", "-b", "main", $Path),
        @("-C", $Path, "config", "user.name", "AgentSwitchboard Disposable Proof"),
        @("-C", $Path, "config", "user.email", "agentswitchboard-proof@invalid.local")
    )) {
        $result = Invoke-BoundedProcess -FilePath $git.Source -ArgumentList $arguments -TimeoutSeconds 30
        if ($result.ExitCode -ne 0) { throw "Disposable repository initialization failed. $($result.Output)" }
    }
    Set-Content -LiteralPath (Join-Path $Path "README.md") -Value "# AgentSwitchboard disposable GNHF proof`n" -Encoding utf8NoBOM
    foreach ($arguments in @(
        @("-C", $Path, "add", "README.md"),
        @("-C", $Path, "commit", "-m", "test: initialize disposable proof repository")
    )) {
        $result = Invoke-BoundedProcess -FilePath $git.Source -ArgumentList $arguments -TimeoutSeconds 30
        if ($result.ExitCode -ne 0) { throw "Disposable repository baseline commit failed. $($result.Output)" }
    }
    [IO.Path]::GetFullPath($Path)
}

function Resolve-TargetRepository {
    param($Request, $Compiled)
    if ($CreateDisposableProofRepo) {
        if ($TargetRepo) { throw "-TargetRepo and -CreateDisposableProofRepo are mutually exclusive." }
        return New-DisposableRepository -Path (Join-Path $evidenceDirectory "disposable-repo")
    }
    $candidate = if ($TargetRepo) { $TargetRepo } elseif ($Compiled.repository.localPath) { [string]$Compiled.repository.localPath } else { [string]$Request.repository.localPath }
    if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate -match '^(__|\{\{|<).*TARGET_REPO') {
        throw "A concrete -TargetRepo is required when the request uses a portable target placeholder."
    }
    [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($candidate))
}

function Render-CompiledPrompt {
    param([Parameter(Mandatory)][string]$PromptText, [Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$ProofNonce)
    $rendered = $PromptText
    foreach ($placeholder in @("{{TARGET_REPO}}", "__TARGET_REPO__", "<TARGET_REPO>")) { $rendered = $rendered.Replace($placeholder, $Repository) }
    foreach ($placeholder in @("{{PROOF_NONCE}}", "__PROOF_NONCE__", "<PROOF_NONCE>")) { $rendered = $rendered.Replace($placeholder, $ProofNonce) }
    if (-not $rendered.Contains($Repository)) { throw "The compiled prompt does not contain the concrete target repository path." }
    if ($CreateDisposableProofRepo -and -not $rendered.Contains($ProofNonce)) { throw "The disposable proof prompt does not contain the generated nonce." }
    $rendered
}

function Get-ChangedGnhfProof {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)]$BeforeHeads,
        [Parameter(Mandatory)][string[]]$ExpectedArtifacts,
        [Parameter(Mandatory)][string]$ExpectedNonce,
        [Parameter(Mandatory)][string]$ExpectedCommitMessage
    )
    $candidates = [Collections.Generic.List[object]]::new()
    $afterHeads = Get-GnhfBranchHeads -Repository $Repository
    foreach ($branch in $afterHeads.Keys) {
        if ($BeforeHeads.ContainsKey($branch) -and $BeforeHeads[$branch] -eq $afterHeads[$branch]) { continue }
        $aheadResult = Invoke-Git -Repository $Repository -Arguments @("rev-list", "--count", "$Base..$branch")
        $ahead = [int]$aheadResult.Stdout.Trim()
        if ($ahead -le 0) { continue }
        $changedResult = Invoke-Git -Repository $Repository -Arguments @("diff", "--name-only", "$Base...$branch")
        $changed = @($changedResult.Stdout -split "\r?\n" | Where-Object { $_ } | Sort-Object -Unique)
        $expected = @($ExpectedArtifacts | ForEach-Object { $_ -replace '\\', '/' } | Sort-Object -Unique)
        $exactFiles = (($changed -join "`n") -ceq ($expected -join "`n"))
        $artifactProof = $true
        foreach ($artifact in $expected) {
            $content = Invoke-Git -Repository $Repository -Arguments @("show", "${branch}:$artifact") -AllowFailure
            if ($content.ExitCode -ne 0 -or -not $content.Stdout.Contains($ExpectedNonce)) { $artifactProof = $false }
        }
        $message = (Invoke-Git -Repository $Repository -Arguments @("log", "-1", "--format=%s", $branch)).Stdout.Trim()
        $worktree = Get-WorktreeForBranch -Repository $Repository -Branch $branch
        $worktreeClean = $false
        if ($worktree -and (Test-Path -LiteralPath $worktree -PathType Container)) {
            $worktreeClean = [string]::IsNullOrWhiteSpace((Invoke-Git -Repository $worktree -Arguments @("status", "--short")).Stdout)
        }
        [void]$candidates.Add([pscustomobject]@{
            Branch = $branch
            Commit = $afterHeads[$branch]
            CommitsAhead = $ahead
            ChangedFiles = $changed
            ExactFiles = $exactFiles
            ArtifactProof = $artifactProof
            CommitMessage = $message
            CommitMessageExact = ($message -ceq $ExpectedCommitMessage)
            Worktree = $worktree
            WorktreeClean = $worktreeClean
        })
    }
    $valid = @($candidates | Where-Object { $_.ExactFiles -and $_.ArtifactProof -and $_.CommitMessageExact -and $_.WorktreeClean })
    if ($valid.Count -ne 1) {
        throw "Expected exactly one changed GNHF branch with exact artifact, nonce, commit message, and clean worktree proof; found $($valid.Count)."
    }
    $valid[0]
}

try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
    $script:transcriptStarted = $true

    $bannerTitle = if ($RuntimeFamily -eq "Cursor") { "CURSOR LOCAL -> GNHF SPRINT" } else { "CHATGPT DESKTOP -> GNHF SPRINT" }
    Write-Host "=== $bannerTitle ===" -ForegroundColor Cyan
    Write-Host "Family:   $RuntimeFamily"
    Write-Host "Mode:     $executionMode"
    Write-Host "Evidence: $evidenceDirectory"

    foreach ($requiredPath in @(
        $sourceRoot,
        (Join-Path $PSScriptRoot "GnhfPromptContracts.psm1"),
        (Join-Path $PSScriptRoot "Start-GnhfSprint.ps1"),
        (Join-Path $sourceRoot "tooling\wsl\Start-TmuxGnhfWorkspaceSetup.ps1")
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required AgentSwitchboard runtime file is missing: $requiredPath" }
    }

    $RequestPath = [IO.Path]::GetFullPath($RequestPath)
    $CompiledPromptPath = [IO.Path]::GetFullPath($CompiledPromptPath)
    Import-Module (Join-Path $PSScriptRoot "GnhfPromptContracts.psm1") -Force
    $requestValidation = Test-GnhfPromptContractFile -Path $RequestPath -ExpectedKind "regular-sprint-request"
    $compiledValidation = Test-GnhfPromptContractFile -Path $CompiledPromptPath -ExpectedKind "compiled-gnhf-prompt-result"
    $validationSummary.requestValid = [bool]$requestValidation.Valid
    $validationSummary.compiledPromptValid = [bool]$compiledValidation.Valid
    if (-not $requestValidation.Valid) { throw "Regular request contract failed: $($requestValidation.Errors -join '; ')" }
    if (-not $compiledValidation.Valid) { throw "Compiled prompt contract failed: $($compiledValidation.Errors -join '; ')" }

    $requestText = Get-Content -LiteralPath $RequestPath -Raw
    $compiledText = Get-Content -LiteralPath $CompiledPromptPath -Raw
    Set-Content -LiteralPath $regularEvidencePath -Value $requestText -Encoding utf8NoBOM
    $requestDocument = $requestText | ConvertFrom-Json -Depth 50
    $compiledDocument = $compiledText | ConvertFrom-Json -Depth 50

    if ([string]$requestDocument.repository.name -cne [string]$compiledDocument.repository.name -or
        [string]$requestDocument.repository.remote -cne [string]$compiledDocument.repository.remote) {
        throw "The regular request and compiled prompt identify different repositories."
    }
    if ([string]$requestDocument.desiredProofLevel -cne [string]$compiledDocument.proofLevel) {
        throw "The compiled proof level exceeds or differs from the operator's requested proof level."
    }
    if ([string]$compiledDocument.gitExecution.mode -ne "worktree") {
        throw "The desktop GNHF v1 runtime delegates to Start-GnhfSprint.ps1 and therefore requires gitExecution.mode=worktree."
    }
    if ($compiledDocument.bounds.preventSleep -ne $true) {
        throw "The desktop GNHF v1 launcher requires bounds.preventSleep=true to match Start-GnhfSprint.ps1."
    }
    if ($CreateDisposableProofRepo -and [string]$compiledDocument.pushContract.mode -ne "none") {
        throw "Disposable proof repositories cannot be pushed."
    }

    $executionIntent = [string]$requestDocument.executionIntent
    if ($Run -and $executionIntent -eq "compile_only") {
        throw "executionIntent=compile_only rejects -Run. Use Plan mode or change the request intent to local_execute."
    }
    if ($Run -and $executionIntent -notin @("local_execute", "registered_workflow_execute")) {
        throw "executionIntent='$executionIntent' does not authorize local GNHF execution."
    }
    if ($executionIntent -eq "environment_configure" -and $Run) {
        throw "executionIntent=environment_configure authorizes workstation Plan/Apply only; use the existing setup entrypoints instead of -Run."
    }

    $sourceStatus = Invoke-Git -Repository $sourceRoot -Arguments @("status", "--short")
    if (-not [string]::IsNullOrWhiteSpace($sourceStatus.Stdout)) {
        throw "The AgentSwitchboard source checkout must be clean before desktop runtime execution."
    }
    $validationSummary.sourceClean = $true
    $proof.sourceClean = $true

    $resolvedTargetRepo = Resolve-TargetRepository -Request $requestDocument -Compiled $compiledDocument
    $launchResult.targetRepo = $resolvedTargetRepo
    if (-not (Test-Path -LiteralPath $resolvedTargetRepo -PathType Container)) { throw "Target repository does not exist: $resolvedTargetRepo" }
    $inside = Invoke-Git -Repository $resolvedTargetRepo -Arguments @("rev-parse", "--is-inside-work-tree")
    if ($inside.Stdout.Trim() -ne "true") { throw "Target is not a Git worktree: $resolvedTargetRepo" }
    $targetStatus = Invoke-Git -Repository $resolvedTargetRepo -Arguments @("status", "--short")
    if (-not [string]::IsNullOrWhiteSpace($targetStatus.Stdout)) {
        $script:failureClassification = "dirty-target-blocker"
        throw "Target repository must be clean before launch."
    }
    $validationSummary.targetClean = $true
    $baseBranch = (Invoke-Git -Repository $resolvedTargetRepo -Arguments @("branch", "--show-current")).Stdout.Trim()
    if ([string]::IsNullOrWhiteSpace($baseBranch)) {
        $script:failureClassification = "detached-target-blocker"
        throw "Detached target repositories cannot be launched."
    }
    if ([string]$compiledDocument.gitExecution.baseBranch -cne $baseBranch) {
        throw "Compiled base branch '$($compiledDocument.gitExecution.baseBranch)' does not match target branch '$baseBranch'."
    }
    $validationSummary.targetAttached = $true
    $baseCommit = (Invoke-Git -Repository $resolvedTargetRepo -Arguments @("rev-parse", "HEAD")).Stdout.Trim()

    $launchRequest = [pscustomobject][ordered]@{
        kind = "desktop-gnhf-launch-request"
        schemaVersion = 1
        requestPath = $RequestPath
        compiledPromptPath = $CompiledPromptPath
        targetRepo = $resolvedTargetRepo
        executionMode = if ($Run -and $CreateDisposableProofRepo) { "disposable-proof" } elseif ($Run) { "run" } else { "plan" }
        requireCleanTarget = $true
        visiblePromptEmission = $true
        timeoutSeconds = [int]$compiledDocument.bounds.timeoutSeconds
    }
    $launchRequestValidation = Test-GnhfPromptContract -Document $launchRequest -ExpectedKind "desktop-gnhf-launch-request"
    if (-not $launchRequestValidation.Valid) { throw "Desktop launch request contract failed: $($launchRequestValidation.Errors -join '; ')" }

    $renderedPrompt = Render-CompiledPrompt -PromptText ([string]$compiledDocument.prompt) -Repository $resolvedTargetRepo -ProofNonce $nonce
    Set-Content -LiteralPath $compiledEvidencePath -Value $renderedPrompt -Encoding utf8NoBOM
    $promptValidation = [ordered]@{
        schemaVersion = 1
        request = [ordered]@{ kind=$requestValidation.Kind; valid=$requestValidation.Valid; sha256=(Get-Sha256 $requestText); errors=@($requestValidation.Errors) }
        compiledPrompt = [ordered]@{ kind=$compiledValidation.Kind; valid=$compiledValidation.Valid; sourceSha256=(Get-Sha256 $compiledText); renderedPromptSha256=(Get-Sha256 $renderedPrompt); errors=@($compiledValidation.Errors) }
        launchRequest = [ordered]@{ kind=$launchRequestValidation.Kind; valid=$launchRequestValidation.Valid; errors=@($launchRequestValidation.Errors) }
        targetRepo = $resolvedTargetRepo
        nonce = $nonce
    }
    Write-AtomicJson -Value $promptValidation -Path $promptValidationPath

    Write-Host "`n=== COMPILED GNHF PROMPT (EXACT) ===" -ForegroundColor Yellow
    Write-Host $renderedPrompt
    Write-Host "=== END COMPILED GNHF PROMPT ===`n" -ForegroundColor Yellow
    $validationSummary.visiblePromptEmitted = $true

    $pwsh = Get-Command pwsh.exe -ErrorAction Stop
    $workstationPlanPath = Join-Path $sourceRoot "tooling\wsl\Start-TmuxGnhfWorkspaceSetup.ps1"
    $workstationPlanRoot = Join-Path $evidenceDirectory "workstation-plan"
    $workstationPlan = Invoke-BoundedProcess -FilePath $pwsh.Source -ArgumentList @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $workstationPlanPath,
        "-Mode", "Plan", "-RunRoot", $workstationPlanRoot
    ) -TimeoutSeconds 600 -WorkingDirectory $sourceRoot
    if ($workstationPlan.Output) { Write-Host $workstationPlan.Output }
    if ($workstationPlan.ExitCode -ne 0) {
        $script:failureClassification = "workstation-plan-blocker"
        throw "The existing workstation Plan workflow failed with exit code $($workstationPlan.ExitCode)."
    }
    $validationSummary.workstationPlanPassed = $true

    $expectedArtifacts = @($compiledDocument.expectedArtifacts | ForEach-Object { [string]$_.path })
    $proof.expectedArtifacts = $expectedArtifacts
    $proof.baseClean = $true
    if (-not $Run) {
        $launchResult.status = "planned"
        $launchResult.classification = "plan-complete"
        $launchResult.proofLevel = "contract-validation"
        $launchResult.proofCeiling = [string]$compiledDocument.proofCeiling
        $launchResult.baseClean = $true
        $validationSummary.baseClean = $true
        $exitCode = 0
    }
    else {
        $beforeHeads = Get-GnhfBranchHeads -Repository $resolvedTargetRepo
        # Disposable proofs prefer the auto-router so free/natural routes can satisfy the
        # artifact+commit gate when a pinned opencode provider is unhealthy. Explicit
        # non-disposable runs keep the compiled prompt's agent route via Start-GnhfSprint.
        $useAutoRouter = [bool]$CreateDisposableProofRepo
        $launcherPath = if ($useAutoRouter) {
            Join-Path $PSScriptRoot "Start-AutoRoutedGnhfSprint.ps1"
        }
        else {
            Join-Path $PSScriptRoot "Start-GnhfSprint.ps1"
        }
        $launcherArguments = @(
            "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $launcherPath,
            "-RepoPath", $resolvedTargetRepo,
            "-PromptPath", $compiledEvidencePath,
            "-Name", ("{0}-{1}" -f ($(if ($RuntimeFamily -eq "Cursor") { "cursor-local" } else { "chatgpt-desktop" }), $runId)),
            "-MaxIterations", [string]$compiledDocument.bounds.maxIterations,
            "-MaxTokens", [string]$compiledDocument.bounds.maxTokens,
            "-StopWhen", [string]$compiledDocument.stopCondition
        )
        if (-not $useAutoRouter) {
            $launcherArguments += @("-Agent", [string]$compiledDocument.agentRoute.agent)
        }
        if ((-not $useAutoRouter) -and [string]$compiledDocument.pushContract.mode -eq "manual") {
            $launcherArguments += "-PushBranch"
        }

        $ack = "AGENTSWITCHBOARD_GNHF_{0}_STARTED:{1}" -f $RuntimeFamily.ToUpperInvariant(), $runId
        Write-Host $ack -ForegroundColor Cyan
        if ($useAutoRouter) {
            Write-Host "Disposable proof launcher: Start-AutoRoutedGnhfSprint.ps1" -ForegroundColor Cyan
        }
        $launchResult.startAcknowledged = $true
        $validationSummary.gnhfStartAcknowledged = $true

        # For pinned opencode routes, reuse the auto-router DeepSeek config envelope.
        $previousOpenCodeConfig = $env:OPENCODE_CONFIG_CONTENT
        $agentName = [string]$compiledDocument.agentRoute.agent
        if ((-not $useAutoRouter) -and $agentName -eq "opencode") {
            $openCodeRuntimeConfig = [ordered]@{
                '$schema' = "https://opencode.ai/config.json"
                model = "deepseek/deepseek-v4-flash"
                share = "disabled"
                provider = [ordered]@{
                    deepseek = [ordered]@{
                        options = [ordered]@{
                            timeout = 600000
                            chunkTimeout = 60000
                        }
                    }
                }
            }
            $env:OPENCODE_CONFIG_CONTENT = $openCodeRuntimeConfig | ConvertTo-Json -Depth 10 -Compress
        }

        try {
            $processResult = Invoke-BoundedProcess -FilePath $pwsh.Source -ArgumentList $launcherArguments -TimeoutSeconds ([int]$compiledDocument.bounds.timeoutSeconds) -WorkingDirectory $resolvedTargetRepo
        }
        finally {
            if ($null -eq $previousOpenCodeConfig) {
                Remove-Item Env:OPENCODE_CONFIG_CONTENT -ErrorAction SilentlyContinue
            }
            else {
                $env:OPENCODE_CONFIG_CONTENT = $previousOpenCodeConfig
            }
        }

        $launchResult.processExitCode = $processResult.ExitCode
        $launchResult.processTimedOut = $processResult.TimedOut
        if ($processResult.Stdout) { Write-Host $processResult.Stdout }
        if ($processResult.Stderr) { Write-Warning $processResult.Stderr }
        if ($processResult.ExitCode -ne 0) {
            if ($processResult.Output -match '(?i)(quota|usage limit|tokens? remaining|rate.?limit)') { $script:failureClassification = "quota-exhausted-blocker" }
            elseif ($processResult.Output -match '(?i)(spawn|provider error|not found|unavailable|not ready|ENOENT)') { $script:failureClassification = "spawn-preflight-blocker" }
            elseif ($processResult.TimedOut) { $script:failureClassification = "bounded-timeout" }
            else { $script:failureClassification = "gnhf-nonzero" }
            throw "The canonical GNHF launcher failed with exit code $($processResult.ExitCode)."
        }
        $validationSummary.processExitedZero = $true

        $changedProof = Get-ChangedGnhfProof -Repository $resolvedTargetRepo -Base $baseCommit -BeforeHeads $beforeHeads -ExpectedArtifacts $expectedArtifacts -ExpectedNonce $nonce -ExpectedCommitMessage ([string]$compiledDocument.commitContract.message)
        $proof.branch = $changedProof.Branch
        $proof.worktree = $changedProof.Worktree
        $proof.commit = $changedProof.Commit
        $proof.commitsAhead = $changedProof.CommitsAhead
        $proof.commitMessage = $changedProof.CommitMessage
        $proof.changedFiles = $changedProof.ChangedFiles
        $proof.artifactProof = $changedProof.ArtifactProof
        $proof.worktreeClean = $changedProof.WorktreeClean
        $validationSummary.branchAhead = ($changedProof.CommitsAhead -gt 0)
        $validationSummary.expectedArtifactsCommitted = $changedProof.ArtifactProof
        $validationSummary.exactChangedFiles = $changedProof.ExactFiles
        $validationSummary.worktreeClean = $changedProof.WorktreeClean

        $baseStatusAfter = Invoke-Git -Repository $resolvedTargetRepo -Arguments @("status", "--short")
        $sourceStatusAfter = Invoke-Git -Repository $sourceRoot -Arguments @("status", "--short")
        $proof.baseClean = [string]::IsNullOrWhiteSpace($baseStatusAfter.Stdout)
        $proof.sourceClean = [string]::IsNullOrWhiteSpace($sourceStatusAfter.Stdout)
        if (-not $proof.baseClean) { throw "The disposable base checkout was changed by the proof." }
        if (-not $proof.sourceClean) { throw "The AgentSwitchboard source checkout changed during the proof." }
        $validationSummary.baseClean = $true

        $launchResult.status = "succeeded"
        $launchResult.classification = "disposable-runtime-proof-succeeded"
        $launchResult.proofLevel = [string]$compiledDocument.proofLevel
        $launchResult.proofCeiling = [string]$compiledDocument.proofCeiling
        $launchResult.branch = $changedProof.Branch
        $launchResult.worktree = $changedProof.Worktree
        $launchResult.commit = $changedProof.Commit
        $launchResult.artifactProof = $changedProof.ArtifactProof
        $launchResult.baseClean = $true
        $exitCode = 0
    }
}
catch {
    $launchResult.status = if ($script:failureClassification -and $script:failureClassification.EndsWith("blocker")) { "blocked" } else { "failed" }
    $launchResult.classification = if ($script:failureClassification) { $script:failureClassification } else { "runtime-validation-failed" }
    $launchResult.error = $_.Exception.Message
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    $exitCode = 1
}
finally {
    $launchResult.completedAt = (Get-Date).ToString("o")
    if ($resolvedTargetRepo -and (Test-Path -LiteralPath $resolvedTargetRepo -PathType Container)) {
        try {
            $finalBaseStatus = Invoke-Git -Repository $resolvedTargetRepo -Arguments @("status", "--short") -AllowFailure
            $proof.baseClean = ($finalBaseStatus.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($finalBaseStatus.Stdout))
            $validationSummary.baseClean = $proof.baseClean
            $launchResult.baseClean = $proof.baseClean
            $finalSourceStatus = Invoke-Git -Repository $sourceRoot -Arguments @("status", "--short") -AllowFailure
            $proof.sourceClean = ($finalSourceStatus.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($finalSourceStatus.Stdout))

            if ($Run -and $exitCode -ne 0) {
                $failedBranches = [Collections.Generic.List[object]]::new()
                $afterFailureHeads = Get-GnhfBranchHeads -Repository $resolvedTargetRepo
                foreach ($failedBranch in $afterFailureHeads.Keys) {
                    if ($beforeHeads.ContainsKey($failedBranch) -and $beforeHeads[$failedBranch] -eq $afterFailureHeads[$failedBranch]) { continue }
                    $failedWorktree = Get-WorktreeForBranch -Repository $resolvedTargetRepo -Branch $failedBranch
                    [void]$failedBranches.Add([pscustomobject][ordered]@{
                        branch = $failedBranch
                        headCommit = $afterFailureHeads[$failedBranch]
                        atBaseCommit = ($afterFailureHeads[$failedBranch] -eq $baseCommit)
                        worktree = $failedWorktree
                        worktreePreserved = [bool]$failedWorktree
                    })
                }
                $proof.failedBranches = @($failedBranches)
                if ($failedBranches.Count -gt 0) {
                    $proof.failedWorktreePreserved = @($failedBranches | Where-Object worktreePreserved).Count -gt 0
                    if (-not $proof.failedWorktreePreserved) {
                        $proof.preservationGap = "gnhf_removed_failed_worktree_branch_retained_for_review"
                    }
                }
            }
        }
        catch {
            if (-not $proof.preservationGap) { $proof.preservationGap = "failed_run_state_inspection_error: $($_.Exception.Message)" }
        }
    }
    $nextCommand = if ($compiledDocument -and $compiledDocument.PSObject.Properties.Name -contains "nextCommand") {
        [string]$compiledDocument.nextCommand
    }
    else {
        "Review $launchResultPath"
    }
    $evidenceResult = $null
    if (-not $Run -and $exitCode -eq 0 -and $launchRequest) {
        $evidenceResult = $launchRequest
    }
    else {
        $runtimeStatus = if ($exitCode -eq 0) {
            "succeeded"
        }
        elseif ($script:failureClassification -in @("dirty-target-blocker", "detached-target-blocker", "spawn-preflight-blocker", "quota-exhausted-blocker")) {
            "blocked"
        }
        else {
            "failed"
        }
        $artifactResults = @($proof.expectedArtifacts | ForEach-Object {
            [pscustomobject][ordered]@{ path=[string]$_; observed=($exitCode -eq 0 -and $proof.artifactProof) }
        })
        $validationResults = @(
            [pscustomobject][ordered]@{ command="prompt contracts"; result=$(if ($validationSummary.requestValid -and $validationSummary.compiledPromptValid) { "passed" } else { "failed" }) },
            [pscustomobject][ordered]@{ command="workstation plan"; result=$(if ($validationSummary.workstationPlanPassed) { "passed" } else { "skipped" }) },
            [pscustomobject][ordered]@{ command="visible prompt emission"; result=$(if ($validationSummary.visiblePromptEmitted) { "passed" } else { "skipped" }) },
            [pscustomobject][ordered]@{ command="git diff --check and proof verification"; result=$(if ($validationSummary.exactChangedFiles -and $validationSummary.expectedArtifactsCommitted) { "passed" } elseif ($Run -and $launchResult.startAcknowledged) { "failed" } else { "skipped" }) }
        )
        $evidenceResult = [ordered]@{
            kind = "desktop-gnhf-runtime-result"
            schemaVersion = 1
            status = $runtimeStatus
            targetState = [ordered]@{
                clean = [bool]$validationSummary.targetClean
                detached = (-not [bool]$validationSummary.targetAttached)
                branch = if ($baseBranch) { $baseBranch } else { $null }
                baseCommit = if ($baseCommit -match '^[0-9a-f]{7,40}$') { $baseCommit } else { "0000000" }
            }
            spawn = [ordered]@{ acknowledged=[bool]$launchResult.startAcknowledged; processId=$null }
            process = [ordered]@{ exitCode=$launchResult.processExitCode }
            commitProof = [ordered]@{
                required = $true
                observed = ($exitCode -eq 0 -and [bool]$proof.commit)
                branch = $proof.branch
                headCommit = $proof.commit
                commitsAhead = [int]$proof.commitsAhead
            }
            artifacts = $artifactResults
            validation = $validationResults
            proofLevel = if ($exitCode -eq 0) { [string]$launchResult.proofLevel } elseif ($launchResult.startAcknowledged) { "process-observed" } else { "preflight-only" }
            proofCeiling = [string]$launchResult.proofCeiling
            exactNextCommand = $nextCommand
        }
        if ($runtimeStatus -eq "blocked") {
            $blockerCode = switch ($script:failureClassification) {
                "dirty-target-blocker" { "DIRTY_TARGET" }
                "detached-target-blocker" { "DETACHED_HEAD" }
                "quota-exhausted-blocker" { "QUOTA_EXHAUSTED" }
                default { "SPAWN_PREFLIGHT_BLOCKED" }
            }
            $evidenceResult["blocker"] = [ordered]@{ code=$blockerCode; evidence=[string]$launchResult.error }
        }
    }
    if (Get-Command Test-GnhfPromptContract -ErrorAction SilentlyContinue) {
        $expectedResultKind = if ($evidenceResult.kind -eq "desktop-gnhf-launch-request") { "desktop-gnhf-launch-request" } else { "desktop-gnhf-runtime-result" }
        # Normalize nested ordered hashtables through JSON so contract property checks see real objects.
        $resultDocument = ($evidenceResult | ConvertTo-Json -Depth 40 | ConvertFrom-Json -Depth 40)
        $resultValidation = Test-GnhfPromptContract -Document $resultDocument -ExpectedKind $expectedResultKind
        $validationSummary.resultContractValid = [bool]$resultValidation.Valid
        if (-not $resultValidation.Valid) {
            $launchResult.status = "failed"
            $launchResult.classification = "runtime-result-contract-failed"
            $launchResult.error = $resultValidation.Errors -join "; "
            $exitCode = 1
        }
    }
    Write-AtomicJson -Value $proof -Path $worktreeProofPath
    Write-AtomicJson -Value $validationSummary -Path $validationSummaryPath
    Write-AtomicJson -Value $evidenceResult -Path $launchResultPath
    $handoffIsRuntimeResult = $evidenceResult.kind -eq "desktop-gnhf-runtime-result"
    $handoffStatus = if ($handoffIsRuntimeResult) { [string]$evidenceResult.status } else { "planned" }
    $handoffProofLevel = if ($handoffIsRuntimeResult) { [string]$evidenceResult.proofLevel } else { "contract-validation" }
    $handoffProofCeiling = if ($handoffIsRuntimeResult) { [string]$evidenceResult.proofCeiling } else { [string]$compiledDocument.proofCeiling }
    $handoffBranch = if ($handoffIsRuntimeResult) { [string]$evidenceResult.commitProof.branch } else { "" }
    $handoffCommit = if ($handoffIsRuntimeResult) { [string]$evidenceResult.commitProof.headCommit } else { "" }
    $handoffLabel = if ($RuntimeFamily -eq "Cursor") {
        "AgentSwitchboard Cursor local GNHF sprint"
    }
    else {
        "AgentSwitchboard ChatGPT Desktop GNHF sprint"
    }
    $handoff = @(
        $handoffLabel,
        "status: $handoffStatus",
        "classification: $($launchResult.classification)",
        "family: $RuntimeFamily",
        "mode: $executionMode",
        "target: $resolvedTargetRepo",
        "evidence: $evidenceDirectory",
        "branch: $handoffBranch",
        "worktree: $($proof.worktree)",
        "commit: $handoffCommit",
        "proof level: $handoffProofLevel",
        "proof ceiling: $handoffProofCeiling",
        "failed worktree preservation gap: $($proof.preservationGap)",
        "next command: $nextCommand"
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath $operatorHandoffPath -Value $handoff -Encoding utf8NoBOM
    Write-Host "`nLocal evidence: $evidenceDirectory" -ForegroundColor Cyan
    Write-Host "Operator handoff: $operatorHandoffPath" -ForegroundColor Cyan
    if ($script:transcriptStarted) { Stop-Transcript | Out-Null }
}

exit $exitCode
