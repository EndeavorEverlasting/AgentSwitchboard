[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$QueuePath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [switch]$SkipRepositoryValidation,
    [switch]$SkipPullRequestDiscovery
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$queueSupportRoot = Join-Path $PSScriptRoot "queue"
. (Join-Path $queueSupportRoot "GnhfPromptQueue.Repository.ps1")
. (Join-Path $queueSupportRoot "GnhfPromptQueue.Graph.ps1")

$ingestionModule = Join-Path $PSScriptRoot "GnhfPromptIngestion.psm1"
$contractModule = Join-Path $PSScriptRoot "GnhfPromptContracts.psm1"
foreach ($required in @($ingestionModule, $contractModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required AgentSwitchboard prompt module is missing: $required"
    }
}
Import-Module $ingestionModule -Force
Import-Module $contractModule -Force

$QueuePath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($QueuePath))
$OutputRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($OutputRoot))
if (-not (Test-Path -LiteralPath $QueuePath -PathType Leaf)) {
    throw "Prompt queue manifest not found: $QueuePath"
}
$queueDirectory = Split-Path -Parent $QueuePath
$queue = Get-Content -LiteralPath $QueuePath -Raw | ConvertFrom-Json -Depth 50
if ([string]$queue.schemaVersion -cne "agentswitchboard-gnhf-prompt-queue/v1") {
    throw "Unsupported prompt queue schemaVersion: $($queue.schemaVersion)"
}
if ([string]$queue.queueId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$') {
    throw "Invalid prompt queue queueId."
}
$maxParallel = [int]$queue.maxParallel
if ($maxParallel -lt 1 -or $maxParallel -gt 16) {
    throw "Prompt queue maxParallel must be between 1 and 16."
}

$profiles = @($queue.agents | Where-Object { $_.enabled -eq $true } | Sort-Object id)
if ($profiles.Count -eq 0) { throw "Prompt queue has no enabled agent profiles." }
if ($maxParallel -gt $profiles.Count) {
    throw "maxParallel $maxParallel exceeds enabled agent profile count $($profiles.Count); concurrent lanes require distinct profiles."
}
$profileIds = @($profiles | ForEach-Object { [string]$_.id })
if ($profileIds.Count -ne @($profileIds | Sort-Object -Unique).Count) {
    throw "Prompt queue contains duplicate enabled agent profile IDs."
}
foreach ($profile in $profiles) {
    if ([string]$profile.runtimeFamily -cne "Cursor") {
        throw "Prompt queue v1 supports Cursor runtime profiles only."
    }
    if ([string]::IsNullOrWhiteSpace([string]$profile.gnhfAgent)) {
        throw "Agent profile '$($profile.id)' has no gnhfAgent."
    }
}

$rawLanes = @($queue.lanes)
if ($rawLanes.Count -eq 0) { throw "Prompt queue has no lanes." }
$waves = Get-DependencyWaves -Lanes $rawLanes
$laneById = @{}
foreach ($lane in $rawLanes) { $laneById[[string]$lane.laneId] = $lane }

