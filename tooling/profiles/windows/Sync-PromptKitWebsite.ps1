[CmdletBinding()]
param(
    [ValidateSet('Poll', 'Status')]
    [string]$Mode = 'Poll',

    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\prompt-kit-sync'),

    [ValidateRange(30, 900)]
    [int]$CommandTimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryUrl = 'https://github.com/EndeavorEverlasting/web-excel-repair-triage.git'
$ExpectedWebsiteRelativePath = 'web\prompt-kit\index.html'
$GeneratorRelativePath = 'scripts\build_prompt_kit_registry.py'
$GeneratorManifestRelativePath = 'configs\prompt_kit\generators.v1.json'
$ConfigPath = Join-Path $StateRoot 'config.json'
$StatePath = Join-Path $StateRoot 'state.json'
$LastRunPath = Join-Path $StateRoot 'last-run.json'
$SourcePath = Join-Path $StateRoot 'source\web-excel-repair-triage'
$ReleaseRoot = Join-Path $StateRoot 'website\releases'
$LockPath = Join-Path $StateRoot 'sync.lock'

function Normalize-RepositoryUrl {
    param([Parameter(Mandatory)][string]$Url)
    return (($Url.Trim() -replace '\.git$', '') -replace '\\', '/').ToLowerInvariant()
}

function Get-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return [pscustomobject]@{
            schema = 'agentswitchboard.prompt-kit-sync.config.v1'
            enabled = $false
            intervalMinutes = 60
            retentionCount = 2
        }
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($config.schema -ne 'agentswitchboard.prompt-kit-sync.config.v1') {
        throw "Unsupported Prompt Kit sync config schema in $ConfigPath"
    }
    return $config
}

function Read-State {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        return $null
    }
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.schema -ne 'agentswitchboard.prompt-kit-sync.state.v1') {
        throw "Unsupported Prompt Kit sync state schema in $StatePath"
    }
    return $state
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    $null = New-Item -ItemType Directory -Path $directory -Force
    $tempPath = Join-Path $directory ('.{0}.{1}.tmp' -f ([IO.Path]::GetFileName($Path)), [guid]::NewGuid().ToString('N'))
    try {
        $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tempPath -Encoding UTF8
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-LastRun {
    param(
        [Parameter(Mandatory)][string]$Status,
        [bool]$Changed = $false,
        [AllowNull()][string]$SourceBranch,
        [AllowNull()][string]$SourceSha,
        [AllowNull()][string]$WebsitePath,
        [AllowNull()][string]$WebsiteSha256,
        [AllowNull()][string]$Message
    )

    $receipt = [ordered]@{
        schema = 'agentswitchboard.prompt-kit-sync.run.v1'
        checkedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        status = $Status
        changed = $Changed
        sourceRepository = $RepositoryUrl
        sourceBranch = $SourceBranch
        sourceSha = $SourceSha
        websitePath = $WebsitePath
        websiteSha256 = $WebsiteSha256
        message = $Message
    }
    Write-JsonAtomic -Value $receipt -Path $LastRunPath
    return [pscustomobject]$receipt
}

function Invoke-BoundedCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [AllowNull()][string]$WorkingDirectory,
        [int]$TimeoutSeconds = $CommandTimeoutSeconds,
        [switch]$AllowNonZero
    )

    $job = Start-Job -ScriptBlock {
        param($Executable, $CommandArguments, $Directory)
        $ErrorActionPreference = 'Stop'
        if (-not [string]::IsNullOrWhiteSpace($Directory)) {
            Set-Location -LiteralPath $Directory
        }
        $lines = @(& $Executable @CommandArguments 2>&1 | ForEach-Object { $_.ToString() })
        [pscustomobject]@{
            exitCode = [int]$LASTEXITCODE
            lines = @($lines)
        }
    } -ArgumentList $FilePath, $Arguments, $WorkingDirectory

    try {
        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
        if (-not $completed) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            throw "Command timed out after $TimeoutSeconds seconds: $FilePath $($Arguments -join ' ')"
        }
        if ($job.State -ne 'Completed') {
            $reason = $job.ChildJobs[0].JobStateInfo.Reason
            throw "Command failed to execute: $FilePath. $reason"
        }
        $result = Receive-Job -Job $job
    }
    finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }

    if (-not $result) {
        throw "Command returned no result envelope: $FilePath"
    }
    if (-not $AllowNonZero -and [int]$result.exitCode -ne 0) {
        $detail = @($result.lines) -join [Environment]::NewLine
        throw "Command failed with exit code $($result.exitCode): $FilePath $($Arguments -join ' ')`r`n$detail"
    }
    return $result
}

