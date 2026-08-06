[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRepository,
    [Parameter(Mandatory)][string]$WorktreeRoot,
    [Parameter(Mandatory)][string]$Branch,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedHead,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$BaseCommit,
    [ValidateRange(0, 2147483647)][int]$PullRequestNumber = 0,
    [string]$OutputRoot,
    [switch]$NoOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Candidate validation is a Windows operator workflow.'
}

$git = (Get-Command git.exe -ErrorAction Stop).Source
$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
$source = (Resolve-Path -LiteralPath $SourceRepository -ErrorAction Stop).Path
$worktree = [IO.Path]::GetFullPath($WorktreeRoot)
$shortHead = $ExpectedHead.Substring(0, 8).ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard\machine-profile-harness\candidate-$shortHead"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$null = New-Item -ItemType Directory -Path $OutputRoot -Force

$repositoryWebRoot = 'https://github.com/EndeavorEverlasting/AgentSwitchboard'
if ($PullRequestNumber -gt 0) {
    $reviewUrl = "$repositoryWebRoot/pull/$PullRequestNumber"
}
else {
    $escapedBranch = [Uri]::EscapeDataString($Branch)
    $reviewUrl = "$repositoryWebRoot/compare/main...$escapedBranch`?expand=1"
}
$nextActionOwner = 'operator/reviewer'
$nextActionDependency = "candidate validation success at $($ExpectedHead.ToLowerInvariant()); PR review or merge remains the next unproven gate"
$nextCommand = 'start "" "' + $reviewUrl + '"'

$script:ExitCode = 0
$summary = [ordered]@{
    schema = 'agentswitchboard.machine-profile-harness-candidate-validation.v1'
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    completedAt = $null
    status = 'running'
    sourceRepository = $source
    sourceDirty = $null
    worktreeRoot = $worktree
    branch = $Branch
    expectedHead = $ExpectedHead.ToLowerInvariant()
    baseCommit = $BaseCommit.ToLowerInvariant()
    pullRequestNumber = $PullRequestNumber
    reviewUrl = $reviewUrl
    fetchedHead = $null
    actualHead = $null
    checks = [ordered]@{}
    statusJson = $null
    statusMarkdown = $null
    nextActionOwner = $nextActionOwner
    nextActionDependency = $nextActionDependency
    nextCommand = $nextCommand
    error = $null
}
$candidateSummaryPath = Join-Path $OutputRoot 'machine-profile-harness-candidate-validation.json'

function Invoke-GitChecked {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $lines = @(& $git -C $Repository @Arguments 2>&1)
    $code = $LASTEXITCODE
    $text = ($lines | ForEach-Object { [string]$_ }) -join "`n"
    if ($code -ne 0 -and -not $AllowFailure) {
        $script:ExitCode = $code
        throw "git $($Arguments -join ' ') failed with exit code $code. $text"
    }
    [pscustomobject]@{ ExitCode = $code; Text = $text.Trim() }
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][scriptblock]$Command,
        [Parameter(Mandatory)][string]$Name
    )

    & $Command
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $script:ExitCode = $code
        throw "$Name failed with exit code $code."
    }
    $summary.checks[$Name] = 'passed'
}

