[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryRoot = (Get-Location).Path,

    [Parameter()]
    [string]$RemoteName = 'origin',

    [Parameter()]
    [string]$RemoteUrl = 'https://github.com/EndeavorEverlasting/AgentSwitchboard.git',

    [Parameter()]
    [string]$ExpectedRemoteCommit = '1c559d6930be3a28321021eea04bcd8f7e323ecb',

    [Parameter()]
    [string]$ExpectedLocalCommit = '6e91164',

    [Parameter()]
    [switch]$Fetch
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Invoke-GitProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = @(& git -C $RepositoryRoot @Arguments 2>&1)
    $exitCode = $LASTEXITCODE

    [pscustomobject]@{
        command   = 'git -C "{0}" {1}' -f $RepositoryRoot, ($Arguments -join ' ')
        exit_code = $exitCode
        output    = @($output | ForEach-Object { [string]$_ })
    }
}

function Test-GitCommit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Commit
    )

    $probe = Invoke-GitProbe -Arguments @('cat-file', '-e', ('{0}^{{commit}}' -f $Commit))
    return ($probe.exit_code -eq 0)
}

$rootProbe = Invoke-GitProbe -Arguments @('rev-parse', '--show-toplevel')
if ($rootProbe.exit_code -ne 0) {
    throw "RepositoryRoot is not a Git worktree: $RepositoryRoot"
}

if ($Fetch) {
    $remoteProbe = Invoke-GitProbe -Arguments @('remote', 'get-url', $RemoteName)
    if ($remoteProbe.exit_code -ne 0) {
        throw "Remote '$RemoteName' is missing. Add it explicitly before fetching: git remote add $RemoteName $RemoteUrl"
    }

    $fetchProbe = Invoke-GitProbe -Arguments @('fetch', '--prune', $RemoteName)
    if ($fetchProbe.exit_code -ne 0) {
        throw "Fetch failed for remote '$RemoteName': $($fetchProbe.output -join [Environment]::NewLine)"
    }
}

$statusProbe = Invoke-GitProbe -Arguments @('status', '--short')
$branchProbe = Invoke-GitProbe -Arguments @('branch', '--show-current')
$logProbe = Invoke-GitProbe -Arguments @('log', '--oneline', '--decorate', '--all', '-12')
$remoteProbe = Invoke-GitProbe -Arguments @('remote', '-v')
$worktreeProbe = Invoke-GitProbe -Arguments @('worktree', 'list', '--porcelain')

$localCommitPresent = Test-GitCommit -Commit $ExpectedLocalCommit
$remoteCommitPresent = Test-GitCommit -Commit $ExpectedRemoteCommit
$mergeBaseProbe = $null
$historiesRelated = $false

if ($localCommitPresent -and $remoteCommitPresent) {
    $mergeBaseProbe = Invoke-GitProbe -Arguments @('merge-base', $ExpectedLocalCommit, $ExpectedRemoteCommit)
    $historiesRelated = ($mergeBaseProbe.exit_code -eq 0)
}

$isDirty = ($statusProbe.output.Count -gt 0)
$decision = $null
$safeNextCommand = $null

if ($isDirty) {
    $decision = 'blocked-dirty-worktree'
    $safeNextCommand = 'git status --short'
}
elseif (-not $localCommitPresent) {
    $decision = 'blocked-local-seed-commit-missing'
    $safeNextCommand = 'git log --oneline --decorate --all -20'
}
elseif (-not $remoteCommitPresent) {
    $decision = 'blocked-remote-seed-commit-missing'
    $safeNextCommand = "git fetch --prune $RemoteName"
}
elseif ($historiesRelated) {
    $decision = 'related-histories'
    $safeNextCommand = "git merge-base $ExpectedLocalCommit $ExpectedRemoteCommit"
}
else {
    $decision = 'unrelated-histories-preserve-both'
    $safeNextCommand = "git branch preserve/local-bootstrap-seed $ExpectedLocalCommit"
}

$result = [ordered]@{
    schema_version = '1.0'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    repository_root = $rootProbe.output | Select-Object -First 1
    expected = [ordered]@{
        remote_url = $RemoteUrl
        remote_commit = $ExpectedRemoteCommit
        local_commit = $ExpectedLocalCommit
    }
    observed = [ordered]@{
        branch = $branchProbe.output | Select-Object -First 1
        dirty = $isDirty
        status = $statusProbe.output
        recent_history = $logProbe.output
        remotes = $remoteProbe.output
        worktrees = $worktreeProbe.output
        local_commit_present = $localCommitPresent
        remote_commit_present = $remoteCommitPresent
        histories_related = $historiesRelated
        merge_base = if ($mergeBaseProbe -and $mergeBaseProbe.exit_code -eq 0) {
            $mergeBaseProbe.output | Select-Object -First 1
        }
        else {
            $null
        }
    }
    decision = $decision
    safe_next_command = $safeNextCommand
    preservation_contract = [ordered]@{
        force_push = $false
        rewrite_remote_main = $false
        delete_either_root = $false
        preserve_local_seed_branch = 'preserve/local-bootstrap-seed'
        integration_base = 'origin/main'
    }
}

$result | ConvertTo-Json -Depth 8
