[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [string]$WslExe = "wsl.exe",
    [string]$SetupLogRoot = "$env:LOCALAPPDATA\AgentSwitchboard\wsl-setup",
    [switch]$PlanOnly,
    [switch]$ForceRebootAck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "This installer requires PowerShell 7. Run it from pwsh."
}

$repositoryContractModule = Join-Path $PSScriptRoot "WslRepositoryContracts.psm1"
if (-not (Test-Path -LiteralPath $repositoryContractModule -PathType Leaf)) {
    throw "Repository contract module not found: $repositoryContractModule"
}
Import-Module -Name $repositoryContractModule -Force

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function Invoke-SafeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$Description = "",
        [int]$TimeoutSeconds = 60
    )

    Write-Host "+ $FilePath $($ArgumentList -join ' ')" -ForegroundColor DarkGray

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.FileName = $FilePath
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $process.StandardInput.Close()

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill($true); $process.WaitForExit() } catch {}
        throw "Command timed out after ${TimeoutSeconds}s: $FilePath $($ArgumentList -join ' ')"
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
        Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
}

function Invoke-WslDistroCommand {
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$ShellCommand,
        [string[]]$ShellArgumentList = @(),
        [int]$TimeoutSeconds = 60
    )

    $wslArguments = @("-d", $Distribution, "-e", "bash", "-c", $ShellCommand)
    if ($ShellArgumentList.Count -gt 0) {
        $wslArguments += "_"
        $wslArguments += $ShellArgumentList
    }

    return Invoke-SafeCommand -FilePath $WslExe -ArgumentList $wslArguments -TimeoutSeconds $TimeoutSeconds
}

function Backup-ManagedFile {
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$LinuxPath,
        [Parameter(Mandatory)][string]$BackupSuffix
    )

    $checkProbe = Invoke-WslDistroCommand -Distribution $Distribution -ShellCommand "test -f `"$LinuxPath`" && echo EXISTS || echo MISSING"
    if ($checkProbe.Output -match "EXISTS") {
        $backupPath = "${LinuxPath}${BackupSuffix}"
        $copyResult = Invoke-WslDistroCommand -Distribution $Distribution -ShellCommand "cp `"$LinuxPath`" `"$backupPath`" 2>/dev/null && echo BACKED_UP || echo BACKUP_FAILED"
        if ($copyResult.Output -match "BACKED_UP") {
            Write-Host "  Backed up: $LinuxPath -> $backupPath" -ForegroundColor Yellow
            return $true
        }
        else {
            Write-Host "  Warning: could not back up $LinuxPath" -ForegroundColor Yellow
            return $false
        }
    }
    return $false
}

function Convert-WindowsPathToWsl {
    param([Parameter(Mandatory)][string]$WindowsPath)

    $resolved = (Resolve-Path -LiteralPath $WindowsPath).Path
    $drive = $resolved.Substring(0, 1).ToLower()
    $rest = $resolved.Substring(3) -replace "\\", "/"
    return "/mnt/$drive/$rest"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) {
    throw "Unsupported manifest schemaVersion: $($manifest.schemaVersion). Expected 1."
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$logDir = Join-Path $SetupLogRoot $timestamp
if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $logDir -Force)
}

$transcriptPath = Join-Path $logDir "setup-transcript.txt"
$summaryPath = Join-Path $logDir "setup-summary.json"
$resultsPath = Join-Path $logDir "command-results.json"
$repoResultsPath = Join-Path $logDir "repo-results.json"

Start-Transcript -Path $transcriptPath -Force | Out-Null

$planMode = $PlanOnly -or $WhatIfPreference
if ($planMode) {
    Write-Host "PLAN MODE: No changes will be applied." -ForegroundColor Yellow
}

Write-Section "WSL Agent Workstation Bootstrap"
Write-Host "Manifest: $ManifestPath"
Write-Host "Distribution: $($manifest.distribution.name)"
Write-Host "Plan mode: $planMode"

