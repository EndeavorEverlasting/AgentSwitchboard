[CmdletBinding(DefaultParameterSetName = "PromptFile")]
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$Agent,
    [Parameter(Mandatory, ParameterSetName = "PromptFile")][string]$PromptPath,
    [Parameter(Mandatory, ParameterSetName = "PromptText")][string]$Prompt,
    [string]$Name = "gnhf-sprint",
    [ValidateRange(1, 100)][int]$MaxIterations = 6,
    [ValidateRange(0, 1000000000)][int]$MaxTokens = 500000,
    [Parameter(Mandatory)][string]$StopWhen,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$PushBranch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pathHelpersPath = Join-Path $PSScriptRoot "GnhfFleet.Paths.ps1"
if (-not (Test-Path -LiteralPath $pathHelpersPath -PathType Leaf)) {
    throw "Path helper library not found: $pathHelpersPath"
}
. $pathHelpersPath

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & git -C $RepoPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Resolve-AgentSpec {
    param(
        [Parameter(Mandatory)][string]$RequestedAgent,
        [Parameter(Mandatory)]$State
    )

    $normalized = $RequestedAgent.ToLowerInvariant()
    if ($normalized.StartsWith("acp:")) {
        return $RequestedAgent
    }

    $knownNative = @("claude", "codex", "copilot", "pi", "rovodev", "opencode")
    if ($knownNative -contains $normalized -and $normalized -notin @("copilot", "opencode")) {
        return $normalized
    }

    $property = $State.agents.PSObject.Properties[$normalized]
    if (-not $property) {
        throw "Unknown agent '$RequestedAgent'. Use a native GNHF agent name or an acp:<command> specification."
    }

    $agentRecord = $property.Value
    if (-not $agentRecord.available) {
        throw "Agent '$RequestedAgent' is not ready. Evidence: $($agentRecord.evidence)"
    }

    return [string]$agentRecord.agentSpec
}

function Get-GnhfBranchHeads {
    $heads = @{}
    foreach ($line in @(Invoke-Git -Arguments @("for-each-ref", "--format=%(refname:short)|%(objectname)", "refs/heads/gnhf"))) {
        if ($line -match '^([^|]+)\|([0-9a-f]+)$') {
            $heads[$Matches[1]] = $Matches[2]
        }
    }
    return $heads
}

function Test-GnhfCommitProof {
    param(
        [Parameter(Mandatory)][string]$BaseCommit,
        [Parameter(Mandatory)]$BeforeBranches
    )

    foreach ($line in @(Invoke-Git -Arguments @("for-each-ref", "--format=%(refname:short)|%(objectname)", "refs/heads/gnhf"))) {
        if ($line -notmatch '^([^|]+)\|([0-9a-f]+)$') {
            continue
        }

        $branchName = $Matches[1]
        $branchHead = $Matches[2]
        if ($BeforeBranches.ContainsKey($branchName) -and $BeforeBranches[$branchName] -eq $branchHead) {
            continue
        }

        $ahead = [int]((Invoke-Git -Arguments @("rev-list", "--count", "$BaseCommit..$branchName") | Select-Object -First 1).Trim())
        if ($ahead -gt 0) {
            return [pscustomobject]@{
                Passed = $true
                Branch = $branchName
                CommitsAhead = $ahead
            }
        }
    }

    return [pscustomobject]@{
        Passed = $false
        Branch = $null
        CommitsAhead = 0
    }
}

