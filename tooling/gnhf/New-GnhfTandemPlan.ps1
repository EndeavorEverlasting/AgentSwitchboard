[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CatalogPath,
    [Parameter(Mandatory)][string]$RepositoriesPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateSet("maximize-sprint-completion", "maximize-token-efficiency")][string]$Mode = "maximize-sprint-completion",
    [ValidateRange(1, 1440)][int]$MaxCatalogAgeMinutes = 60,
    [switch]$AllowUnauthenticatedModels,
    [switch]$SkipRepositoryValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ExpandedPath {
    param([Parameter(Mandatory)][string]$Path)
    [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
}

function ConvertTo-SafeSlug {
    param([Parameter(Mandatory)][string]$Value)
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "lane" }
    if ($slug.Length -gt 64) { return $slug.Substring(0, 64).Trim('-') }
    $slug
}

function Invoke-GitScalar {
    param([string]$Repository, [string[]]$Arguments)
    $output = @(& git -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in '$Repository': $($output -join [Environment]::NewLine)" }
    ([string]($output | Select-Object -First 1)).Trim()
}

$CatalogPath = Resolve-ExpandedPath $CatalogPath
$RepositoriesPath = Resolve-ExpandedPath $RepositoriesPath
$OutputPath = Resolve-ExpandedPath $OutputPath
foreach ($required in @($CatalogPath, $RepositoriesPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required input not found: $required" }
}
$catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json -Depth 40
$manifest = Get-Content -LiteralPath $RepositoriesPath -Raw | ConvertFrom-Json -Depth 40
if ([string]$catalog.schemaVersion -ne "agentswitchboard-gnhf-model-catalog/v1") { throw "Unsupported model catalog schemaVersion: $($catalog.schemaVersion)" }
if ([string]$manifest.schemaVersion -ne "agentswitchboard-linked-repositories/v1") { throw "Unsupported linked repository schemaVersion: $($manifest.schemaVersion)" }

try { $catalogCapturedAt = [DateTimeOffset]::Parse([string]$catalog.capturedAt) }
catch { throw "The model catalog capturedAt value is invalid." }
$catalogAgeMinutes = ([DateTimeOffset]::UtcNow - $catalogCapturedAt.ToUniversalTime()).TotalMinutes
if ($catalogAgeMinutes -lt -5) { throw "The model catalog timestamp is implausibly in the future." }
if ($catalogAgeMinutes -gt $MaxCatalogAgeMinutes) { throw "The model catalog is stale ($([Math]::Round($catalogAgeMinutes, 1)) minutes old; maximum $MaxCatalogAgeMinutes). Refresh it before planning." }
$readyProviderIds = @($catalog.providers | Where-Object authenticationStatus -eq "reported" | ForEach-Object providerId)
$availableModels = @($catalog.models | Where-Object {
    if ($_.available -ne $true) { return $false }
    if ($AllowUnauthenticatedModels) { return $true }
    ([string]$_.providerId -in $readyProviderIds) -or (@($_.routingTags) -contains "local-capable")
})
if ($availableModels.Count -eq 0) { throw "The model catalog has no authenticated or local-capable available models. Authenticate a provider or use -AllowUnauthenticatedModels for plan exploration only." }
$enabledRepositories = @($manifest.repositories | Where-Object { $_.enabled -eq $true })
if ($enabledRepositories.Count -eq 0) { throw "The linked repository manifest has no enabled repositories." }

$seenRepositoryPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$usedModels = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$lanes = [System.Collections.Generic.List[object]]::new()
$outputRoot = Split-Path -Parent $OutputPath
$handoffRoot = Join-Path $outputRoot "handoffs"

foreach ($repository in $enabledRepositories) {
    $repoPathRaw = [string]$repository.path
    $objectivePathRaw = [string]$repository.objectivePath
    if ($repoPathRaw -match '^__.+__$' -or $objectivePathRaw -match '^__.+__$') {
        throw "Enabled repository '$($repository.id)' still contains placeholder paths."
    }
    $repoPath = Resolve-ExpandedPath $repoPathRaw
    $objectivePath = Resolve-ExpandedPath $objectivePathRaw
    if (-not $seenRepositoryPaths.Add($repoPath)) { throw "Two enabled lanes target the same repository path: $repoPath" }

    if (-not $SkipRepositoryValidation) {
        if (-not (Test-Path -LiteralPath $repoPath -PathType Container)) { throw "Repository path not found for '$($repository.id)': $repoPath" }
        if (-not (Test-Path -LiteralPath $objectivePath -PathType Leaf)) { throw "Objective path not found for '$($repository.id)': $objectivePath" }
        if ((Invoke-GitScalar -Repository $repoPath -Arguments @("rev-parse", "--is-inside-work-tree")) -ne "true") { throw "Not a Git working tree: $repoPath" }
        $status = @(& git -C $repoPath status --porcelain=v1 2>&1 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($LASTEXITCODE -ne 0) { throw "Unable to read Git status for '$repoPath'." }
        if ($status.Count -gt 0) { throw "Repository '$($repository.id)' is dirty and cannot enter tandem execution." }
        $branch = Invoke-GitScalar -Repository $repoPath -Arguments @("branch", "--show-current")
        if ([string]::IsNullOrWhiteSpace($branch)) { throw "Repository '$($repository.id)' is detached." }
    }

    $preferredModels = @($repository.preferredModels)
    $preferredProviders = @($repository.preferredProviders) + @($manifest.providerPreference)
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($preferred in $preferredModels) {
        foreach ($model in @($availableModels | Where-Object { [string]$_.fullId -eq [string]$preferred })) { [void]$candidates.Add($model) }
    }
    foreach ($providerId in $preferredProviders) {
        foreach ($model in @($availableModels | Where-Object { [string]$_.providerId -eq [string]$providerId } | Sort-Object fullId)) { [void]$candidates.Add($model) }
    }
    foreach ($model in @($availableModels | Sort-Object fullId)) { [void]$candidates.Add($model) }

    $selectedModel = $null
    foreach ($candidate in $candidates) {
        if (-not $usedModels.Contains([string]$candidate.fullId)) { $selectedModel = $candidate; break }
    }
    if (-not $selectedModel) { $selectedModel = $candidates[0] }
    [void]$usedModels.Add([string]$selectedModel.fullId)

    $laneId = ConvertTo-SafeSlug -Value ([string]$repository.id)
    $laneHandoffRoot = Join-Path $handoffRoot $laneId
    $inputPath = Join-Path $laneHandoffRoot "input.json"
    $executionObjectivePath = Join-Path $laneHandoffRoot "objective.md"
    $resultPath = Join-Path $laneHandoffRoot "result.json"
    $summaryPath = Join-Path $laneHandoffRoot "summary.md"
    $modelProfileId = ConvertTo-SafeSlug -Value ("$laneId-$($selectedModel.fullId)")

    $lane = [pscustomobject][ordered]@{
        laneId = $laneId
        repositoryId = [string]$repository.id
        repository = [string]$repository.repository
        repoPath = $repoPath
        originalObjectivePath = $objectivePath
        objectivePath = $executionObjectivePath
        agent = [string]$repository.agent
        modelProfileId = $modelProfileId
        modelId = [string]$selectedModel.fullId
        maxIterations = [int]$repository.maxIterations
        maxTokens = [long]$repository.maxTokens
        timeoutMinutes = [int]$repository.timeoutMinutes
        stopWhen = [string]$repository.stopWhen
        dependsOn = @($repository.dependsOn)
        ownedScope = @($repository.ownedScope)
        forbiddenScope = @($repository.forbiddenScope)
        handoff = [pscustomobject][ordered]@{
            inputPath = $inputPath
            resultPath = $resultPath
            summaryPath = $summaryPath
        }
    }
    [void]$lanes.Add($lane)
}

$laneIds = @($lanes | ForEach-Object laneId)
foreach ($lane in $lanes) {
    foreach ($dependency in @($lane.dependsOn)) {
        if ($dependency -notin $laneIds) { throw "Lane '$($lane.laneId)' depends on unknown lane '$dependency'." }
        if ($dependency -eq $lane.laneId) { throw "Lane '$($lane.laneId)' cannot depend on itself." }
    }
}

$plan = [ordered]@{
    schemaVersion = "agentswitchboard-gnhf-tandem-plan/v1"
    createdAt = (Get-Date).ToString("o")
    mode = $Mode
    maxParallelRepos = [int]$manifest.maxParallelRepos
    catalogHash = (Get-FileHash -LiteralPath $CatalogPath -Algorithm SHA256).Hash
    catalogCapturedAt = $catalogCapturedAt.ToString("o")
    catalogAgeMinutes = [Math]::Round($catalogAgeMinutes, 3)
    allowUnauthenticatedModels = [bool]$AllowUnauthenticatedModels
    lanes = @($lanes)
}

foreach ($lane in $lanes) {
    $laneRoot = Split-Path -Parent $lane.handoff.inputPath
    if (-not (Test-Path -LiteralPath $laneRoot -PathType Container)) { [void](New-Item -ItemType Directory -Path $laneRoot -Force) }
    [ordered]@{
        schemaVersion = "agentswitchboard-gnhf-handoff-input/v1"
        createdAt = (Get-Date).ToString("o")
        laneId = $lane.laneId
        repository = $lane.repository
        repoPath = $lane.repoPath
        originalObjectivePath = $lane.originalObjectivePath
        executionObjectivePath = $lane.objectivePath
        agent = $lane.agent
        modelProfileId = $lane.modelProfileId
        modelId = $lane.modelId
        dependsOn = @($lane.dependsOn)
        ownedScope = @($lane.ownedScope)
        forbiddenScope = @($lane.forbiddenScope)
        expectedResultPath = $lane.handoff.resultPath
        expectedSummaryPath = $lane.handoff.summaryPath
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $lane.handoff.inputPath -Encoding utf8NoBOM

    $originalObjective = if (Test-Path -LiteralPath $lane.originalObjectivePath -PathType Leaf) {
        Get-Content -LiteralPath $lane.originalObjectivePath -Raw
    }
    else {
        "Fixture planning mode: the original objective file was not read."
    }
    @(
        "# AgentSwitchboard tandem lane — $($lane.laneId)",
        "",
        "Read the machine-readable handoff input before making changes:",
        "``$($lane.handoff.inputPath)``",
        "",
        "Repository: ``$($lane.repository)``",
        "Selected agent: ``$($lane.agent)``",
        "Selected model: ``$($lane.modelId)``",
        "Owned scope: $(@($lane.ownedScope) -join '; ')",
        "Forbidden scope: $(@($lane.forbiddenScope) -join '; ')",
        "Expected result packet: ``$($lane.handoff.resultPath)``",
        "Expected English summary: ``$($lane.handoff.summaryPath)``",
        "",
        "AgentSwitchboard writes the final result packet. Do not claim a higher proof level than observed evidence.",
        "Do not push, merge, deploy, release, mutate a default branch, or access credentials unless the repository objective explicitly authorizes it and the launcher supplies that authority.",
        "",
        "## Repository objective",
        "",
        $originalObjective
    ) | Set-Content -LiteralPath $lane.objectivePath -Encoding utf8NoBOM
}

if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) { [void](New-Item -ItemType Directory -Path $outputRoot -Force) }
$tempPath = "$OutputPath.$([guid]::NewGuid().ToString('N')).tmp"
$plan | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $tempPath -Encoding utf8NoBOM
Move-Item -LiteralPath $tempPath -Destination $OutputPath -Force
Write-Host "Tandem plan written: $OutputPath" -ForegroundColor Green
Write-Host "Enabled lanes: $($lanes.Count)"
Write-Host "Parallel cap:  $($plan.maxParallelRepos)"
$lanes | ForEach-Object { Write-Host "  $($_.laneId): $($_.modelId) -> $($_.repository)" }