function Resolve-PythonCommand {
    foreach ($candidate in @(
        [pscustomobject]@{ File = 'py.exe'; Prefix = @('-3') },
        [pscustomobject]@{ File = 'python.exe'; Prefix = @() },
        [pscustomobject]@{ File = 'python'; Prefix = @() }
    )) {
        if (Get-Command $candidate.File -ErrorAction SilentlyContinue) {
            return $candidate
        }
    }
    throw 'Python 3 is required to validate the canonical Prompt Kit website.'
}

function Get-RemoteDefaultHead {
    if (-not (Get-Command 'git.exe' -ErrorAction SilentlyContinue) -and -not (Get-Command 'git' -ErrorAction SilentlyContinue)) {
        throw 'Git is required to poll the Prompt Kit repository.'
    }
    $git = if (Get-Command 'git.exe' -ErrorAction SilentlyContinue) { 'git.exe' } else { 'git' }
    $result = Invoke-BoundedCommand -FilePath $git -Arguments @('ls-remote', '--symref', $RepositoryUrl, 'HEAD') -WorkingDirectory $null
    $branch = $null
    $sha = $null
    foreach ($line in @($result.lines)) {
        if ($line -match '^ref:\s+refs/heads/(?<branch>[^\s]+)\s+HEAD$') {
            $branch = $Matches.branch
        }
        elseif ($line -match '^(?<sha>[0-9a-fA-F]{40})\s+HEAD$') {
            $sha = $Matches.sha.ToLowerInvariant()
        }
    }
    if ([string]::IsNullOrWhiteSpace($branch) -or [string]::IsNullOrWhiteSpace($sha)) {
        throw 'Could not resolve the Prompt Kit repository default branch and exact HEAD.'
    }
    return [pscustomobject]@{ Branch = $branch; Sha = $sha; Git = $git }
}

function Ensure-ManagedSource {
    param(
        [Parameter(Mandatory)][string]$Git,
        [Parameter(Mandatory)][string]$Branch
    )

    $sourceParent = Split-Path -Parent $SourcePath
    $null = New-Item -ItemType Directory -Path $sourceParent -Force

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        Invoke-BoundedCommand -FilePath $Git -Arguments @(
            'clone', '--branch', $Branch, '--single-branch', $RepositoryUrl, $SourcePath
        ) -WorkingDirectory $sourceParent | Out-Null
    }
    elseif (-not (Test-Path -LiteralPath (Join-Path $SourcePath '.git') -PathType Container)) {
        throw "Managed Prompt Kit source path exists but is not a Git checkout: $SourcePath"
    }

    $originResult = Invoke-BoundedCommand -FilePath $Git -Arguments @('remote', 'get-url', 'origin') -WorkingDirectory $SourcePath
    $origin = (@($originResult.lines) | Select-Object -First 1).Trim()
    if ((Normalize-RepositoryUrl $origin) -ne (Normalize-RepositoryUrl $RepositoryUrl)) {
        throw "Managed Prompt Kit source has an unexpected origin: $origin"
    }

    $statusResult = Invoke-BoundedCommand -FilePath $Git -Arguments @('status', '--porcelain') -WorkingDirectory $SourcePath
    if (@($statusResult.lines).Count -gt 0) {
        throw 'Managed Prompt Kit source contains local changes. No reset, clean, checkout overwrite, or discard was attempted.'
    }

    $branchResult = Invoke-BoundedCommand -FilePath $Git -Arguments @('branch', '--show-current') -WorkingDirectory $SourcePath
    $currentBranch = (@($branchResult.lines) | Select-Object -First 1).Trim()
    if ($currentBranch -ne $Branch) {
        throw "Managed Prompt Kit source is on '$currentBranch' while the remote default branch is '$Branch'. No branch rewrite was attempted."
    }

    Invoke-BoundedCommand -FilePath $Git -Arguments @('fetch', 'origin', $Branch, '--prune') -WorkingDirectory $SourcePath | Out-Null
    $remoteHeadResult = Invoke-BoundedCommand -FilePath $Git -Arguments @('rev-parse', "origin/$Branch") -WorkingDirectory $SourcePath
    $remoteHead = (@($remoteHeadResult.lines) | Select-Object -First 1).Trim().ToLowerInvariant()
    if ($remoteHead -notmatch '^[0-9a-f]{40}$') {
        throw "Fetched Prompt Kit head is not a commit SHA: $remoteHead"
    }

    $localHeadResult = Invoke-BoundedCommand -FilePath $Git -Arguments @('rev-parse', 'HEAD') -WorkingDirectory $SourcePath
    $localHead = (@($localHeadResult.lines) | Select-Object -First 1).Trim().ToLowerInvariant()
    if ($localHead -ne $remoteHead) {
        $ancestor = Invoke-BoundedCommand -FilePath $Git -Arguments @('merge-base', '--is-ancestor', $localHead, "origin/$Branch") -WorkingDirectory $SourcePath -AllowNonZero
        if ([int]$ancestor.exitCode -ne 0) {
            throw 'Managed Prompt Kit source is not an ancestor of the fetched remote head. No reset or overwrite was attempted.'
        }
        Invoke-BoundedCommand -FilePath $Git -Arguments @('merge', '--ff-only', "origin/$Branch") -WorkingDirectory $SourcePath | Out-Null
    }

    $finalHeadResult = Invoke-BoundedCommand -FilePath $Git -Arguments @('rev-parse', 'HEAD') -WorkingDirectory $SourcePath
    $finalHead = (@($finalHeadResult.lines) | Select-Object -First 1).Trim().ToLowerInvariant()
    if ($finalHead -ne $remoteHead) {
        throw "Managed Prompt Kit checkout did not converge to fetched head $remoteHead."
    }
    return $finalHead
}

