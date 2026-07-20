function Resolve-QueuePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BaseDirectory
    )
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ([IO.Path]::IsPathRooted($expanded)) {
        return [IO.Path]::GetFullPath($expanded)
    }
    return [IO.Path]::GetFullPath((Join-Path $BaseDirectory $expanded))
}

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

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )
    $output = @(& git -C $Repository @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed in '$Repository': $($output -join [Environment]::NewLine)"
    }
    [pscustomobject]@{
        ExitCode = $exitCode
        Lines = @($output | ForEach-Object { [string]$_ })
        Text = ($output -join [Environment]::NewLine)
    }
}

function ConvertTo-CanonicalGitHubRemote {
    param([Parameter(Mandatory)][string]$Remote)
    $trimmed = $Remote.Trim()
    if ($trimmed -match '^git@github\.com:(?<name>[^/]+/[^/]+?)(?:\.git)?$') {
        return "https://github.com/$($Matches.name)"
    }
    if ($trimmed -match '^https://github\.com/(?<name>[^/]+/[^/]+?)(?:\.git)?/?$') {
        return "https://github.com/$($Matches.name)"
    }
    throw "Only canonical GitHub remotes are supported by prompt queue planning: $Remote"
}

function Get-RepositoryName {
    param([Parameter(Mandatory)][string]$Remote)
    if ($Remote -notmatch '^https://github\.com/(?<name>[^/]+/[^/]+)$') {
        throw "Unable to derive repository name from remote: $Remote"
    }
    $Matches.name
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory)][string]$Child,
        [Parameter(Mandatory)][string]$Parent
    )
    $separator = [IO.Path]::DirectorySeparatorChar
    $normalizedParent = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/') + $separator
    $normalizedChild = [IO.Path]::GetFullPath($Child).TrimEnd('\', '/') + $separator
    $normalizedChild.StartsWith($normalizedParent, [StringComparison]::OrdinalIgnoreCase)
}

function Get-PullRequestIntelligence {
    param(
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][string]$Branch,
        [AllowNull()][Nullable[int]]$DeclaredNumber,
        [switch]$SkipDiscovery
    )

    if ($SkipDiscovery) {
        return [pscustomobject][ordered]@{
            status = if ($DeclaredNumber) { "declared-unverified" } else { "skipped" }
            number = if ($DeclaredNumber) { [int]$DeclaredNumber } else { $null }
            url = $null
            headBranch = $Branch
            baseBranch = $null
            draft = $null
            evidence = "Pull-request discovery was explicitly skipped."
        }
    }

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        if ($DeclaredNumber) {
            throw "Lane declares PR #$DeclaredNumber for '$RepositoryName', but gh is unavailable to verify it."
        }
        return [pscustomobject][ordered]@{
            status = "unavailable"
            number = $null
            url = $null
            headBranch = $Branch
            baseBranch = $null
            draft = $null
            evidence = "gh was not available."
        }
    }

    $raw = @(& $gh.Source pr list --repo $RepositoryName --state open --head $Branch --limit 20 --json number,url,headRefName,baseRefName,isDraft 2>&1)
    if ($LASTEXITCODE -ne 0) {
        if ($DeclaredNumber) {
            throw "Unable to verify declared PR #$DeclaredNumber for '$RepositoryName': $($raw -join [Environment]::NewLine)"
        }
        return [pscustomobject][ordered]@{
            status = "unavailable"
            number = $null
            url = $null
            headBranch = $Branch
            baseBranch = $null
            draft = $null
            evidence = ($raw -join [Environment]::NewLine)
        }
    }

    $matches = @((($raw -join [Environment]::NewLine) | ConvertFrom-Json -Depth 20))
    if ($matches.Count -gt 1) {
        throw "More than one open PR uses branch '$Branch' in '$RepositoryName'. Queue selection is ambiguous."
    }
    if ($matches.Count -eq 0) {
        if ($DeclaredNumber) {
            throw "Declared PR #$DeclaredNumber was not found as an open PR for branch '$Branch' in '$RepositoryName'."
        }
        return [pscustomobject][ordered]@{
            status = "none"
            number = $null
            url = $null
            headBranch = $Branch
            baseBranch = $null
            draft = $null
            evidence = "No open PR matched the current branch."
        }
    }

    $match = $matches[0]
    if ($DeclaredNumber -and [int]$match.number -ne [int]$DeclaredNumber) {
        throw "Declared PR #$DeclaredNumber does not match discovered PR #$($match.number) for '$RepositoryName'."
    }
    [pscustomobject][ordered]@{
        status = "matched"
        number = [int]$match.number
        url = [string]$match.url
        headBranch = [string]$match.headRefName
        baseBranch = [string]$match.baseRefName
        draft = [bool]$match.isDraft
        evidence = "Discovered with gh pr list."
    }
}

