[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$QueuePath,
    [string]$OutputPath,
    [string]$PlanId = [Guid]::NewGuid().ToString('n').Substring(0, 12),
    [switch]$SkipDependencyCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$QueuePath = [IO.Path]::GetFullPath($QueuePath)
if (-not (Test-Path -LiteralPath $QueuePath -PathType Leaf)) {
    throw "Prompt queue file not found: $QueuePath"
}

$queue = Get-Content -LiteralPath $QueuePath -Raw | ConvertFrom-Json
if ([string]$queue.schema -ne 'agentswitchboard.gnhf.prompt-queue.v1') {
    throw "Unsupported prompt queue schema: $($queue.schema)"
}

$laneIds = @($queue.lanes | ForEach-Object { [string]$_.id })
$laneIdSet = New-Object 'System.Collections.Generic.HashSet[string]' @(,[string[]]$laneIds)

if (-not $SkipDependencyCheck) {
    foreach ($lane in $queue.lanes) {
        if ($lane.PSObject.Properties.Name -contains 'dependsOn') {
            foreach ($dep in $lane.dependsOn) {
                if (-not $laneIdSet.Contains([string]$dep)) {
                    throw "Lane '$($lane.id)' depends on unknown lane '$dep'."
                }
            }
        }
    }
}

$inDegree = @{}
$successors = @{}
foreach ($lane in $queue.lanes) {
    $inDegree[[string]$lane.id] = 0
    $successors[[string]$lane.id] = @()
}
foreach ($lane in $queue.lanes) {
    $id = [string]$lane.id
    if ($lane.PSObject.Properties.Name -contains 'dependsOn') {
        foreach ($dep in $lane.dependsOn) {
            $inDegree[$id]++
            $successors[[string]$dep] += @($id)
        }
    }
}

$order = @()
$ready = New-Object 'System.Collections.Generic.Queue[string]'
foreach ($id in $laneIds) {
    if ($inDegree[$id] -eq 0) { $ready.Enqueue($id) }
}
while ($ready.Count -gt 0) {
    $current = $ready.Dequeue()
    $order += $current
    foreach ($next in $successors[$current]) {
        $inDegree[$next]--
        if ($inDegree[$next] -eq 0) { $ready.Enqueue($next) }
    }
}

if ($order.Count -ne $queue.lanes.Count) {
    $cycle = @($laneIds | Where-Object { $_ -notin $order })
    throw "Dependency cycle detected among lanes: $($cycle -join ', ')"
}

$defaultAgent = if ($queue.PSObject.Properties.Name -contains 'defaultAgent') { [string]$queue.defaultAgent } else { 'opencode' }
$stageIndex = 0
$plannedLanes = [ordered]@{}
foreach ($id in $order) {
    $lane = $queue.lanes | Where-Object { [string]$_.id -eq $id | | Select-Object -First 1
    $agent = if ($lane.PSObject.Properties.Name -contains 'agent') { [string]$lane.agent } else { $defaultAgent }
    $maxIterations = if ($lane.PSObject.Properties.Name -contains 'maxIterations') { [int]$lane.maxIterations } else { 4 }
    $maxTokens = if ($lane.PSObject.Properties.Name -contains 'maxTokens') { [int]$lane.maxTokens } else { 250000 }
    $allowPush = if ($lane.PSObject.Properties.Name -contains 'allowPush') { [bool]$lane.allowPush } else { $false }
    $dependsOn = if ($lane.PSObject.Properties.Name -contains 'dependsOn') { @($lane.dependsOn | ForEach-Object { [string]$_ }) } else { @() }
    $expectedArtifacts = if ($lane.PSObject.Properties.Name -contains 'expectedArtifacts') { @($lane.expectedArtifacts | ForEach-Object { [string]$_ }) } else { @() }

    $plannedLanes[$id] = [ordered]@{
        id = $id
        lane = [string]$lane.lane
        stageIndex = $stageIndex
        dependsOn = $dependsOn
        agent = $agent
        promptPath = if ($lane.PSObject.Properties.Name -contains 'promptPath') { [string]$lane.promptPath } else { '' }
        maxIterations = $maxIterations
        maxTokens = $maxTokens
        ownedScope = [string]$lane.ownedScope
        forbiddenScope = [string]$lane.forbiddenScope
        expectedArtifacts = $expectedArtifacts
        validation = [string]$lane.validation
        stopWhen = [string]$lane.stopWhen
        allowPush = $allowPush
    }
    $stageIndex++
}

$targetRepository = if ($queue.PSObject.Properties.Name -contains 'targetRepository') { [string]$queue.targetRepository } else { '' }
$plan = [ordered]@{
    schema = 'agentswitchboard.gnhf.queue-plan.v1'
    planId = $PlanId
    queueId = [string]$queue.queueId
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    sprint = [string]$queue.sprint
    baseBranch = [string]$queue.baseBranch
    targetRepository = $targetRepository
    executionOrder = $order
    lanes = $plannedLanes
    ready = ($order.Count -gt 0)
    blockers = @()
}

$planJson = $plan | ConvertTo-Json -Depth 10
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Output $planJson
}
else {
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $planJson | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
    Write-Host "Wrote queue plan to $OutputPath" -ForegroundColor Green
}