function Write-AgyRouteStatus {
    param(
        [Parameter(Mandatory)][string]$Classification,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$Summary
    )

    $statusPath = $env:AGENTSWITCHBOARD_AGY_STATUS_PATH
    if ([string]::IsNullOrWhiteSpace($statusPath)) {
        return
    }

    $parent = Split-Path -Parent $statusPath
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [ordered]@{
        schemaVersion = 1
        completedAt = (Get-Date).ToString("o")
        classification = $Classification
        exitCode = $ExitCode
        modelMode = "agy-default"
        model = $null
        summary = $Summary
        source = "preflight"
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding utf8NoBOM
}

function Invoke-AgyQuotaPreflight {
    $agy = Get-Command agy -ErrorAction SilentlyContinue
    if (-not $agy) {
        return [pscustomobject]@{
            Classification = "agent-error"
            ExitCode = 127
            Summary = "AGY command was not found on PATH."
        }
    }

    $probeOutput = @(
        & $agy.Source `
            --mode plan `
            --print `
            "Return exactly this text and nothing else: AGY_ROUTER_PREFLIGHT_READY" 2>&1
    )
    $probeExitCode = $LASTEXITCODE
    $probeText = ($probeOutput -join [Environment]::NewLine).Trim()

    if ($probeExitCode -eq 0 -and $probeText -match 'AGY_ROUTER_PREFLIGHT_READY') {
        return [pscustomobject]@{
            Classification = "ready"
            ExitCode = 0
            Summary = "AGY natural allocation accepted the bounded plan-mode preflight."
        }
    }

    if ($probeText -match '(?i)(individual\s+quota\s+(has\s+been\s+)?reached|quota\s*(is\s*)?(reached|exhausted|exceeded)|usage\s+limit\s+(reached|exceeded)|free\s+(token|credit)s?\s+(are\s+)?(exhausted|used\s+up)|no\s+(free\s+)?tokens?\s+remaining|token\s+allowance\s+(is\s+)?exhausted)') {
        return [pscustomobject]@{
            Classification = "quota-exhausted"
            ExitCode = 75
            Summary = $probeText
        }
    }

    if ($probeText -match '(?i)(429|too many requests|rate.?limit)') {
        return [pscustomobject]@{
            Classification = "rate-limited"
            ExitCode = 76
            Summary = $probeText
        }
    }

    if ($probeText -match '(?i)(unauthorized|forbidden|authentication|login required|sign in)') {
        return [pscustomobject]@{
            Classification = "authentication-required"
            ExitCode = 77
            Summary = $probeText
        }
    }

    return [pscustomobject]@{
        Classification = "agent-error"
        ExitCode = 78
        Summary = if ($probeText) { $probeText } else { "AGY preflight returned no usable response." }
    }
}

$RepoPath = Resolve-GnhfFleetDirectory -Path $RepoPath -Description "target repository"
$InstallRoot = Get-GnhfFleetAbsolutePath -Path $InstallRoot
$statePath = Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "state.json") -Description "fleet state"
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$agentSpec = Resolve-AgentSpec -RequestedAgent $Agent -State $state

if ($PSCmdlet.ParameterSetName -eq "PromptFile") {
    $PromptPath = Resolve-GnhfFleetFile -Path $PromptPath -Description "sprint prompt"
    $objective = Get-Content -LiteralPath $PromptPath -Raw
}
else {
    $objective = $Prompt
}

if ([string]::IsNullOrWhiteSpace($objective)) {
    throw "The sprint prompt is empty."
}

$insideWorkTree = (Invoke-Git -Arguments @("rev-parse", "--is-inside-work-tree") | Select-Object -First 1).Trim()
if ($insideWorkTree -ne "true") {
    throw "Target path is not a Git working tree: $RepoPath"
}

$dirty = @(Invoke-Git -Arguments @("status", "--porcelain=v1"))
$dirty = @($dirty | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($dirty.Count -gt 0) {
    throw "GNHF requires a clean target worktree. Existing changes:`n$($dirty -join [Environment]::NewLine)"
}

$branch = (Invoke-Git -Arguments @("branch", "--show-current") | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw "Detached HEAD is not allowed for an unattended sprint."
}
if ($branch.StartsWith("gnhf/")) {
    throw "Launch worktree mode from a non-GNHF base branch. Current branch: $branch"
}

$baseCommit = (Invoke-Git -Arguments @("rev-parse", "HEAD") | Select-Object -First 1).Trim()
$gnhfBranchesBefore = Get-GnhfBranchHeads
$recentCommits = Invoke-Git -Arguments @("log", "--oneline", "--decorate", "-5")
$configuredGnhfPath = [string]$state.gnhf.commandPath
$gnhfPath = $null
if ($configuredGnhfPath -and (Test-Path -LiteralPath $configuredGnhfPath -PathType Leaf)) {
    $gnhfPath = (Get-Item -LiteralPath $configuredGnhfPath -Force).FullName
}
else {
    $gnhfCommand = Get-Command gnhf -ErrorAction SilentlyContinue
    if (-not $gnhfCommand) {
        throw "The configured GNHF executable is unavailable: $configuredGnhfPath. Rerun the installer to repair state."
    }
    $gnhfPath = $gnhfCommand.Source
}

$logsRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "logs")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$safeName = ($Name -replace "[^A-Za-z0-9._-]", "-").Trim("-")
if ([string]::IsNullOrWhiteSpace($safeName)) {
    $safeName = "gnhf-sprint"
}
$runLogDir = Ensure-GnhfFleetDirectory -Path (Join-Path $logsRoot "$timestamp-$safeName")
$transcriptPath = Join-Path $runLogDir "launcher-transcript.txt"
$summaryPath = Join-Path $runLogDir "launcher-summary.json"

$summary = [ordered]@{
    schemaVersion = 2
    name = $Name
    startedAt = (Get-Date).ToString("o")
    repoPath = $RepoPath
    baseBranch = $branch
    baseCommit = $baseCommit
    agentRequested = $Agent
    agentSpec = $agentSpec
    maxIterations = $MaxIterations
    maxTokens = $MaxTokens
    stopWhen = $StopWhen
    pushBranch = [bool]$PushBranch
    recentCommits = @($recentCommits)
    agyPreflightClassification = $null
    gnhfInvoked = $false
    commitProofBranch = $null
    commitProofCount = 0
    outcome = $null
    exitCode = $null
    completedAt = $null
    launcherLog = $transcriptPath
    promptSource = $PSCmdlet.ParameterSetName
    promptUtf8Bytes = [Text.Encoding]::UTF8.GetByteCount($objective)
}

$gnhfArguments = [System.Collections.Generic.List[string]]::new()
[void]$gnhfArguments.Add("--agent")
[void]$gnhfArguments.Add($agentSpec)
[void]$gnhfArguments.Add("--worktree")
[void]$gnhfArguments.Add("--max-iterations")
[void]$gnhfArguments.Add([string]$MaxIterations)
if ($MaxTokens -gt 0) {
    [void]$gnhfArguments.Add("--max-tokens")
    [void]$gnhfArguments.Add([string]$MaxTokens)
}
[void]$gnhfArguments.Add("--stop-when")
[void]$gnhfArguments.Add($StopWhen)
[void]$gnhfArguments.Add("--prevent-sleep")
[void]$gnhfArguments.Add("on")
if ($PushBranch) {
    [void]$gnhfArguments.Add("--push")
}

$env:GNHF_TELEMETRY = "0"
$exitCode = 1
$shouldInvokeGnhf = $true
$transcriptStarted = $false
$oldLocation = Get-Location

try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
    $transcriptStarted = $true

    Write-Host "`n=== GNHF SPRINT ===" -ForegroundColor Cyan
    Write-Host "Repo:       $RepoPath"
    Write-Host "Base:       $branch"
    Write-Host "Agent:      $agentSpec"
    Write-Host "Iterations: $MaxIterations"
    Write-Host "Token cap:  $MaxTokens"
    Write-Host "Push:       $([bool]$PushBranch)"
    Write-Host "Stop when:  $StopWhen"
    Write-Host "`nRecent commits:"
    $recentCommits | ForEach-Object { Write-Host "  $_" }

    $isAgyBridgeRun = $agentSpec -eq "pi" -and -not [string]::IsNullOrWhiteSpace($env:AGENTSWITCHBOARD_AGY_STATUS_PATH)
    if ($isAgyBridgeRun) {
        Write-Host "`nChecking AGY natural allocation before opening GNHF..." -ForegroundColor Cyan
        $agyPreflight = Invoke-AgyQuotaPreflight
        $summary.agyPreflightClassification = $agyPreflight.Classification

        if ($agyPreflight.Classification -ne "ready") {
            $sanitized = $agyPreflight.Summary -replace '(?i)(sk-[A-Za-z0-9_-]+)', '[redacted]'
            Write-AgyRouteStatus -Classification $agyPreflight.Classification -ExitCode $agyPreflight.ExitCode -Summary $sanitized
            Write-Warning "AGY preflight stopped before GNHF: $($agyPreflight.Classification)."
            $summary.outcome = "agy-preflight-$($agyPreflight.Classification)"
            $exitCode = if ($agyPreflight.ExitCode -eq 0) { 75 } else { $agyPreflight.ExitCode }
            $shouldInvokeGnhf = $false
        }
        else {
            Remove-Item -LiteralPath $env:AGENTSWITCHBOARD_AGY_STATUS_PATH -Force -ErrorAction SilentlyContinue
        }
    }

    if ($shouldInvokeGnhf) {
        $summary.gnhfInvoked = $true
        Set-Location -LiteralPath $RepoPath
        $objective | & $gnhfPath @gnhfArguments
        $exitCode = $LASTEXITCODE

        $commitProof = Test-GnhfCommitProof -BaseCommit $baseCommit -BeforeBranches $gnhfBranchesBefore
        $summary.commitProofBranch = $commitProof.Branch
        $summary.commitProofCount = $commitProof.CommitsAhead

        if ($exitCode -eq 0 -and -not $commitProof.Passed) {
            Write-Warning "GNHF returned exit code 0 without producing a new commit. Treating the route as failed."
            $summary.outcome = "no-commit-proof"
            $exitCode = 79
        }
        elseif ($exitCode -eq 0) {
            $summary.outcome = "committed"
        }
        else {
            $summary.outcome = "gnhf-nonzero"
        }
    }
}
catch {
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    $summary.outcome = "launcher-error"
    $exitCode = 1
}
finally {
    Set-Location -LiteralPath $oldLocation.Path
    $summary.exitCode = $exitCode
    $summary.completedAt = (Get-Date).ToString("o")
    [void](Ensure-GnhfFleetParentDirectory -Path $summaryPath)
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}

Write-Host "`nLauncher summary: $summaryPath" -ForegroundColor Cyan
exit $exitCode