$commandResults = [System.Collections.Generic.List[object]]::new()
$repoResults = [System.Collections.Generic.List[object]]::new()
$rebootRequired = $false
$installedAgents = @()

Write-Section "WSL Feature Status"

$wslCommand = Get-Command $WslExe -ErrorAction SilentlyContinue
if (-not $wslCommand) {
    if ($planMode) {
        Write-Host "[PLAN] Would attempt to enable WSL feature via: dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart" -ForegroundColor Yellow
        $commandResults.Add([pscustomobject]@{
            step = "enable-wsl-feature"
            status = "planned"
            evidence = "WSL not available. In apply mode, would attempt feature enablement requiring elevation."
            rebootRequired = $true
        })
        $rebootRequired = $true
    }
    else {
        Write-Host "WSL is not available. Attempting to enable..." -ForegroundColor Yellow
        try {
            $enableResult = Invoke-SafeCommand -FilePath "dism.exe" -ArgumentList @("/online", "/enable-feature", "/featurename:Microsoft-Windows-Subsystem-Linux", "/all", "/norestart") -TimeoutSeconds 120
            $commandResults.Add([pscustomobject]@{
                step = "enable-wsl-feature"
                status = "applied"
                evidence = $enableResult.Output
                rebootRequired = $true
            })
            $rebootRequired = $true
            Write-Host "WSL feature enabled. Reboot required." -ForegroundColor Yellow
        }
        catch {
            $commandResults.Add([pscustomobject]@{
                step = "enable-wsl-feature"
                status = "failed"
                evidence = $_.Exception.Message
            })
            throw "Failed to enable WSL feature: $($_.Exception.Message)"
        }
    }
}
else {
    $commandResults.Add([pscustomobject]@{
        step = "wsl-feature-check"
        status = "already-installed"
        evidence = "wsl.exe found at $($wslCommand.Source)"
    })
    Write-Host "WSL is available." -ForegroundColor Green
}

Write-Section "Distribution Check"

$listOutput = if ($wslCommand) { & $WslExe --list --verbose 2>&1 } else { @() }
$distributionNames = @($listOutput | ForEach-Object {
    $line = [string]$_
    if ($line -match "^\s*\*?\s*(\S+)\s+") { $matches[1] }
} | Where-Object { $_ -ne "NAME" -and $_ -ne "---" })

$targetDist = $manifest.distribution.name
$distExists = $distributionNames -contains $targetDist

if (-not $distExists) {
    if ($planMode) {
        Write-Host "[PLAN] Would install distribution: $targetDist" -ForegroundColor Yellow
        $commandResults.Add([pscustomobject]@{
            step = "install-distribution"
            status = "planned"
            evidence = "Distribution '$targetDist' not found. Would run: wsl --install -d $targetDist"
            rebootRequired = $true
        })
        $rebootRequired = $true
    }
    elseif ($wslCommand) {
        Write-Host "Distribution '$targetDist' not found. Installing..." -ForegroundColor Yellow
        try {
            $installResult = Invoke-SafeCommand -FilePath $WslExe -ArgumentList @("--install", "-d", $targetDist) -TimeoutSeconds 300
            $commandResults.Add([pscustomobject]@{
                step = "install-distribution"
                status = "applied"
                evidence = $installResult.Output
                rebootRequired = $true
            })
            $rebootRequired = $true
            Write-Host "Distribution installed. Reboot may be required." -ForegroundColor Yellow
        }
        catch {
            $commandResults.Add([pscustomobject]@{
                step = "install-distribution"
                status = "failed"
                evidence = $_.Exception.Message
            })
            throw "Failed to install WSL feature: $($_.Exception.Message)"
        }
    } else {
        $commandResults.Add([pscustomobject]@{
            step = "install-distribution"
            status = "deferred-until-reboot"
            evidence = "wsl.exe is not available until the WSL feature reboot checkpoint completes."
            rebootRequired = $true
        })
    }
}
else {
    $commandResults.Add([pscustomobject]@{
        step = "distribution-check"
        status = "already-installed"
        evidence = "Distribution '$targetDist' found."
    })
    Write-Host "Distribution '$targetDist' is installed." -ForegroundColor Green
}

