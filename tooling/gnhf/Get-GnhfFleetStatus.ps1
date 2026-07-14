[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pathHelpersPath = Join-Path $PSScriptRoot "GnhfFleet.Paths.ps1"
if (-not (Test-Path -LiteralPath $pathHelpersPath -PathType Leaf)) {
    throw "Path helper library not found: $pathHelpersPath"
}
. $pathHelpersPath

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = & git -C $RepoPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "git -C '$RepoPath' $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
    }
}

function Parse-WorktreeList {
    param([string[]]$Lines)

    $records = [System.Collections.Generic.List[object]]::new()
    $current = [ordered]@{}

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($current.Count -gt 0) {
                [void]$records.Add([pscustomobject]$current)
                $current = [ordered]@{}
            }
            continue
        }

        $parts = $line -split " ", 2
        $key = $parts[0]
        $value = if ($parts.Count -gt 1) { $parts[1] } else { $true }
        $current[$key] = $value
    }

    if ($current.Count -gt 0) {
        [void]$records.Add([pscustomobject]$current)
    }

    return @($records)
}

function Add-UnavailableRepoRow {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Rows,
        [Parameter(Mandatory)][string]$ConfiguredPath,
        [Parameter(Mandatory)][string]$ResolvedPath,
        [Parameter(Mandatory)][string]$Reason
    )

    [void]$Rows.Add([pscustomobject]@{
        availability = "unavailable"
        repoPath = $ResolvedPath
        configuredRepoPath = $ConfiguredPath
        baseBranch = $null
        worktreePath = $null
        branch = $null
        head = $null
        status = @()
        recentCommits = @()
        latestRunDirectory = $null
        notesPath = $null
        debugLogPath = $null
        error = $Reason
    })
}

$ManifestPath = Resolve-GnhfFleetFile -Path $ManifestPath -Description "fleet manifest"
$manifestDirectory = Split-Path -Parent $ManifestPath
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$InstallRoot = Get-GnhfFleetAbsolutePath -Path $InstallRoot
$reportsRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "reports")

$configuredRepoPaths = @(
    $manifest.sprints |
        Where-Object { -not $_.PSObject.Properties["enabled"] -or [bool]$_.enabled } |
        ForEach-Object { [string]$_.repoPath } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
)

