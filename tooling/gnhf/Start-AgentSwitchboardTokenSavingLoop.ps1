[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$ObjectivePath,
    [ValidateSet("Auto", "Standard", "Free")][string]$ThinkerMode = "Auto",
    [ValidateSet("Auto", "agy", "opencode", "hermes")][string]$BuilderAgent = "Auto",
    [Parameter(Mandatory)][ValidateLength(1, 4000)][string]$ValidationCommand,
    [ValidateRange(1, 20)][int]$MaxInitialIterations = 4,
    [ValidateRange(0, 10)][int]$MaxRepairCycles = 2,
    [ValidateRange(1000, 1000000000)][int]$MaxTokensPerBuilderRun = 125000,
    [ValidateRange(500, 20000)][int]$MaxFailureChars = 6000,
    [ValidateRange(5, 3600)][int]$ValidatorTimeoutSeconds = 900,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -lt 7) { throw "PowerShell 7 is required." }

$RepoPath = [IO.Path]::GetFullPath($RepoPath)
$ObjectivePath = [IO.Path]::GetFullPath($ObjectivePath)
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) { throw "Repository not found: $RepoPath" }
if (-not (Test-Path -LiteralPath $ObjectivePath -PathType Leaf)) { throw "Objective file not found: $ObjectivePath" }

$routeHelpers = Join-Path $PSScriptRoot "TokenSaving.Route.ps1"
$processHelpers = Join-Path $PSScriptRoot "Gnhf.Process.ps1"
$thinkerLauncher = Join-Path $PSScriptRoot "Start-AgentSwitchboardThinker.ps1"
$operatorLauncher = Join-Path $PSScriptRoot "Start-AgentSwitchboard.ps1"
$gnhfLauncher = Join-Path $InstallRoot "Start-GnhfSprint.ps1"
foreach ($path in @($routeHelpers, $processHelpers, $thinkerLauncher, $operatorLauncher, $gnhfLauncher)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Token-saving runtime dependency not found: $path" }
}
. $routeHelpers
. $processHelpers

$statePath = Join-Path $InstallRoot "state.json"
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "Fleet state not found: $statePath. Run AgentSwitchboard setup first." }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$builder = Resolve-AgentSwitchboardBuilderRoute -Requested $BuilderAgent -State $state
if ($builder.status -ne "selected") {
    $details = @($builder.skipped | ForEach-Object { "$($_.route): $($_.reason)" }) -join "; "
    throw "No builder is ready. $details"
}

$dirty = @(& git -C $RepoPath status --porcelain=v1 2>&1)
if ($LASTEXITCODE -ne 0) { throw "Target path is not a usable Git worktree: $RepoPath" }
if (@($dirty | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw "Token-saving loop requires a clean target checkout before creating its isolated builder worktree."
}

$runId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"), [guid]::NewGuid().ToString("N")
$runRoot = Join-Path $InstallRoot "logs\token-saving-loop\$runId"
[void](New-Item -ItemType Directory -Path $runRoot -Force)
$planPath = Join-Path $runRoot "SYSTEM_PLAN.md"
$receiptPath = Join-Path $runRoot "loop-receipt.json"
$validationCommandSha256 = Get-AgentSwitchboardSha256Text -Text $ValidationCommand
$validationRecords = [System.Collections.Generic.List[object]]::new()
$repairRecords = [System.Collections.Generic.List[object]]::new()
$beforeWorktrees = @(Get-AgentSwitchboardGitWorktreePaths -RepoPath $RepoPath)
$worktreePath = $null
$planSha256 = $null
$status = "running"
$failureReason = $null

function Get-HeadSha {
    param([Parameter(Mandatory)][string]$Path)
    $sha = (& git -C $Path rev-parse HEAD 2>&1 | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $sha) { throw "Unable to resolve HEAD for $Path" }
    return ([string]$sha).Trim()
}

function Invoke-Validation {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Number
    )

    $pwsh = Get-Command pwsh -ErrorAction Stop
    $psi = New-GnhfProcessStartInfo -FilePath $pwsh.Source -ArgumentList @("-NoLogo", "-NoProfile", "-Command", $ValidationCommand) -WorkingDirectory $Path
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($ValidatorTimeoutSeconds * 1000)
        if ($timedOut) {
            try { $process.Kill($true) } catch {}
            try { $process.WaitForExit(5000) | Out-Null } catch {}
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
        $exitCode = if ($timedOut) { -1 } else { $process.ExitCode }
        $logPath = Join-Path $runRoot ("validation-{0:D2}.log" -f $Number)
        Set-Content -LiteralPath $logPath -Value $output -Encoding utf8NoBOM
        return [pscustomobject]@{
            number = $Number
            exitCode = $exitCode
            timedOut = $timedOut
            output = $output
            outputSha256 = Get-AgentSwitchboardSha256Text -Text $output
            logPath = $logPath
            headSha = Get-HeadSha -Path $Path
        }
    }
    finally { $process.Dispose() }
}