if ($rebootRequired -and -not $ForceRebootAck) {
    Write-Section "Reboot Required"
    Write-Host "The system requires a reboot before bootstrap can continue." -ForegroundColor Yellow
    Write-Host "After reboot, re-run this script to complete setup." -ForegroundColor Yellow
    Write-Host "To acknowledge reboot and continue planning only, use -ForceRebootAck." -ForegroundColor DarkGray

    Stop-Transcript | Out-Null

    $summary = [ordered]@{
        schemaVersion = 1
        completedAt = (Get-Date).ToString("o")
        status = "reboot-required"
        manifestPath = $ManifestPath
        distribution = $targetDist
        rebootRequired = $true
        commandResults = $commandResults
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    $commandResults | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultsPath -Encoding utf8NoBOM

    Write-Host "Setup summary: $summaryPath" -ForegroundColor Cyan
    return $summary
}

Write-Section "Linux Bootstrap"

$bootstrapScript = Join-Path $PSScriptRoot "scripts" | Join-Path -ChildPath "bootstrap-agent-workstation.sh"
if (-not (Test-Path -LiteralPath $bootstrapScript -PathType Leaf)) {
    throw "Bootstrap script not found: $bootstrapScript"
}

$configJson = $manifest | ConvertTo-Json -Depth 10
$configEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($configJson))

if ($planMode) {
    Write-Host "[PLAN] Would copy bootstrap script to WSL and execute it." -ForegroundColor Yellow
    Write-Host "[PLAN] Manifest configuration would be passed via base64-encoded stdin." -ForegroundColor Yellow
    $commandResults.Add([pscustomobject]@{
        step = "linux-bootstrap"
        status = "planned"
        evidence = "Would copy bootstrap-agent-workstation.sh and execute in WSL."
    })
}
else {
    Write-Host "Copying bootstrap script to WSL..." -ForegroundColor Yellow

    $tempScript = Join-Path $env:TEMP "agent-switchboard-bootstrap-$($timestamp).sh"
    Copy-Item -LiteralPath $bootstrapScript -Destination $tempScript -Force

    $wslTempPath = "/tmp/agent-switchboard-bootstrap.sh"
    $wslTempScriptPath = Convert-WindowsPathToWsl -WindowsPath $tempScript
    & $WslExe -d $targetDist -e bash -c "cp '$wslTempScriptPath' '$wslTempPath' && chmod +x '$wslTempPath'"

    Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue

    $bootstrapConfig = "echo '$configEncoded' | base64 -d | bash $wslTempPath"
    $bootstrapResult = Invoke-WslDistroCommand -Distribution $targetDist -ShellCommand $bootstrapConfig -TimeoutSeconds 600

    $commandResults.Add([pscustomobject]@{
        step = "linux-bootstrap"
        status = if ($bootstrapResult.ExitCode -eq 0) { "applied" } else { "failed" }
        evidence = $bootstrapResult.Output
        exitCode = $bootstrapResult.ExitCode
    })

    if ($bootstrapResult.ExitCode -ne 0) {
        Write-Host "Bootstrap script failed with exit code $($bootstrapResult.ExitCode)." -ForegroundColor Red
    }
    else {
        Write-Host "Linux bootstrap completed." -ForegroundColor Green
    }

    & $WslExe -d $targetDist -e bash -c "rm -f $wslTempPath"
}

Write-Section "Repository Cloning"

$repositoryProbeScript = @'
set -euo pipefail
relative_destination=$1
destination=$HOME
if [[ -n "$relative_destination" ]]; then
    destination="$HOME/$relative_destination"
