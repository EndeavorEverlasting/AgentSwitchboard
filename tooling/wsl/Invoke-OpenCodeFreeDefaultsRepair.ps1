[CmdletBinding()]
param(
    [string]$SourceRepoPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$RemoteName = "origin",
    [string]$RemoteBranch = "feat/windows-workstation-live-runtime-proof",
    [string]$ValidatedHead = "",
    [string]$WorktreePath = "",
    [switch]$PlanOnly,
    [switch]$RemoveWorktreeOnSuccess
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or newer is required."
}
if ($env:OS -ne "Windows_NT") {
    throw "This workflow repairs the managed WSL OpenCode configuration from Windows."
}

function Invoke-BoundedNative {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = "",
        [ValidateRange(1, 900)][int]$TimeoutSeconds = 120
    )

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($WorkingDirectory) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            $process.Kill($true)
            $process.WaitForExit()
        }
        catch {}
        throw "Command timed out after $TimeoutSeconds seconds: $FilePath"
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
    $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
        Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(2, 32)][int]$Depth = 12
    )

    $json = $Value | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Get-NativeFailureMessage {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)]$Result
    )

    $detail = $Result.Output
    if (-not $detail) {
        $detail = "exit code $($Result.ExitCode)"
    }
    "$Operation failed: $detail"
}

$resolvedSource = (Resolve-Path -LiteralPath $SourceRepoPath -ErrorAction Stop).Path
Set-Location -LiteralPath $resolvedSource

$gitRoot = Invoke-BoundedNative -FilePath "git" -ArgumentList @("rev-parse", "--show-toplevel") -WorkingDirectory $resolvedSource -TimeoutSeconds 30
if ($gitRoot.ExitCode -ne 0) {
    throw (Get-NativeFailureMessage -Operation "Repository resolution" -Result $gitRoot)
}
if ([IO.Path]::GetFullPath($gitRoot.Stdout) -ne [IO.Path]::GetFullPath($resolvedSource)) {
    throw "SourceRepoPath must be the AgentSwitchboard repository root: $resolvedSource"
}
if ($RemoteName -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Unsafe Git remote name: $RemoteName"
}
if ($RemoteBranch -notmatch '^[A-Za-z0-9._/-]+$') {
    throw "Unsafe Git branch name: $RemoteBranch"
}
if ($ValidatedHead -and $ValidatedHead -notmatch '^[0-9a-fA-F]{40}$') {
    throw "ValidatedHead must be a full 40-character commit SHA."
}

$sourceStatus = Invoke-BoundedNative -FilePath "git" -ArgumentList @("status", "--short") -WorkingDirectory $resolvedSource -TimeoutSeconds 30
if ($sourceStatus.ExitCode -ne 0) {
    throw (Get-NativeFailureMessage -Operation "Source checkout inspection" -Result $sourceStatus)
}
$sourceDirty = [bool]$sourceStatus.Stdout

$fetch = Invoke-BoundedNative -FilePath "git" -ArgumentList @("fetch", $RemoteName, $RemoteBranch) -WorkingDirectory $resolvedSource -TimeoutSeconds 180
if ($fetch.ExitCode -ne 0) {
    throw (Get-NativeFailureMessage -Operation "Remote branch fetch" -Result $fetch)
}

$remoteRef = "refs/remotes/$RemoteName/$RemoteBranch"
$remoteHeadResult = Invoke-BoundedNative -FilePath "git" -ArgumentList @("rev-parse", "--verify", "$remoteRef^{commit}") -WorkingDirectory $resolvedSource -TimeoutSeconds 30
if ($remoteHeadResult.ExitCode -ne 0 -or $remoteHeadResult.Stdout -notmatch '^[0-9a-f]{40}$') {
    throw (Get-NativeFailureMessage -Operation "Remote head resolution" -Result $remoteHeadResult)
}
$targetHead = $remoteHeadResult.Stdout
if ($ValidatedHead) {
    $targetHead = $ValidatedHead.ToLowerInvariant()
}