function Test-CanonicalPromptKit {
    foreach ($relativePath in @($ExpectedWebsiteRelativePath, $GeneratorRelativePath, $GeneratorManifestRelativePath)) {
        if (-not (Test-Path -LiteralPath (Join-Path $SourcePath $relativePath) -PathType Leaf)) {
            throw "Canonical Prompt Kit source is missing required file: $relativePath"
        }
    }

    $manifestPath = Join-Path $SourcePath $GeneratorManifestRelativePath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schema_version -ne 'prompt-kit-generators/v1' -or -not $manifest.generators -or $manifest.generators.Count -lt 1) {
        throw 'Canonical Prompt Kit generator manifest is missing or unsupported.'
    }

    $python = Resolve-PythonCommand
    $arguments = @($python.Prefix) + @(
        $GeneratorRelativePath,
        '--output',
        $ExpectedWebsiteRelativePath,
        '--check'
    )
    Invoke-BoundedCommand -FilePath $python.File -Arguments $arguments -WorkingDirectory $SourcePath -TimeoutSeconds 300 | Out-Null
}

function Publish-PromptKitWebsite {
    param(
        [Parameter(Mandatory)][string]$SourceSha,
        [Parameter(Mandatory)][int]$RetentionCount
    )

    if ($SourceSha -notmatch '^[0-9a-f]{40}$') {
        throw "Refusing invalid Prompt Kit release identity: $SourceSha"
    }
    $sourceWebsite = Join-Path $SourcePath $ExpectedWebsiteRelativePath
    $sourceHash = (Get-FileHash -LiteralPath $sourceWebsite -Algorithm SHA256).Hash.ToLowerInvariant()
    $releaseDirectory = Join-Path $ReleaseRoot $SourceSha
    $releasePath = Join-Path $releaseDirectory 'index.html'
    $null = New-Item -ItemType Directory -Path $releaseDirectory -Force

    $needsCopy = $true
    if (Test-Path -LiteralPath $releasePath -PathType Leaf) {
        $existingHash = (Get-FileHash -LiteralPath $releasePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $needsCopy = $existingHash -ne $sourceHash
    }
    if ($needsCopy) {
        $tempPath = Join-Path $releaseDirectory ('.index.{0}.tmp' -f [guid]::NewGuid().ToString('N'))
        try {
            Copy-Item -LiteralPath $sourceWebsite -Destination $tempPath
            $copiedHash = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($copiedHash -ne $sourceHash) {
                throw 'Prompt Kit website hash changed during local publication.'
            }
            Move-Item -LiteralPath $tempPath -Destination $releasePath -Force
        }
        finally {
            if (Test-Path -LiteralPath $tempPath) {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return [pscustomobject]@{ Path = $releasePath; Sha256 = $sourceHash }
}

function Prune-PromptKitReleases {
    param(
        [Parameter(Mandatory)][string]$CurrentSourceSha,
        [Parameter(Mandatory)][int]$RetentionCount
    )

    if ($RetentionCount -lt 1) { $RetentionCount = 1 }
    if (-not (Test-Path -LiteralPath $ReleaseRoot -PathType Container)) { return }

    $releaseDirectories = @(Get-ChildItem -LiteralPath $ReleaseRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^[0-9a-f]{40}$' } |
        Sort-Object LastWriteTimeUtc -Descending)
    $keepers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$keepers.Add($CurrentSourceSha)
    foreach ($release in $releaseDirectories) {
        if ($keepers.Count -ge $RetentionCount) { break }
        [void]$keepers.Add($release.Name)
    }

    foreach ($oldRelease in $releaseDirectories) {
        if (-not $keepers.Contains($oldRelease.Name)) {
            Remove-Item -LiteralPath $oldRelease.FullName -Recurse -Force
        }
    }
}

$config = Get-Config
$state = Read-State
if ($Mode -eq 'Status') {
    [ordered]@{
        schema = 'agentswitchboard.prompt-kit-sync.status.v1'
        enabled = [bool]$config.enabled
        intervalMinutes = [int]$config.intervalMinutes
        sourceRepository = $RepositoryUrl
        stateRoot = $StateRoot
        sourceSha = if ($state) { [string]$state.sourceSha } else { $null }
        websitePath = if ($state) { [string]$state.websitePath } else { $null }
        lastRunPath = $LastRunPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

if (-not [bool]$config.enabled) {
    Write-Output (@{
        schema = 'agentswitchboard.prompt-kit-sync.status.v1'
        enabled = $false
        status = 'disabled'
        message = 'Prompt Kit polling is disabled. No network request was made.'
    } | ConvertTo-Json -Depth 4)
    exit 0
}

$null = New-Item -ItemType Directory -Path $StateRoot -Force
$lockStream = $null
try {
    try {
        $lockStream = [IO.File]::Open($LockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    catch [IO.IOException] {
        $receipt = Write-LastRun -Status 'skipped-lock-held' -Message 'Another Prompt Kit sync run is already active.'
        Write-Output ($receipt | ConvertTo-Json -Depth 6)
        exit 0
    }

    $remote = Get-RemoteDefaultHead
    $previousSha = if ($state) { [string]$state.sourceSha } else { $null }
    $previousPath = if ($state) { [string]$state.websitePath } else { $null }
    $previousHash = if ($state) { [string]$state.websiteSha256 } else { $null }
    $publishedHealthy = $false
    if ($previousSha -eq $remote.Sha -and -not [string]::IsNullOrWhiteSpace($previousPath) -and (Test-Path -LiteralPath $previousPath -PathType Leaf)) {
        $currentHash = (Get-FileHash -LiteralPath $previousPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $publishedHealthy = -not [string]::IsNullOrWhiteSpace($previousHash) -and $currentHash -eq $previousHash
    }

    if ($publishedHealthy) {
        $receipt = Write-LastRun -Status 'current' -Changed:$false -SourceBranch $remote.Branch -SourceSha $remote.Sha -WebsitePath $previousPath -WebsiteSha256 $previousHash -Message 'Remote Prompt Kit head is unchanged and the published website hash still matches state.'
        Write-Output ($receipt | ConvertTo-Json -Depth 6)
        exit 0
    }

    $sourceSha = Ensure-ManagedSource -Git $remote.Git -Branch $remote.Branch
    Test-CanonicalPromptKit
    $retention = if ($config.PSObject.Properties.Name -contains 'retentionCount') { [int]$config.retentionCount } else { 2 }
    $published = Publish-PromptKitWebsite -SourceSha $sourceSha -RetentionCount $retention
    $changed = $previousSha -ne $sourceSha

    $newState = [ordered]@{
        schema = 'agentswitchboard.prompt-kit-sync.state.v1'
        updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        sourceRepository = $RepositoryUrl
        sourceBranch = $remote.Branch
        sourceSha = $sourceSha
        websitePath = $published.Path
        websiteSha256 = $published.Sha256
    }
    Write-JsonAtomic -Value $newState -Path $StatePath
    # Prune only after the new state is durable. A state-write failure therefore leaves
    # the previously referenced known-good website intact.
    Prune-PromptKitReleases -CurrentSourceSha $sourceSha -RetentionCount $retention
    $receipt = Write-LastRun -Status 'published' -Changed:$changed -SourceBranch $remote.Branch -SourceSha $sourceSha -WebsitePath $published.Path -WebsiteSha256 $published.Sha256 -Message 'Canonical Prompt Kit website validated and published to the AgentSwitchboard-managed local cache.'
    Write-Output ($receipt | ConvertTo-Json -Depth 6)
}
catch {
    try {
        $receipt = Write-LastRun -Status 'failed' -Message $_.Exception.Message
        Write-Error ($receipt | ConvertTo-Json -Depth 6)
    }
    catch {
        Write-Error $_.Exception.Message
    }
    exit 1
}
finally {
    if ($lockStream) {
        $lockStream.Dispose()
    }
}