fi
if [[ -d "$destination/.git" ]]; then
    git -C "$destination" remote get-url origin 2>/dev/null || printf 'NO_REMOTE\n'
else
    printf 'MISSING\n'
fi
'@

$repositoryCloneScript = @'
set -euo pipefail
relative_destination=$1
repository_url=$2
repository_branch=$3
destination=$HOME
if [[ -n "$relative_destination" ]]; then
    destination="$HOME/$relative_destination"
fi
mkdir -p -- "$(dirname -- "$destination")"
git clone --branch "$repository_branch" -- "$repository_url" "$destination"
'@

if ($manifest.repositories) {
    foreach ($repo in $manifest.repositories) {
        if (-not $repo.enabled) {
            Write-Host "Skipping disabled repository: $($repo.name)" -ForegroundColor DarkGray
            continue
        }

        $destPath = [string]$repo.destination
        try {
            $relativeDestination = ConvertTo-WslHomeRelativePath -Path $destPath
            $repoUrl = Assert-GitHubRepositoryUrl -Url ([string]$repo.url)
            $branchCandidate = [string]$repo.branch
            if ([string]::IsNullOrWhiteSpace($branchCandidate)) {
                $branchCandidate = "main"
            }
            $repoBranch = Assert-GitBranchName -Branch $branchCandidate
        }
        catch {
            Write-Host "Repository '$($repo.name)' has an invalid manifest contract: $($_.Exception.Message)" -ForegroundColor Red
            $repoResults.Add([pscustomobject]@{
                name = $repo.name
                destination = $destPath
                status = "invalid-manifest"
                evidence = $_.Exception.Message
            })
            continue
        }

        $probeResult = Invoke-WslDistroCommand `
            -Distribution $targetDist `
            -ShellCommand $repositoryProbeScript `
            -ShellArgumentList @($relativeDestination) `
            -TimeoutSeconds 15
        if ($probeResult.ExitCode -ne 0) {
            Write-Host "Repository '$($repo.name)' probe failed." -ForegroundColor Red
            $repoResults.Add([pscustomobject]@{
                name = $repo.name
                destination = $destPath
                status = "probe-failed"
                evidence = "Repository probe failed inside the selected WSL distribution."
            })
            continue
        }

        $currentRemote = $probeResult.Output.Trim()
        if ($currentRemote -ne "MISSING") {
            if ($currentRemote -eq $repoUrl) {
                Write-Host "Repository '$($repo.name)' already exists with correct remote." -ForegroundColor Green
                $repoResults.Add([pscustomobject]@{
                    name = $repo.name
                    destination = $destPath
                    status = "already-exists-correct-remote"
                    remote = $currentRemote
                })
            }
            else {
                Write-Host "Repository '$($repo.name)' exists but with wrong remote: $currentRemote (expected $repoUrl)" -ForegroundColor Yellow
                $repoResults.Add([pscustomobject]@{
                    name = $repo.name
                    destination = $destPath
                    status = "wrong-remote"
                    remote = $currentRemote
                    expectedRemote = $repoUrl
                })
            }
            continue
        }

        if ($planMode) {
            Write-Host "[PLAN] Would clone $($repo.name) from $repoUrl to $destPath" -ForegroundColor Yellow
            $repoResults.Add([pscustomobject]@{
                name = $repo.name
                destination = $destPath
                status = "planned"
            })
            continue
        }

        Write-Host "Cloning $($repo.name)..." -ForegroundColor Yellow
        $cloneResult = Invoke-WslDistroCommand `
            -Distribution $targetDist `
            -ShellCommand $repositoryCloneScript `
            -ShellArgumentList @($relativeDestination, $repoUrl, $repoBranch) `
            -TimeoutSeconds 120

        $repoResults.Add([pscustomobject]@{
            name = $repo.name
            destination = $destPath
            status = if ($cloneResult.ExitCode -eq 0) { "cloned" } else { "clone-failed" }
            remote = $repoUrl
            evidence = $cloneResult.Output
        })

        if ($cloneResult.ExitCode -eq 0) {
            Write-Host "Cloned $($repo.name) to $destPath" -ForegroundColor Green
        }
        else {
            Write-Host "Failed to clone $($repo.name): $($cloneResult.Output)" -ForegroundColor Red
        }
    }
}

