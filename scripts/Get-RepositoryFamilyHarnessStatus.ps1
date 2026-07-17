[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [string]$OutputRoot,
    [switch]$FailOnNotReady
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent $repoRoot
}
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)

$runStamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$nonce = ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
$runId = "${runStamp}-${nonce}"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) ("AgentSwitchboard/repository-family/{0}" -f $runId)
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

$registryPath = Join-Path $repoRoot '.ai/harness/repository-family.registry.json'
$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
$repositories = @($registry.repositories)
if ($repositories.Count -ne 4) {
    throw 'Repository-family registry must contain exactly four repositories.'
}

$git = (Get-Command git -ErrorAction Stop).Source

function Invoke-GitText {
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = & $git -C $RepositoryPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        ExitCode = $exitCode
        Text = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    }
}

function Test-RemoteMatches {
    param(
        [AllowNull()][string]$Actual,
        [Parameter(Mandatory)][string]$ExpectedFullName
    )

    if ([string]::IsNullOrWhiteSpace($Actual)) { return $false }
    $normalized = $Actual.Trim()
    $normalized = $normalized -replace '^git@github\.com:', 'https://github.com/'
    $normalized = $normalized -replace '^ssh://git@github\.com/', 'https://github.com/'
    $normalized = $normalized.TrimEnd('/')
    $normalized = $normalized -replace '\.git$', ''
    return $normalized -ieq "https://github.com/${ExpectedFullName}"
}