$contexts = @{}
$seenRepoPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($lane in $rawLanes) {
    $laneId = [string]$lane.laneId
    if ($laneId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$') {
        throw "Invalid laneId '$laneId'."
    }
    $promptPath = Resolve-QueuePath -Path ([string]$lane.promptPath) -BaseDirectory $queueDirectory
    $repoPath = Resolve-QueuePath -Path ([string]$lane.repositoryPath) -BaseDirectory $queueDirectory
    if (-not (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
        throw "Prompt path not found for lane '$laneId': $promptPath"
    }
    if (-not $seenRepoPaths.Add($repoPath)) {
        throw "Two queue lanes target the same repository path: $repoPath"
    }
    if (Test-PathWithin -Child $OutputRoot -Parent $repoPath) {
        throw "Queue output root cannot be inside target repository '$repoPath'."
    }
    $promptText = Get-Content -LiteralPath $promptPath -Raw
    $pinnedAgent = $null
    $sourceKind = "sectioned-prompt"
    if ($promptText.TrimStart().StartsWith("{")) {
        $sourceKind = "regular-sprint-request"
    }
    elseif ($promptText -match '(?is)^\s*gnhf(?:\s|`)') {
        $metadata = Get-GnhfCommandPromptMetadata -Text $promptText
        $pinnedAgent = [string]$metadata.agent
        $sourceKind = [string]$metadata.sourceKind
    }
    $repository = Get-RepositoryIntelligence `
        -Lane $lane `
        -RepositoryPath $repoPath `
        -SkipValidation:$SkipRepositoryValidation `
        -SkipPullRequests:$SkipPullRequestDiscovery

    $contexts[$laneId] = [pscustomobject][ordered]@{
        lane = $lane
        laneId = $laneId
        promptPath = $promptPath
        promptText = $promptText
        promptSourceKind = $sourceKind
        pinnedAgent = $pinnedAgent
        repository = $repository
    }
}

if (Test-Path -LiteralPath $OutputRoot -PathType Container) {
    if (@(Get-ChildItem -LiteralPath $OutputRoot -Force).Count -gt 0) {
        throw "Queue output root already contains files. Use a new run directory: $OutputRoot"
    }
}
else {
    [void](New-Item -ItemType Directory -Path $OutputRoot -Force)
}
$lanesRoot = Join-Path $OutputRoot "lanes"
$resultsRoot = Join-Path $OutputRoot "results"
foreach ($directory in @($lanesRoot, $resultsRoot)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
}

$batches = [Collections.Generic.List[object]]::new()
$plannedLanes = [Collections.Generic.List[object]]::new()
$batchSequence = 0

foreach ($wave in $waves) {
    $waveLaneIds = @($wave.laneIds)
    for ($offset = 0; $offset -lt $waveLaneIds.Count; $offset += $maxParallel) {
        $last = [Math]::Min($offset + $maxParallel - 1, $waveLaneIds.Count - 1)
        $chunk = @($waveLaneIds[$offset..$last])
        $batchId = "batch-{0:d3}" -f $batchSequence
        $availableProfiles = [Collections.Generic.List[object]]::new()
        foreach ($profile in $profiles) { [void]$availableProfiles.Add($profile) }

        foreach ($laneId in $chunk) {
            $context = $contexts[[string]$laneId]
            $selectedProfile = $null
            if (-not [string]::IsNullOrWhiteSpace([string]$context.pinnedAgent)) {
                $selectedProfile = @(
                    $availableProfiles |
                        Where-Object { [string]$_.gnhfAgent -ceq [string]$context.pinnedAgent } |
                        Sort-Object id |
                        Select-Object -First 1
                )
                if ($selectedProfile.Count -eq 0) {
                    throw "Lane '$laneId' pins GNHF agent '$($context.pinnedAgent)', but no unused matching profile is available in $batchId."
                }
                $selectedProfile = $selectedProfile[0]
            }
            else {
                $selectedProfile = $availableProfiles[0]
            }
            [void]$availableProfiles.Remove($selectedProfile)

            $lane = $context.lane
            $conversion = ConvertTo-GnhfPromptContracts `
                -PromptText ([string]$context.promptText) `
                -RepositoryName ([string]$context.repository.name) `
                -RepositoryRemote ([string]$context.repository.remote) `
                -RepositoryLocalPath ([string]$context.repository.path) `
                -BaseBranch ([string]$context.repository.branch) `
                -DefaultAgent ([string]$selectedProfile.gnhfAgent) `
                -TimeoutSeconds ([int]$lane.timeoutSeconds) `
                -ExecutionIntent ([string]$lane.executionIntent) `
                -DesiredProofLevel ([string]$lane.desiredProofLevel) `
                -ExpectedArtifactPath @($lane.expectedArtifactPaths)

            if ([string]$conversion.regularRequest.executionIntent -cne [string]$lane.executionIntent) {
                throw "Lane '$laneId' prompt executionIntent conflicts with the queue manifest."
            }
            if ([string]$conversion.regularRequest.desiredProofLevel -cne [string]$lane.desiredProofLevel) {
                throw "Lane '$laneId' prompt proof level conflicts with the queue manifest."
            }
            if ([string]$conversion.compiledPrompt.agentRoute.agent -cne [string]$selectedProfile.gnhfAgent) {
                throw "Lane '$laneId' compiled route '$($conversion.compiledPrompt.agentRoute.agent)' conflicts with assigned profile '$($selectedProfile.gnhfAgent)'."
            }

            $requestValidation = Test-GnhfPromptContract -Document $conversion.regularRequest -ExpectedKind "regular-sprint-request"
            $compiledValidation = Test-GnhfPromptContract -Document $conversion.compiledPrompt -ExpectedKind "compiled-gnhf-prompt-result"
            if (-not $requestValidation.Valid) {
                throw "Lane '$laneId' regular request failed: $($requestValidation.Errors -join '; ')"
            }
            if (-not $compiledValidation.Valid) {
                throw "Lane '$laneId' compiled prompt failed: $($compiledValidation.Errors -join '; ')"
            }

            $laneRoot = Join-Path $lanesRoot $laneId
            $requestPath = Join-Path $laneRoot "regular-request.json"
            $compiledPath = Join-Path $laneRoot "compiled-gnhf-prompt.json"
            $repositoryPath = Join-Path $laneRoot "repository-intelligence.json"
            $resultPath = Join-Path $resultsRoot "$laneId.json"
            Write-AtomicJson -Value $conversion.regularRequest -Path $requestPath
            Write-AtomicJson -Value $conversion.compiledPrompt -Path $compiledPath
            Write-AtomicJson -Value $context.repository -Path $repositoryPath

            [void]$plannedLanes.Add([pscustomobject][ordered]@{
                laneId = $laneId
                batchId = $batchId
                batchSequence = $batchSequence
                wave = [int]$wave.wave
                dependsOn = @($lane.dependsOn)
                runtimeFamily = "Cursor"
                agentProfileId = [string]$selectedProfile.id
                gnhfAgent = [string]$selectedProfile.gnhfAgent
                provider = if ($selectedProfile.PSObject.Properties.Name -contains "provider") { $selectedProfile.provider } else { $null }
                repository = $context.repository
                prompt = [pscustomobject][ordered]@{
                    sourcePath = $context.promptPath
                    sourceKind = [string]$conversion.sourceKind
                    sha256 = (Get-FileHash -LiteralPath $context.promptPath -Algorithm SHA256).Hash
                }
                contracts = [pscustomobject][ordered]@{
                    requestPath = $requestPath
                    compiledPromptPath = $compiledPath
                    repositoryIntelligencePath = $repositoryPath
                }
                result = [pscustomobject][ordered]@{
                    resultPath = $resultPath
                    stdoutPath = Join-Path $resultsRoot "$laneId.stdout.txt"
                    stderrPath = Join-Path $resultsRoot "$laneId.stderr.txt"
                }
            })
        }

        [void]$batches.Add([pscustomobject][ordered]@{
            batchId = $batchId
            sequence = $batchSequence
            wave = [int]$wave.wave
            laneIds = @($chunk)
        })
        $batchSequence++
    }
}

$plan = [pscustomobject][ordered]@{
    schemaVersion = "agentswitchboard-gnhf-prompt-queue-plan/v1"
    queueId = [string]$queue.queueId
    createdAt = (Get-Date).ToString("o")
    sourceQueueHash = (Get-FileHash -LiteralPath $QueuePath -Algorithm SHA256).Hash
    outputRoot = $OutputRoot
    maxParallel = $maxParallel
    batches = @($batches)
    lanes = @($plannedLanes)
    automaticPush = $false
    automaticMerge = $false
}
$planPath = Join-Path $OutputRoot "queue-plan.json"
Write-AtomicJson -Value $plan -Path $planPath

Write-Host "Prompt queue plan written: $planPath" -ForegroundColor Green
Write-Host "Queue:   $($plan.queueId)"
Write-Host "Lanes:   $($plannedLanes.Count)"
Write-Host "Batches: $($batches.Count)"
foreach ($batch in $batches) {
    Write-Host "  $($batch.batchId): $(@($batch.laneIds) -join ', ')"
}