Write-Section "Configuration Templates"

if ($manifest.tmux -and $manifest.tmux.enabled -and -not $planMode) {
    $tmuxTemplate = Join-Path $PSScriptRoot "templates" | Join-Path -ChildPath "tmux.conf"
    if (Test-Path -LiteralPath $tmuxTemplate -PathType Leaf) {
        $tmuxDestination = if ($manifest.tmux.configDestination.StartsWith('~/')) { '$HOME/' + $manifest.tmux.configDestination.Substring(2) } else { $manifest.tmux.configDestination }
        $backupPolicy = $manifest.dotfilePolicy
        if ($backupPolicy -and $backupPolicy.backupExisting) {
            [void](Backup-ManagedFile -Distribution $targetDist -LinuxPath $tmuxDestination -BackupSuffix $backupPolicy.backupSuffix)
        }

        $tmuxTempDest = "/tmp/agent-switchboard-tmux.conf"
        $tempTmux = Join-Path $env:TEMP "agent-switchboard-tmux-$($timestamp).conf"
        Copy-Item -LiteralPath $tmuxTemplate -Destination $tempTmux -Force
        $wslTempTmuxPath = Convert-WindowsPathToWsl -WindowsPath $tempTmux
        & $WslExe -d $targetDist -e bash -c "cp '$wslTempTmuxPath' '$tmuxTempDest' && cp '$tmuxTempDest' `"$tmuxDestination`" && rm -f '$tmuxTempDest'"
        Remove-Item -LiteralPath $tempTmux -Force -ErrorAction SilentlyContinue
        Write-Host "tmux configuration installed: $($manifest.tmux.configDestination)" -ForegroundColor Green
    }
}

if ($planMode -and $manifest.tmux -and $manifest.tmux.enabled) {
    Write-Host "[PLAN] Would install tmux template to $($manifest.tmux.configDestination)" -ForegroundColor Yellow
}

Stop-Transcript | Out-Null

$repositoryFailureStatuses = @("clone-failed", "invalid-manifest", "probe-failed", "wrong-remote")
$hasRepositoryFailure = @(
    $repoResults | Where-Object { $_.status -in $repositoryFailureStatuses }
).Count -gt 0

$finalStatus = if (($commandResults | Where-Object { $_.status -eq "failed" }) -or $hasRepositoryFailure) { "completed-with-errors" }
    elseif (($commandResults | Where-Object { $_.status -eq "planned" }) -or ($repoResults | Where-Object { $_.status -eq "planned" })) { "plan-only" }
    else { "completed" }

$summary = [ordered]@{
    schemaVersion = 1
    completedAt = (Get-Date).ToString("o")
    status = $finalStatus
    manifestPath = $ManifestPath
    distribution = $targetDist
    rebootRequired = $rebootRequired
    planMode = $planMode
    commandResults = @($commandResults)
    repoResults = @($repoResults)
    transcriptPath = $transcriptPath
}

$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
$commandResults | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultsPath -Encoding utf8NoBOM
$repoResults | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $repoResultsPath -Encoding utf8NoBOM

Write-Section "Setup Complete"
Write-Host "Status: $finalStatus" -ForegroundColor $(if ($finalStatus -eq "completed") { "Green" } else { "Yellow" })
Write-Host "Summary: $summaryPath"
Write-Host "Transcript: $transcriptPath"
Write-Host "Command results: $resultsPath"
Write-Host "Repository results: $repoResultsPath"

return $summary