function Get-RepositoryIntelligence {
    param(
        [Parameter(Mandatory)]$Lane,
        [Parameter(Mandatory)][string]$RepositoryPath,
        [switch]$SkipValidation,
        [switch]$SkipPullRequests
    )

    if ($SkipValidation) {
        if ([string]::IsNullOrWhiteSpace([string]$Lane.repositoryRemote) -or
            [string]::IsNullOrWhiteSpace([string]$Lane.baseBranch)) {
            throw "Skipping repository validation requires repositoryRemote and baseBranch for lane '$($Lane.laneId)'."
        }
        $remote = ConvertTo-CanonicalGitHubRemote -Remote ([string]$Lane.repositoryRemote)
        $name = if ([string]::IsNullOrWhiteSpace([string]$Lane.repositoryName)) {
            Get-RepositoryName -Remote $remote
        }
        else {
            [string]$Lane.repositoryName
        }
        return [pscustomobject][ordered]@{
            name = $name
            remote = $remote
            path = $RepositoryPath
            branch = [string]$Lane.baseBranch
            head = "0000000000000000000000000000000000000000"
            clean = $true
            attached = $true
            worktreeCount = 0
            pullRequest = Get-PullRequestIntelligence -RepositoryName $name -Branch ([string]$Lane.baseBranch) -DeclaredNumber $Lane.pullRequestNumber -SkipDiscovery
            validation = "skipped"
        }
    }

    if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
        throw "Repository path not found for lane '$($Lane.laneId)': $RepositoryPath"
    }
    $inside = Invoke-Git -Repository $RepositoryPath -Arguments @("rev-parse", "--is-inside-work-tree")
    if (([string]($inside.Lines | Select-Object -First 1)).Trim() -ne "true") {
        throw "Lane '$($Lane.laneId)' does not target a Git worktree."
    }
    $status = Invoke-Git -Repository $RepositoryPath -Arguments @("status", "--porcelain=v1")
    $dirtyLines = @($status.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($dirtyLines.Count -gt 0) {
        throw "Repository for lane '$($Lane.laneId)' is dirty."
    }
    $branchResult = Invoke-Git -Repository $RepositoryPath -Arguments @("branch", "--show-current")
    $branch = ([string]($branchResult.Lines | Select-Object -First 1)).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw "Repository for lane '$($Lane.laneId)' is detached."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Lane.baseBranch) -and
        $branch -cne [string]$Lane.baseBranch) {
        throw "Lane '$($Lane.laneId)' expects base branch '$($Lane.baseBranch)' but repository is on '$branch'."
    }
    $headResult = Invoke-Git -Repository $RepositoryPath -Arguments @("rev-parse", "HEAD")
    $head = ([string]($headResult.Lines | Select-Object -First 1)).Trim()
    if ($head -notmatch '^[0-9a-f]{40}$') {
        throw "Repository for lane '$($Lane.laneId)' returned an invalid HEAD SHA."
    }
    $remoteResult = Invoke-Git -Repository $RepositoryPath -Arguments @("remote", "get-url", "origin")
    $remote = ConvertTo-CanonicalGitHubRemote -Remote ([string]($remoteResult.Lines | Select-Object -First 1))
    if (-not [string]::IsNullOrWhiteSpace([string]$Lane.repositoryRemote)) {
        $declaredRemote = ConvertTo-CanonicalGitHubRemote -Remote ([string]$Lane.repositoryRemote)
        if ($remote -cne $declaredRemote) {
            throw "Lane '$($Lane.laneId)' remote '$declaredRemote' does not match repository origin '$remote'."
        }
    }
    $name = Get-RepositoryName -Remote $remote
    if (-not [string]::IsNullOrWhiteSpace([string]$Lane.repositoryName) -and
        [string]$Lane.repositoryName -cne $name) {
        throw "Lane '$($Lane.laneId)' repositoryName '$($Lane.repositoryName)' does not match '$name'."
    }
    $worktreeResult = Invoke-Git -Repository $RepositoryPath -Arguments @("worktree", "list", "--porcelain")
    $worktreeCount = @($worktreeResult.Lines | Where-Object { $_ -match '^worktree\s+' }).Count
    [pscustomobject][ordered]@{
        name = $name
        remote = $remote
        path = $RepositoryPath
        branch = $branch
        head = $head
        clean = $true
        attached = $true
        worktreeCount = $worktreeCount
        pullRequest = Get-PullRequestIntelligence -RepositoryName $name -Branch $branch -DeclaredNumber $Lane.pullRequestNumber -SkipDiscovery:$SkipPullRequests
        validation = "observed"
    }
}