$commitProbe = Invoke-BoundedNative -FilePath "git" -ArgumentList @("cat-file", "-e", "$targetHead^{commit}") -WorkingDirectory $resolvedSource -TimeoutSeconds 30
if ($commitProbe.ExitCode -ne 0) {
    throw "Validated repair commit is unavailable: $targetHead"
}
$ancestorProbe = Invoke-BoundedNative -FilePath "git" -ArgumentList @("merge-base", "--is-ancestor", $targetHead, $remoteRef) -WorkingDirectory $resolvedSource -TimeoutSeconds 30
if ($ancestorProbe.ExitCode -ne 0) {
    throw "Validated repair commit is not contained by $RemoteName/$RemoteBranch`: $targetHead"
}

$runId = "{0}-{1}" -f (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ"), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$stateRoot = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\OpenCodeFreeDefaults"
$runRoot = Join-Path (Join-Path $stateRoot "runs") $runId
[void](New-Item -ItemType Directory -Path $runRoot -Force)

if (-not $WorktreePath) {
    $devRoot = Split-Path -Parent $resolvedSource
    $WorktreePath = Join-Path $devRoot "AgentSwitchboard-opencode-free-$runId"
}
$WorktreePath = [IO.Path]::GetFullPath($WorktreePath)

$runContextPath = Join-Path $runRoot "run-context.json"
$registryPath = Join-Path $runRoot "artifact-registry.json"
$effectiveConfigPath = Join-Path $runRoot "effective-opencode-config.json"
$installerOutputPath = Join-Path $runRoot "installer-output.txt"
$reportPath = Join-Path $runRoot "operator-report.md"
$handoffPath = Join-Path $runRoot "final-handoff.json"
$latestPath = Join-Path $stateRoot "latest-run.txt"

$script:artifacts = [System.Collections.Generic.List[object]]::new()
$script:runContext = [ordered]@{
    schemaVersion = 1
    runId = $runId
    workflowId = "opencode-free-defaults-repair"
    startedAt = (Get-Date).ToUniversalTime().ToString("o")
    completedAt = $null
    mode = $(if ($PlanOnly) { "plan-only" } else { "apply" })
    sourceRepoPath = $resolvedSource
    sourceDirty = $sourceDirty
    remoteName = $RemoteName
    remoteBranch = $RemoteBranch
    requestedValidatedHead = $(if ($ValidatedHead) { $ValidatedHead } else { $null })
    targetHead = $targetHead
    worktreePath = $WorktreePath
    distribution = $null
    status = "starting"
    error = $null
    proofLevel = "contract"
    proofCeiling = "No provider authentication, free-model availability, hosted response, push, merge, or deployment proof."
}

function Save-RunContext {
    Write-JsonFile -Value $script:runContext -Path $runContextPath
}

function Save-ArtifactRegistry {
    $registry = [ordered]@{
        schemaVersion = 1
        runId = $runId
        workflowId = "opencode-free-defaults-repair"
        artifacts = @($script:artifacts)
    }
    Write-JsonFile -Value $registry -Path $registryPath
}

function Add-RunArtifact {
    param(
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet("planned", "created", "observed", "failed", "preserved")][string]$Status,
        [string]$MediaType = $null,
        [string]$Description = $null
    )

    [void]$script:artifacts.Add([ordered]@{
        role = $Role
        path = $Path
        status = $Status
        tracked = $false
        mediaType = $MediaType
        description = $Description
    })
    Save-ArtifactRegistry
}

Save-RunContext
Add-RunArtifact -Role "run-context" -Path $runContextPath -Status "created" -MediaType "application/json" -Description "Machine-readable execution context."
Add-RunArtifact -Role "artifact-registry" -Path $registryPath -Status "created" -MediaType "application/json" -Description "Per-run artifact ledger."