function Test-PathInside {
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Parent
    )

    $candidateFull = [IO.Path]::GetFullPath($Candidate).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($candidateFull -ieq $parentFull) { return $true }
    return $candidateFull.StartsWith($parentFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

$resolvedPaths = @{}
foreach ($repository in $repositories) {
    if ($repository.fullName -eq 'EndeavorEverlasting/AgentSwitchboard') {
        $resolvedPaths[$repository.id] = $repoRoot
        continue
    }

    $candidate = $null
    foreach ($directoryName in @($repository.directoryNames)) {
        $path = Join-Path $WorkspaceRoot $directoryName
        if (Test-Path -LiteralPath $path -PathType Container) {
            $candidate = [IO.Path]::GetFullPath($path)
            break
        }
    }
    $resolvedPaths[$repository.id] = $candidate
}

foreach ($path in @($resolvedPaths.Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
    if (Test-PathInside -Candidate $OutputRoot -Parent ([string]$path)) {
        throw "OutputRoot must be outside inspected repositories: $OutputRoot"
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$runContext = [ordered]@{
    schema = 'agentswitchboard.repository-family-run-context.v1'
    runId = $runId
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    producer = 'EndeavorEverlasting/AgentSwitchboard'
    workflowId = 'repository-family-intake'
    workspaceRootSupplied = $PSBoundParameters.ContainsKey('WorkspaceRoot')
    networkAllowed = $false
    mutationAllowed = $false
    proofTarget = 'read-only-repository-intake'
}

$repositoryResults = @()
foreach ($repository in $repositories) {
    $path = $resolvedPaths[$repository.id]
    $directoryName = if ($null -ne $path) { Split-Path -Leaf ([string]$path) } else { $null }
    $isRepository = $false
    $remoteMatches = $false
    $branch = $null
    $head = $null
    $dirty = $null
    $missingPaths = @()
    $status = 'not_present'
    $exactNextCommand = "git clone `"$($repository.cloneUrl)`" `"$(@($repository.directoryNames)[0])`""

    if ($null -ne $path) {
        $rootProbe = Invoke-GitText -RepositoryPath $path -Arguments @('rev-parse', '--show-toplevel')
        $isRepository = $rootProbe.ExitCode -eq 0

        if ($isRepository) {
            $remote = Invoke-GitText -RepositoryPath $path -Arguments @('config', '--get', 'remote.origin.url')
            $remoteMatches = $remote.ExitCode -eq 0 -and (Test-RemoteMatches -Actual $remote.Text -ExpectedFullName $repository.fullName)

            $branchProbe = Invoke-GitText -RepositoryPath $path -Arguments @('branch', '--show-current')
            if ($branchProbe.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($branchProbe.Text)) {
                $branch = $branchProbe.Text
            }

            $headProbe = Invoke-GitText -RepositoryPath $path -Arguments @('rev-parse', 'HEAD')
            if ($headProbe.ExitCode -eq 0) {
                $head = $headProbe.Text
            }

            $statusProbe = Invoke-GitText -RepositoryPath $path -Arguments @('status', '--porcelain=v1')
            if ($statusProbe.ExitCode -eq 0) {
                $dirty = -not [string]::IsNullOrWhiteSpace($statusProbe.Text)
            }
        }

        foreach ($relativePath in @($repository.requiredPaths)) {
            if (-not (Test-Path -LiteralPath (Join-Path $path $relativePath))) {
                $missingPaths += [string]$relativePath
            }
        }

        if (-not $isRepository -or -not $remoteMatches -or [string]::IsNullOrWhiteSpace([string]$branch)) {
            $status = 'blocked'
            $exactNextCommand = "git -C `"${directoryName}`" remote -v"
        }
        elseif ($missingPaths.Count -gt 0) {
            $status = 'partial'
            $exactNextCommand = "git -C `"${directoryName}`" status --short"
        }
        else {
            $status = 'ready'
            $firstValidator = [string]@($repository.validationCommands)[0]
            $exactNextCommand = "Set-Location `"${directoryName}`"; ${firstValidator}"
        }
    }

    $repositoryResults += [ordered]@{
        id = [string]$repository.id
        fullName = [string]$repository.fullName
        status = $status
        directoryName = $directoryName
        git = [ordered]@{
            isRepository = [bool]$isRepository
            remoteMatches = [bool]$remoteMatches
            branch = $branch
            head = $head
            dirty = $dirty
        }
        missingRequiredPaths = @($missingPaths)
        validatorCommands = @($repository.validationCommands)
        proofLevel = 'read-only-repository-intake'
        proofCeiling = [string]$repository.proofCeiling
        exactNextCommand = $exactNextCommand
    }
}

$ready = @($repositoryResults | Where-Object status -eq 'ready').Count
$partial = @($repositoryResults | Where-Object status -eq 'partial').Count
$blocked = @($repositoryResults | Where-Object status -eq 'blocked').Count
$notPresent = @($repositoryResults | Where-Object status -eq 'not_present').Count

$artifacts = @(
    [ordered]@{ artifactId = 'repository-family-run-context'; artifactType = 'run-context'; path = 'run-context.json'; tracked = $false; sensitivity = 'local-operational' },
    [ordered]@{ artifactId = 'repository-family-status'; artifactType = 'status-report'; path = 'repository-family-status.json'; tracked = $false; sensitivity = 'local-operational' },
    [ordered]@{ artifactId = 'repository-family-operator-report'; artifactType = 'operator-report'; path = 'operator-report.md'; tracked = $false; sensitivity = 'local-operational' },
    [ordered]@{ artifactId = 'repository-family-final-handoff'; artifactType = 'final-handoff'; path = 'final-handoff.json'; tracked = $false; sensitivity = 'local-operational' }
)

$proofCeiling = 'Read-only local clone presence, Git identity, branch, HEAD, dirty-state observation, and required-path readiness only. No fetch freshness, child validation, provider, runtime, merge, deployment, or product proof.'
$statusDocument = [ordered]@{
    schema = 'agentswitchboard.repository-family-status.v1'
    runContext = $runContext
    summary = [ordered]@{
        total = 4
        ready = $ready
        partial = $partial
        blocked = $blocked
        notPresent = $notPresent
    }
    repositories = @($repositoryResults)
    artifacts = $artifacts
    proofLevel = 'read-only-repository-intake'
    proofCeiling = $proofCeiling
    nextCommand = 'pwsh -NoLogo -NoProfile -File ./scripts/Test-RepositoryFamilyHarness.ps1'
}

$completed = @($repositoryResults | Where-Object status -eq 'ready' | ForEach-Object { $_.fullName })
$blockedItems = @($repositoryResults | Where-Object status -ne 'ready' | ForEach-Object { "$($_.fullName): $($_.status)" })
$handoff = [ordered]@{
    schema = 'agentswitchboard.repository-family-handoff.v1'
    runId = $runId
    completed = $completed
    blocked = $blockedItems
    risks = @(
        'Local observations become stale after Git or filesystem changes.',
        'A ready profile does not authorize child mutation or prove child validators pass.',
        'Unmerged pull requests are evidence only and are not treated as default-branch authority.'
    )
    proofLevel = 'read-only-repository-intake'
    proofCeiling = $proofCeiling
    receivingAgentMustReinspectState = $true
    nextCommand = 'pwsh -NoLogo -NoProfile -File ./scripts/Test-RepositoryFamilyHarness.ps1'
}

$runContext | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutputRoot 'run-context.json') -Encoding utf8
$statusDocument | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $OutputRoot 'repository-family-status.json') -Encoding utf8
$handoff | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutputRoot 'final-handoff.json') -Encoding utf8

$reportLines = @(
    '# Repository Family Harness Status',
    '',
    "- Run ID: $runId",
    '- Proof level: read-only-repository-intake',
    "- Ready: $ready / 4",
    "- Partial: $partial",
    "- Blocked: $blocked",
    "- Not present: $notPresent",
    '',
    '## Repositories',
    ''
)
foreach ($result in $repositoryResults) {
    $reportLines += "### $($result.fullName)"
    $reportLines += ''
    $reportLines += "- Status: $($result.status)"
    $reportLines += "- Directory: $(if ($null -eq $result.directoryName) { 'not present' } else { $result.directoryName })"
    $reportLines += "- Branch: $(if ($null -eq $result.git.branch) { 'unknown' } else { $result.git.branch })"
    $reportLines += "- HEAD: $(if ($null -eq $result.git.head) { 'unknown' } else { $result.git.head })"
    $reportLines += "- Dirty: $(if ($null -eq $result.git.dirty) { 'unknown' } else { $result.git.dirty })"
    $reportLines += "- Missing required paths: $(if (@($result.missingRequiredPaths).Count -eq 0) { 'none' } else { @($result.missingRequiredPaths) -join ', ' })"
    $reportLines += "- Next command: ``$($result.exactNextCommand)``"
    $reportLines += ''
}
$reportLines += '## Proof ceiling'
$reportLines += ''
$reportLines += $proofCeiling
$reportLines += ''
$reportLines += 'The receiving agent must re-inspect repository state before acting.'
$reportLines | Set-Content -LiteralPath (Join-Path $OutputRoot 'operator-report.md') -Encoding utf8

Write-Host "Repository family status: $OutputRoot" -ForegroundColor Cyan
Write-Host "Ready=$ready Partial=$partial Blocked=$blocked NotPresent=$notPresent"

if ($FailOnNotReady -and $ready -ne 4) {
    exit 2
}

$statusDocument