function Write-Receipt {
    $receipt = [ordered]@{
        schema = "agentswitchboard.token-saving-loop.v1"
        runId = $runId
        status = $status
        repoPath = $RepoPath
        objectivePath = $ObjectivePath
        thinkerMode = $ThinkerMode
        planPath = if (Test-Path -LiteralPath $planPath -PathType Leaf) { $planPath } else { $null }
        planSha256 = $planSha256
        builderRequested = $BuilderAgent
        builderSelected = $builder.route
        builderEvidence = $builder.evidence
        builderSkipped = @($builder.skipped)
        validationCommandSha256 = $validationCommandSha256
        maxInitialIterations = $MaxInitialIterations
        maxRepairCycles = $MaxRepairCycles
        maxTokensPerBuilderRun = $MaxTokensPerBuilderRun
        maxFailureChars = $MaxFailureChars
        worktreePath = $worktreePath
        validations = @($validationRecords)
        repairs = @($repairRecords)
        failureReason = $failureReason
        completedAt = if ($status -eq "running") { $null } else { (Get-Date).ToString("o") }
    }
    $receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
}

try {
    # The thinker is intentionally invoked exactly once. All later failures route only to the builder.
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $thinkerLauncher `
        -RepoPath $RepoPath `
        -PromptPath $ObjectivePath `
        -Mode $ThinkerMode `
        -OutputPath $planPath `
        -InstallRoot $InstallRoot
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
        throw "Thinker did not produce SYSTEM_PLAN.md."
    }
    $planText = Get-Content -LiteralPath $planPath -Raw
    $planSha256 = Get-AgentSwitchboardSha256Text -Text $planText

    $builderName = "token-loop-$($builder.route)-$($runId.Substring(0,17))"
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $operatorLauncher `
        -RepoPath $RepoPath `
        -Agent $builder.route `
        -PromptPath $planPath `
        -Name $builderName `
        -MaxIterations $MaxInitialIterations `
        -MaxTokens $MaxTokensPerBuilderRun `
        -StopWhen "Implement only the bounded SYSTEM_PLAN, commit the coherent change in the isolated worktree, and stop without merge or deployment." `
        -InstallRoot $InstallRoot
    if ($LASTEXITCODE -ne 0) { throw "Initial builder run failed." }

    $afterWorktrees = @(Get-AgentSwitchboardGitWorktreePaths -RepoPath $RepoPath)
    $beforeSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $beforeWorktrees) { [void]$beforeSet.Add($path) }
    $newWorktrees = @($afterWorktrees | Where-Object { -not $beforeSet.Contains($_) })
    if ($newWorktrees.Count -ne 1) {
        throw "Expected exactly one new GNHF worktree after the initial builder; observed $($newWorktrees.Count). Refusing to guess the repair target."
    }
    $worktreePath = $newWorktrees[0]

    $validationNumber = 1
    $validation = Invoke-Validation -Path $worktreePath -Number $validationNumber
    [void]$validationRecords.Add([ordered]@{
        number = $validation.number
        exitCode = $validation.exitCode
        timedOut = $validation.timedOut
        outputSha256 = $validation.outputSha256
        logPath = $validation.logPath
        headSha = $validation.headSha
    })

    $repairCycle = 0
    while (($validation.exitCode -ne 0 -or $validation.timedOut) -and $repairCycle -lt $MaxRepairCycles) {
        $repairCycle++
        $envelope = New-AgentSwitchboardFailureEnvelope `
            -ValidationNumber $validation.number `
            -ExitCode $validation.exitCode `
            -TimedOut $validation.timedOut `
            -Output $validation.output `
            -WorktreePath $worktreePath `
            -HeadSha $validation.headSha `
            -MaxFailureChars $MaxFailureChars

        $repairPromptPath = Join-Path $runRoot ("repair-{0:D2}.md" -f $repairCycle)
        $repairPrompt = @"
# DETERMINISTIC REPAIR ENVELOPE
The original SYSTEM_PLAN has already been implemented on this gnhf/* worktree. Do not ask for or replay the original conversation and do not call the thinker.
Repair only the concrete validation failure below. Inspect only the minimum repository context needed. Do not broaden scope, merge, deploy, or push.

- validation_number: $($envelope.validationNumber)
- exit_code: $($envelope.exitCode)
- timed_out: $($envelope.timedOut)
- validator_output_sha256: $($envelope.outputSha256)
- validator_output_chars: $($envelope.outputChars)
- excerpt_chars: $($envelope.excerptChars)
- worktree_head: $($envelope.headSha)

## Bounded failure excerpt
```text
$($envelope.excerpt)
```

Commit a coherent bounded repair, then stop. The orchestrator will rerun the deterministic validator itself.
"@
        Set-Content -LiteralPath $repairPromptPath -Value $repairPrompt -Encoding utf8NoBOM
        [void]$repairRecords.Add([ordered]@{
            cycle = $repairCycle
            failureEnvelopeSha256 = Get-AgentSwitchboardSha256Text -Text ($envelope | ConvertTo-Json -Depth 5 -Compress)
            promptPath = $repairPromptPath
            promptChars = $repairPrompt.Length
            inputHeadSha = $validation.headSha
        })

        & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $gnhfLauncher `
            -RepoPath $worktreePath `
            -Agent $builder.route `
            -PromptPath $repairPromptPath `
            -Name "$builderName-repair-$repairCycle" `
            -MaxIterations ([Math]::Min(2, $MaxInitialIterations)) `
            -MaxTokens $MaxTokensPerBuilderRun `
            -StopWhen "Resolve only the supplied deterministic validation failure, commit the bounded repair, and stop." `
            -InstallRoot $InstallRoot `
            -RepairCurrentGnhfBranch
        if ($LASTEXITCODE -ne 0) { throw "Builder repair cycle $repairCycle failed." }

        $validationNumber++
        $validation = Invoke-Validation -Path $worktreePath -Number $validationNumber
        [void]$validationRecords.Add([ordered]@{
            number = $validation.number
            exitCode = $validation.exitCode
            timedOut = $validation.timedOut
            outputSha256 = $validation.outputSha256
            logPath = $validation.logPath
            headSha = $validation.headSha
        })
    }

    if ($validation.exitCode -ne 0 -or $validation.timedOut) {
        throw "Deterministic validation is still failing after $repairCycle repair cycle(s)."
    }

    $status = "success"
}
catch {
    $status = "failed"
    $failureReason = $_.Exception.Message
    throw
}
finally {
    Write-Receipt
    Write-Host "Token-saving loop receipt: $receiptPath" -ForegroundColor Cyan
}

Write-Host "TOKEN-SAVING LOOP COMPLETE" -ForegroundColor Green
Write-Host "Builder:   $($builder.route)"
Write-Host "Worktree:  $worktreePath"
Write-Host "Plan SHA:  $planSha256"
Write-Host "Receipt:   $receiptPath"
