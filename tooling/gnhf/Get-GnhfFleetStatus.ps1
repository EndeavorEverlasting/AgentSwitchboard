[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = & git -C $RepoPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        throw "git -C '$RepoPath' $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Resolve-ManifestPath {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$BaseDirectory
    )

    if ([System.IO.Path]::IsPathRooted($Value)) {
        return (Resolve-Path -LiteralPath $Value).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $BaseDirectory $Value)).Path
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

$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
$manifestDirectory = Split-Path -Parent $ManifestPath
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

$repoPaths = @(
    $manifest.sprints |
        Where-Object { -not $_.PSObject.Properties["enabled"] -or [bool]$_.enabled } |
        ForEach-Object { Resolve-ManifestPath -Value ([string]$_.repoPath) -BaseDirectory $manifestDirectory } |
        Select-Object -Unique
)

$reportRows = [System.Collections.Generic.List[object]]::new()

foreach ($repoPath in $repoPaths) {
    $baseBranch = (Invoke-Git -RepoPath $repoPath -Arguments @("branch", "--show-current") | Select-Object -First 1).Trim()
    $worktreeLines = Invoke-Git -RepoPath $repoPath -Arguments @("worktree", "list", "--porcelain")
    $worktrees = Parse-WorktreeList -Lines $worktreeLines

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

        $status = Invoke-Git -RepoPath $path -Arguments @("status", "--short") -AllowFailure
        $commits = Invoke-Git -RepoPath $path -Arguments @("log", "--oneline", "--decorate", "--max-count=12") -AllowFailure
        $runRoot = Join-Path $path ".gnhf\runs"
        $latestRun = $null
        $notes = $null
        $debugLog = $null

        if (Test-Path -LiteralPath $runRoot) {
            $latestRun = Get-ChildItem -LiteralPath $runRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

            if ($latestRun) {
                $notesPath = Join-Path $latestRun.FullName "notes.md"
                $debugPath = Join-Path $latestRun.FullName "gnhf.log"
                if (Test-Path -LiteralPath $notesPath) {
                    $notes = $notesPath
                }
                if (Test-Path -LiteralPath $debugPath) {
                    $debugLog = $debugPath
                }
            }
        }

        [void]$reportRows.Add([pscustomobject]@{
            repoPath = $repoPath
            baseBranch = $baseBranch
            worktreePath = $path
            branch = $branch
            head = if ($worktree.PSObject.Properties["HEAD"]) { [string]$worktree.HEAD } else { $null }
            status = @($status)
            recentCommits = @($commits)
            latestRunDirectory = if ($latestRun) { $latestRun.FullName } else { $null }
            notesPath = $notes
            debugLogPath = $debugLog
        })
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$jsonPath = Join-Path $InstallRoot "reports\morning-review-$timestamp.json"
$mdPath = Join-Path $InstallRoot "reports\morning-review-$timestamp.md"

[pscustomobject]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    manifestPath = $ManifestPath
    worktrees = @($reportRows)
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM

$markdown = [System.Collections.Generic.List[string]]::new()
[void]$markdown.Add("# GNHF Morning Review")
[void]$markdown.Add("")
[void]$markdown.Add("Generated: $(Get-Date -Format o)")
[void]$markdown.Add("")

if ($reportRows.Count -eq 0) {
    [void]$markdown.Add("No GNHF worktrees were found for the repositories in the manifest.")
}
else {
    foreach ($row in $reportRows) {
        [void]$markdown.Add("## $($row.branch)")
        [void]$markdown.Add("")
        [void]$markdown.Add("- Repository: ``$($row.repoPath)``")
        [void]$markdown.Add("- Worktree: ``$($row.worktreePath)``")
        [void]$markdown.Add("- HEAD: ``$($row.head)``")
        [void]$markdown.Add("- Notes: $(if ($row.notesPath) { "``$($row.notesPath)``" } else { "not found" })")
        [void]$markdown.Add("- Debug log: $(if ($row.debugLogPath) { "``$($row.debugLogPath)``" } else { "not found" })")
        [void]$markdown.Add("")
        [void]$markdown.Add("### Git status")
        [void]$markdown.Add("")
        [void]$markdown.Add("```text")
        if ($row.status.Count -gt 0) {
            foreach ($line in $row.status) { [void]$markdown.Add([string]$line) }
        }
        else {
            [void]$markdown.Add("(clean)")
        }
        [void]$markdown.Add("```")
        [void]$markdown.Add("")
        [void]$markdown.Add("### Recent commits")
        [void]$markdown.Add("")
        [void]$markdown.Add("```text")
        foreach ($line in $row.recentCommits) { [void]$markdown.Add([string]$line) }
        [void]$markdown.Add("```")
        [void]$markdown.Add("")
    }
}

$markdown -join [Environment]::NewLine | Set-Content -LiteralPath $mdPath -Encoding utf8NoBOM

Write-Host "Morning review written:" -ForegroundColor Green
Write-Host "  $mdPath"
Write-Host "  $jsonPath"
Write-Host ""
$reportRows | Select-Object branch, worktreePath, head, notesPath | Format-Table -AutoSize