$reportRows = [System.Collections.Generic.List[object]]::new()
foreach ($configuredRepoPath in $configuredRepoPaths) {
    $candidatePath = Get-GnhfFleetAbsolutePath -Path $configuredRepoPath -BaseDirectory $manifestDirectory
    try {
        $repoPath = Resolve-GnhfFleetDirectory -Path $candidatePath -Description "configured repository"
    }
    catch {
        Add-UnavailableRepoRow -Rows $reportRows -ConfiguredPath $configuredRepoPath -ResolvedPath $candidatePath -Reason $_.Exception.Message
        continue
    }

    try {
        $baseBranchResult = Invoke-Git -RepoPath $repoPath -Arguments @("branch", "--show-current")
        $baseBranch = ($baseBranchResult.Output | Select-Object -First 1).Trim()
        $worktreeResult = Invoke-Git -RepoPath $repoPath -Arguments @("worktree", "list", "--porcelain")
        $worktrees = Parse-WorktreeList -Lines $worktreeResult.Output
    }
    catch {
        Add-UnavailableRepoRow -Rows $reportRows -ConfiguredPath $configuredRepoPath -ResolvedPath $repoPath -Reason $_.Exception.Message
        continue
    }

    $matchingWorktreeCount = 0
    foreach ($worktree in $worktrees) {
        if (-not $worktree.PSObject.Properties["worktree"]) {
            continue
        }

        $path = [string]$worktree.worktree
        $branchRef = if ($worktree.PSObject.Properties["branch"]) { [string]$worktree.branch } else { "" }
        $branch = $branchRef -replace "^refs/heads/", ""
        $isGnhf = $branch.StartsWith("gnhf/") -or $path -match "gnhf-worktrees"
        if (-not $isGnhf) {
            continue
        }
        $matchingWorktreeCount++

        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            [void]$reportRows.Add([pscustomobject]@{
                availability = "worktree-missing"
                repoPath = $repoPath
                configuredRepoPath = $configuredRepoPath
                baseBranch = $baseBranch
                worktreePath = $path
                branch = $branch
                head = if ($worktree.PSObject.Properties["HEAD"]) { [string]$worktree.HEAD } else { $null }
                status = @()
                recentCommits = @()
                latestRunDirectory = $null
                notesPath = $null
                debugLogPath = $null
                error = "Git lists this worktree, but its directory is missing. Run 'git worktree prune' after confirming no work must be recovered."
            })
            continue
        }

        $statusResult = Invoke-Git -RepoPath $path -Arguments @("status", "--short") -AllowFailure
        $commitsResult = Invoke-Git -RepoPath $path -Arguments @("log", "--oneline", "--decorate", "--max-count=12") -AllowFailure
        $runRoot = Join-Path $path ".gnhf\runs"
        $latestRun = $null
        $notes = $null
        $debugLog = $null

        if (Test-Path -LiteralPath $runRoot -PathType Container) {
            $latestRun = Get-ChildItem -LiteralPath $runRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

            if ($latestRun) {
                $notesPath = Join-Path $latestRun.FullName "notes.md"
                $debugPath = Join-Path $latestRun.FullName "gnhf.log"
                if (Test-Path -LiteralPath $notesPath -PathType Leaf) {
                    $notes = $notesPath
                }
                if (Test-Path -LiteralPath $debugPath -PathType Leaf) {
                    $debugLog = $debugPath
                }
            }
        }

        $gitErrors = [System.Collections.Generic.List[string]]::new()
        if ($statusResult.ExitCode -ne 0) {
            [void]$gitErrors.Add("git status failed: $($statusResult.Output -join ' ')")
        }
        if ($commitsResult.ExitCode -ne 0) {
            [void]$gitErrors.Add("git log failed: $($commitsResult.Output -join ' ')")
        }

        [void]$reportRows.Add([pscustomobject]@{
            availability = if ($gitErrors.Count -eq 0) { "available" } else { "partial" }
            repoPath = $repoPath
            configuredRepoPath = $configuredRepoPath
            baseBranch = $baseBranch
            worktreePath = $path
            branch = $branch
            head = if ($worktree.PSObject.Properties["HEAD"]) { [string]$worktree.HEAD } else { $null }
            status = @($statusResult.Output)
            recentCommits = @($commitsResult.Output)
            latestRunDirectory = if ($latestRun) { $latestRun.FullName } else { $null }
            notesPath = $notes
            debugLogPath = $debugLog
            error = if ($gitErrors.Count -gt 0) { $gitErrors -join "; " } else { $null }
        })
    }

    if ($matchingWorktreeCount -eq 0) {
        [void]$reportRows.Add([pscustomobject]@{
            availability = "available"
            repoPath = $repoPath
            configuredRepoPath = $configuredRepoPath
            baseBranch = $baseBranch
            worktreePath = $null
            branch = $null
            head = $null
            status = @()
            recentCommits = @()
            latestRunDirectory = $null
            notesPath = $null
            debugLogPath = $null
            error = "No GNHF worktrees found for this repository."
        })
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$jsonPath = Join-Path $reportsRoot "morning-review-$timestamp.json"
$mdPath = Join-Path $reportsRoot "morning-review-$timestamp.md"

[pscustomobject]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    manifestPath = $ManifestPath
    repositoriesConfigured = $configuredRepoPaths.Count
    worktrees = @($reportRows)
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM

$markdown = [System.Collections.Generic.List[string]]::new()
[void]$markdown.Add("# GNHF Morning Review")
[void]$markdown.Add("")
[void]$markdown.Add("Generated: $(Get-Date -Format o)")
[void]$markdown.Add("")

if ($reportRows.Count -eq 0) {
    [void]$markdown.Add("No enabled repository paths were found in the manifest.")
}
else {
    foreach ($row in $reportRows) {
        $heading = if ($row.branch) { $row.branch } else { $row.configuredRepoPath }
        [void]$markdown.Add("## $heading")
        [void]$markdown.Add("")
        [void]$markdown.Add("- Availability: **$($row.availability)**")
        [void]$markdown.Add("- Repository: " + '`' + $row.repoPath + '`')
        if ($row.worktreePath) { [void]$markdown.Add("- Worktree: " + '`' + $row.worktreePath + '`') }
        if ($row.head) { [void]$markdown.Add("- HEAD: " + '`' + $row.head + '`') }
        [void]$markdown.Add("- Notes: $(if ($row.notesPath) { '`' + $row.notesPath + '`' } else { 'not found' })")
        [void]$markdown.Add("- Debug log: $(if ($row.debugLogPath) { '`' + $row.debugLogPath + '`' } else { 'not found' })")
        if ($row.error) { [void]$markdown.Add("- Evidence: $($row.error)") }
        [void]$markdown.Add("")

        if ($row.worktreePath) {
            [void]$markdown.Add("### Git status")
            [void]$markdown.Add("")
            [void]$markdown.Add('```text')
            if ($row.status.Count -gt 0) {
                foreach ($line in $row.status) { [void]$markdown.Add([string]$line) }
            }
            else {
                [void]$markdown.Add("(clean or unavailable)")
            }
            [void]$markdown.Add('```')
            [void]$markdown.Add("")
            [void]$markdown.Add("### Recent commits")
            [void]$markdown.Add("")
            [void]$markdown.Add('```text')
            foreach ($line in $row.recentCommits) { [void]$markdown.Add([string]$line) }
            [void]$markdown.Add('```')
            [void]$markdown.Add("")
        }
    }
}

$markdown -join [Environment]::NewLine | Set-Content -LiteralPath $mdPath -Encoding utf8NoBOM

Write-Host "Morning review written:" -ForegroundColor Green
Write-Host "  $mdPath"
Write-Host "  $jsonPath"
Write-Host ""
$reportRows | Select-Object availability, branch, worktreePath, repoPath, error | Format-Table -AutoSize