try {
    $inside = Invoke-GitChecked -Repository $source -Arguments @('rev-parse', '--is-inside-work-tree')
    if ($inside.Text -ne 'true') { throw "Source is not a Git worktree: $source" }

    $origin = (Invoke-GitChecked -Repository $source -Arguments @('remote', 'get-url', 'origin')).Text
    $allowedOrigin = $origin -match '^https://github\.com/EndeavorEverlasting/AgentSwitchboard(?:\.git)?$' -or $origin -match '^git@github\.com:EndeavorEverlasting/AgentSwitchboard(?:\.git)?$'
    if (-not $allowedOrigin) { throw "Unexpected origin: $origin" }
    $summary.checks.origin = 'passed'

    $sourceStatus = (Invoke-GitChecked -Repository $source -Arguments @('status', '--short')).Text
    $summary.sourceDirty = -not [string]::IsNullOrWhiteSpace($sourceStatus)

    $null = Invoke-GitChecked -Repository $source -Arguments @('fetch', '--no-tags', 'origin', 'main')
    $null = Invoke-GitChecked -Repository $source -Arguments @('fetch', '--no-tags', 'origin', $Branch)
    $fetched = (Invoke-GitChecked -Repository $source -Arguments @('rev-parse', 'FETCH_HEAD')).Text.ToLowerInvariant()
    $summary.fetchedHead = $fetched
    if ($fetched -ne $ExpectedHead.ToLowerInvariant()) {
        throw "Fetched head mismatch. Expected $ExpectedHead, received $fetched."
    }
    $summary.checks.fetch = 'passed'

    $baseObject = Invoke-GitChecked -Repository $source -Arguments @('cat-file', '-e', "$BaseCommit`^{commit}") -AllowFailure
    if ($baseObject.ExitCode -ne 0) { throw "Base commit is unavailable: $BaseCommit" }
    $ancestry = Invoke-GitChecked -Repository $source -Arguments @('merge-base', '--is-ancestor', $BaseCommit, $ExpectedHead) -AllowFailure
    if ($ancestry.ExitCode -ne 0) { throw "$BaseCommit is not an ancestor of $ExpectedHead." }
    $summary.checks.ancestry = 'passed'

    if (Test-Path -LiteralPath $worktree) {
        $existing = Invoke-GitChecked -Repository $worktree -Arguments @('rev-parse', '--is-inside-work-tree') -AllowFailure
        if ($existing.ExitCode -ne 0 -or $existing.Text -ne 'true') {
            throw "Candidate path exists but is not a Git worktree: $worktree"
        }
    }
    else {
        $parent = Split-Path -Parent $worktree
        if ($parent) { $null = New-Item -ItemType Directory -Path $parent -Force }
        $null = Invoke-GitChecked -Repository $source -Arguments @('worktree', 'add', '--detach', $worktree, $ExpectedHead)
    }

    $actual = (Invoke-GitChecked -Repository $worktree -Arguments @('rev-parse', 'HEAD')).Text.ToLowerInvariant()
    $summary.actualHead = $actual
    if ($actual -ne $ExpectedHead.ToLowerInvariant()) {
        throw "Worktree head mismatch. Expected $ExpectedHead, received $actual."
    }
    $worktreeStatus = (Invoke-GitChecked -Repository $worktree -Arguments @('status', '--short')).Text
    if (-not [string]::IsNullOrWhiteSpace($worktreeStatus)) {
        throw "Candidate worktree is dirty: $worktreeStatus"
    }
    $summary.checks.worktree = 'passed'

    $manifestPath = Join-Path $worktree 'tooling\profiles\windows\harness\machine-profile\manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $artifactRegistryPath = Join-Path $worktree ([string]$manifest.artifactRegistry)
    $artifactRegistry = Get-Content -LiteralPath $artifactRegistryPath -Raw | ConvertFrom-Json

    Push-Location $worktree
    try {
        $validatorCommand = Join-Path $worktree ([string]$manifest.validatorCommand)
        Invoke-CheckedCommand -Name 'powershell-harness-validator' -Command { & $validatorCommand }

        $python = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($python) {
            $pythonExe = $python.Source
            $pythonPrefix = @()
        }
        else {
            $py = Get-Command py.exe -ErrorAction Stop
            $pythonExe = $py.Source
            $pythonPrefix = @('-3')
        }
        $pythonValidator = Join-Path $worktree ([string]$manifest.pythonValidator)
        Invoke-CheckedCommand -Name 'python-harness-validator' -Command { & $pythonExe @pythonPrefix $pythonValidator }
        Invoke-CheckedCommand -Name 'existing-machine-profile-python-contract' -Command { & $pythonExe @pythonPrefix -m unittest tests.test_machine_profile_bootstrap }

        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $existingPowerShellValidator = Join-Path $worktree 'scripts\Test-MachineProfileBootstrap.ps1'
        Invoke-CheckedCommand -Name 'existing-machine-profile-powershell-contract' -Command { & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $existingPowerShellValidator }

        $diff = Invoke-GitChecked -Repository $worktree -Arguments @('diff', '--check', "$BaseCommit..$ExpectedHead") -AllowFailure
        if ($diff.ExitCode -ne 0) {
            $script:ExitCode = $diff.ExitCode
            throw "git diff --check failed. $($diff.Text)"
        }
        $summary.checks.diffHygiene = 'passed'
    }
    finally {
        Pop-Location
    }

    $statusScript = Join-Path $worktree ([string]$manifest.statusReporter)
    Invoke-CheckedCommand -Name 'operator-status-report' -Command {
        & $pwsh -NoLogo -NoProfile -File $statusScript -RepoRoot $worktree -Emit Human -OutputRoot $OutputRoot -NextCommand $nextCommand -NextActionOwner $nextActionOwner -NextActionDependency $nextActionDependency
    }

    $jsonArtifact = @($artifactRegistry.generatedArtifacts | Where-Object id -eq 'harness-status-json')[0]
    $markdownArtifact = @($artifactRegistry.generatedArtifacts | Where-Object id -eq 'harness-status-markdown')[0]
    if (-not $jsonArtifact -or -not $markdownArtifact) { throw 'Status artifacts are missing from the artifact registry.' }
    $statusJson = Join-Path $OutputRoot ([IO.Path]::GetFileName(([string]$jsonArtifact.path).Replace('/', '\')))
    $statusMarkdown = Join-Path $OutputRoot ([IO.Path]::GetFileName(([string]$markdownArtifact.path).Replace('/', '\')))
    foreach ($artifactPath in @($statusJson, $statusMarkdown)) {
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { throw "Expected artifact was not produced: $artifactPath" }
    }
    $summary.statusJson = $statusJson
    $summary.statusMarkdown = $statusMarkdown
    $summary.checks.artifactResolution = 'passed'

    $statusResult = Get-Content -LiteralPath $statusJson -Raw | ConvertFrom-Json
    if ([string]$statusResult.nextCommand -ne $nextCommand) {
        throw 'Status report did not preserve the candidate review command.'
    }
    if ([string]$statusResult.nextActionOwner -ne $nextActionOwner) {
        throw 'Status report did not preserve the candidate next-action owner.'
    }
    $summary.checks.handoffCommand = 'passed'

    Get-Content -LiteralPath $statusMarkdown
    if (-not $NoOpen) {
        Start-Process -FilePath notepad.exe -ArgumentList @($statusMarkdown)
        $summary.checks.artifactOpen = 'passed'
    }
    else {
        $summary.checks.artifactOpen = 'skipped'
    }

    $summary.status = 'success'
}
catch {
    if ($script:ExitCode -eq 0) { $script:ExitCode = 1 }
    $summary.status = 'failed'
    $summary.error = $_.Exception.ToString()
    Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
    $summary.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $candidateSummaryPath -Encoding utf8NoBOM
    Write-Host "Candidate summary: $candidateSummaryPath"
}

if ($script:ExitCode -ne 0) { exit $script:ExitCode }
exit 0