$worktreeCreated = $false
$workflowSucceeded = $false
$installed = $null

try {
    $worktreeExists = Test-Path -LiteralPath $WorktreePath -PathType Container
    if ($worktreeExists) {
        $registeredWorktrees = Invoke-BoundedNative -FilePath "git" -ArgumentList @("worktree", "list", "--porcelain") -WorkingDirectory $resolvedSource -TimeoutSeconds 30
        if ($registeredWorktrees.ExitCode -ne 0 -or -not $registeredWorktrees.Stdout.Contains("worktree $WorktreePath")) {
            throw "Existing WorktreePath is not a registered worktree for this repository: $WorktreePath"
        }
        $existingStatus = Invoke-BoundedNative -FilePath "git" -ArgumentList @("status", "--short") -WorkingDirectory $WorktreePath -TimeoutSeconds 30
        if ($existingStatus.ExitCode -ne 0) {
            throw (Get-NativeFailureMessage -Operation "Existing worktree inspection" -Result $existingStatus)
        }
        if ($existingStatus.Stdout) {
            throw "Existing repair worktree contains changes and was preserved: $WorktreePath"
        }
        $switch = Invoke-BoundedNative -FilePath "git" -ArgumentList @("switch", "--detach", $targetHead) -WorkingDirectory $WorktreePath -TimeoutSeconds 60
        if ($switch.ExitCode -ne 0) {
            throw (Get-NativeFailureMessage -Operation "Existing worktree update" -Result $switch)
        }
    }

    if (-not $worktreeExists) {
        $add = Invoke-BoundedNative -FilePath "git" -ArgumentList @("worktree", "add", "--detach", $WorktreePath, $targetHead) -WorkingDirectory $resolvedSource -TimeoutSeconds 120
        if ($add.ExitCode -ne 0) {
            throw (Get-NativeFailureMessage -Operation "Isolated worktree creation" -Result $add)
        }
        $worktreeCreated = $true
    }

    Add-RunArtifact -Role "repair-worktree" -Path $WorktreePath -Status "preserved" -Description "Detached worktree pinned to the validated remote commit."

    $manifestPath = Join-Path $WorktreePath "tooling\wsl\tmux-gnhf-workstation.example.json"
    $installerPath = Join-Path $WorktreePath "tooling\wsl\Set-OpenCodeFreeDefaults.ps1"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Manifest not found at validated head: $manifestPath"
    }
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw "Installer not found at validated head: $installerPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $distribution = [string]$manifest.distribution
    $script:runContext.distribution = $distribution
    Save-RunContext

    $installerArguments = @("-NoLogo", "-NoProfile", "-File", $installerPath, "-ManifestPath", $manifestPath)
    if ($PlanOnly) {
        $installerArguments += "-PlanOnly"
    }
    $installer = Invoke-BoundedNative -FilePath "pwsh" -ArgumentList $installerArguments -WorkingDirectory $WorktreePath -TimeoutSeconds 600
    [IO.File]::WriteAllText($installerOutputPath, $installer.Output + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Add-RunArtifact -Role "installer-output" -Path $installerOutputPath -Status $(if ($installer.ExitCode -eq 0) { "observed" } else { "failed" }) -MediaType "text/plain" -Description "Complete managed installer output."
    if ($installer.ExitCode -ne 0) {
        throw (Get-NativeFailureMessage -Operation "OpenCode free-default installer" -Result $installer)
    }

    if ($PlanOnly) {
        $script:runContext.status = "planned"
        $script:runContext.proofLevel = "local-plan"
    }

    if (-not $PlanOnly) {
        $inspectCommand = 'jq -e -c ''{model,small_model,share,whitelist:.provider.opencode.whitelist}'' "$HOME/.config/opencode/opencode.json"'
        $inspection = Invoke-BoundedNative -FilePath "wsl.exe" -ArgumentList @("-d", $distribution, "-e", "bash", "-lc", $inspectCommand) -WorkingDirectory $WorktreePath -TimeoutSeconds 30
        if ($inspection.ExitCode -ne 0 -or -not $inspection.Stdout) {
            throw (Get-NativeFailureMessage -Operation "Independent OpenCode configuration inspection" -Result $inspection)
        }
        $installed = $inspection.Stdout | ConvertFrom-Json
        $expectedModels = @($manifest.opencode.freeModelIds | ForEach-Object { [string]$_ })
        $actualModels = @($installed.whitelist | ForEach-Object { [string]$_ })
        if (
            $installed.model -ne [string]$manifest.opencode.defaultModel -or
            $installed.small_model -ne [string]$manifest.opencode.smallModel -or
            $installed.share -ne "disabled" -or
            (@(Compare-Object -ReferenceObject $expectedModels -DifferenceObject $actualModels).Count -ne 0)
        ) {
            throw "Independent configuration inspection does not match the reviewed manifest."
        }
        Write-JsonFile -Value $installed -Path $effectiveConfigPath
        Add-RunArtifact -Role "effective-config" -Path $effectiveConfigPath -Status "observed" -MediaType "application/json" -Description "Independently read effective OpenCode defaults and whitelist."
        $script:runContext.status = "succeeded"
        $script:runContext.proofLevel = "local-configuration"
    }

    $script:runContext.completedAt = (Get-Date).ToUniversalTime().ToString("o")
    Save-RunContext

    $summary = "OpenCode free-default repair completed in $($script:runContext.mode) mode at commit $targetHead."
    $modelLine = "- Effective model: not changed in plan-only mode"
    $smallModelLine = "- Effective small model: not changed in plan-only mode"
    $whitelistLine = "- Effective whitelist: not changed in plan-only mode"
    if ($null -ne $installed) {
        $modelLine = "- Effective model: $($installed.model)"
        $smallModelLine = "- Effective small model: $($installed.small_model)"
        $whitelistLine = "- Effective whitelist: $(@($installed.whitelist) -join ', ')"
    }

    $report = @"
# OpenCode Free-Defaults Repair Report

## Result

- Status: $($script:runContext.status)
- Mode: $($script:runContext.mode)
- Source repository: $resolvedSource
- Source checkout dirty before run: $sourceDirty
- Remote branch: $RemoteName/$RemoteBranch
- Validated commit: $targetHead
- Isolated worktree: $WorktreePath
- WSL distribution: $distribution
$modelLine
$smallModelLine
$whitelistLine

## Artifacts

- Run context: $runContextPath
- Artifact registry: $registryPath
- Installer output: $installerOutputPath
- Effective configuration: $(if (Test-Path -LiteralPath $effectiveConfigPath) { $effectiveConfigPath } else { 'not produced' })
- Final handoff: $handoffPath

## Safety and proof

The source checkout was inspected but not rewritten. The workflow used an isolated detached worktree, did not access provider credentials, did not select a paid default, and did not push, merge, deploy, or delete unrelated work.

Proof level: $($script:runContext.proofLevel)

Proof ceiling: $($script:runContext.proofCeiling)

## Next decision

Run the read-only status probe:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\wsl\Get-OpenCodeFreeDefaultsHarnessStatus.ps1
```
"@
    [IO.File]::WriteAllText($reportPath, $report.Trim() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Add-RunArtifact -Role "operator-report" -Path $reportPath -Status "created" -MediaType "text/markdown" -Description "English operator report."

    $handoff = [ordered]@{
        schemaVersion = 1
        runId = $runId
        workflowId = "opencode-free-defaults-repair"
        status = $script:runContext.status
        summary = $summary
        targetHead = $targetHead
        worktreePath = $WorktreePath
        artifacts = @($script:artifacts | ForEach-Object { [string]$_.path })
        proofLevel = $script:runContext.proofLevel
        proofCeiling = $script:runContext.proofCeiling
        blocker = $null
        nextAction = "pwsh -NoLogo -NoProfile -File .\tooling\wsl\Get-OpenCodeFreeDefaultsHarnessStatus.ps1"
    }
    Write-JsonFile -Value $handoff -Path $handoffPath
    Add-RunArtifact -Role "final-handoff" -Path $handoffPath -Status "created" -MediaType "application/json" -Description "Compressed machine-readable handoff."

    [void](New-Item -ItemType Directory -Path $stateRoot -Force)
    [IO.File]::WriteAllText($latestPath, $runRoot + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $workflowSucceeded = $true

    if ($RemoveWorktreeOnSuccess -and $worktreeCreated) {
        $remove = Invoke-BoundedNative -FilePath "git" -ArgumentList @("worktree", "remove", $WorktreePath) -WorkingDirectory $resolvedSource -TimeoutSeconds 120
        if ($remove.ExitCode -ne 0) {
            throw (Get-NativeFailureMessage -Operation "Owned worktree removal" -Result $remove)
        }
    }

    Write-Host ""
    Write-Host "[PASS] OpenCode free-default repair workflow completed." -ForegroundColor Green
    Write-Host "Run context: $runContextPath"
    Write-Host "Operator report: $reportPath"
    Write-Host "Final handoff: $handoffPath"
    Write-Host "Validated commit: $targetHead"

    [pscustomobject]@{
        status = $script:runContext.status
        runId = $runId
        targetHead = $targetHead
        worktreePath = $WorktreePath
        runContext = $runContextPath
        artifactRegistry = $registryPath
        operatorReport = $reportPath
        finalHandoff = $handoffPath
        proofLevel = $script:runContext.proofLevel
    }
}
catch {
    $message = $_.Exception.Message
    $script:runContext.status = "failed"
    $script:runContext.error = $message
    $script:runContext.completedAt = (Get-Date).ToUniversalTime().ToString("o")
    Save-RunContext

    $failureReport = @"
# OpenCode Free-Defaults Repair Report

## Result

- Status: failed
- Mode: $($script:runContext.mode)
- Source repository: $resolvedSource
- Remote branch: $RemoteName/$RemoteBranch
- Validated commit: $targetHead
- Preserved worktree: $WorktreePath

## Blocker

$message

## Evidence

- Run context: $runContextPath
- Artifact registry: $registryPath
- Installer output: $(if (Test-Path -LiteralPath $installerOutputPath) { $installerOutputPath } else { 'not produced' })

## Proof ceiling

$($script:runContext.proofCeiling)

## Next decision

Review the blocker and rerun the repository-owned one-click entrypoint after repairing the exact cause.
"@
    [IO.File]::WriteAllText($reportPath, $failureReport.Trim() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Add-RunArtifact -Role "operator-report" -Path $reportPath -Status "created" -MediaType "text/markdown" -Description "English blocker report."

    $handoff = [ordered]@{
        schemaVersion = 1
        runId = $runId
        workflowId = "opencode-free-defaults-repair"
        status = "failed"
        summary = "OpenCode free-default repair stopped at an evidence-backed blocker."
        targetHead = $targetHead
        worktreePath = $WorktreePath
        artifacts = @($script:artifacts | ForEach-Object { [string]$_.path })
        proofLevel = "contract"
        proofCeiling = $script:runContext.proofCeiling
        blocker = $message
        nextAction = ".\Repair-OpenCodeFreeDefaults.cmd"
    }
    Write-JsonFile -Value $handoff -Path $handoffPath
    Add-RunArtifact -Role "final-handoff" -Path $handoffPath -Status "created" -MediaType "application/json" -Description "Compressed blocker handoff."
    [void](New-Item -ItemType Directory -Path $stateRoot -Force)
    [IO.File]::WriteAllText($latestPath, $runRoot + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

    Write-Error "OpenCode free-default repair failed. Operator report: $reportPath"
    throw
}
