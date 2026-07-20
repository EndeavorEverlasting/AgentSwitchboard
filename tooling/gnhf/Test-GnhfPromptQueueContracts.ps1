[CmdletBinding()]
param(
    [ValidateSet("All", "Parse", "Plan", "Run", "Failures")]
    [string]$Stage = "All"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "fixtures/GnhfPromptQueue.TestHelpers.ps1")

$plannerPath = Join-Path $PSScriptRoot "New-GnhfPromptQueuePlan.ps1"
$executorPath = Join-Path $PSScriptRoot "Invoke-GnhfPromptQueue.ps1"
$fixtureRunnerPath = Join-Path $PSScriptRoot "fixtures/Invoke-FakeCursorQueueRunner.ps1"
$ingestionPath = Join-Path $PSScriptRoot "GnhfPromptIngestion.psm1"
$contractPath = Join-Path $PSScriptRoot "GnhfPromptContracts.psm1"
$schemaRoot = Join-Path $PSScriptRoot "schemas"

function Test-ParseStage {
    $helperPaths = @(
        (Join-Path $PSScriptRoot "queue/GnhfPromptQueue.Repository.ps1"),
        (Join-Path $PSScriptRoot "queue/GnhfPromptQueue.Graph.ps1"),
        (Join-Path $PSScriptRoot "queue/GnhfPromptQueue.Execution.ps1"),
        (Join-Path $PSScriptRoot "fixtures/GnhfPromptQueue.TestHelpers.ps1")
    )
    foreach ($path in @($plannerPath, $executorPath, $fixtureRunnerPath, $PSCommandPath) + $helperPaths) {
        Assert-QueueContract (Test-Path -LiteralPath $path -PathType Leaf) "Required queue file is missing: $path"
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        $messages = @($errors | ForEach-Object { $_.Message })
        Assert-QueueContract ($messages.Count -eq 0) "$path must parse. $($messages -join '; ')"
    }
    $schemaExpectations = [ordered]@{
        "gnhf-prompt-queue.v1.schema.json" = "agentswitchboard-gnhf-prompt-queue/v1"
        "gnhf-prompt-queue-plan.v1.schema.json" = "agentswitchboard-gnhf-prompt-queue-plan/v1"
        "gnhf-prompt-queue-lane-result.v1.schema.json" = "agentswitchboard-gnhf-prompt-queue-lane-result/v1"
    }
    foreach ($entry in $schemaExpectations.GetEnumerator()) {
        $schemaPath = Join-Path $schemaRoot $entry.Key
        $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -Depth 40
        Assert-QueueContract ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "$($entry.Key) must use JSON Schema 2020-12."
        Assert-QueueContract ($schema.properties.schemaVersion.const -eq $entry.Value) "$($entry.Key) must bind $($entry.Value)."
    }
    Write-Host "PASS: prompt queue parse and schema contracts"
}

function New-PlannedFixture {
    $fixture = New-QueueFixture
    $planRun = Invoke-ChildPwsh -Arguments @(
        "-File", $plannerPath,
        "-QueuePath", $fixture.QueuePath,
        "-OutputRoot", $fixture.OutputRoot,
        "-SkipPullRequestDiscovery"
    )
    Assert-QueueContract ($planRun.ExitCode -eq 0) "Queue planner failed: $($planRun.Text)"
    $planPath = Join-Path $fixture.OutputRoot "queue-plan.json"
    Assert-QueueContract (Test-Path -LiteralPath $planPath -PathType Leaf) "Queue plan was not written."
    $fixture | Add-Member -NotePropertyName PlanPath -NotePropertyValue $planPath
    $fixture | Add-Member -NotePropertyName Plan -NotePropertyValue (Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 50)
    $fixture
}

function Test-PlanStage {
    $fixture = New-PlannedFixture
    try {
        $plan = $fixture.Plan
        Assert-QueueContract ($plan.schemaVersion -eq "agentswitchboard-gnhf-prompt-queue-plan/v1") "Unexpected queue plan schema."
        Assert-QueueContract (@($plan.lanes).Count -eq 3) "Queue plan must contain three lanes."
        Assert-QueueContract (@($plan.batches).Count -eq 2) "Queue plan must contain two dependency batches."
        $firstBatch = @($plan.batches | Sort-Object sequence | Select-Object -First 1)[0]
        Assert-QueueContract (@($firstBatch.laneIds).Count -eq 2) "First batch must contain two independent lanes."
        $firstLanes = @($plan.lanes | Where-Object { $_.batchId -eq $firstBatch.batchId })
        Assert-QueueContract (@($firstLanes.agentProfileId | Sort-Object -Unique).Count -eq 2) "Concurrent lanes must receive distinct agent profiles."
        Assert-QueueContract (@($firstLanes.repository.path | Sort-Object -Unique).Count -eq 2) "Concurrent lanes must target distinct repositories."
        $laneB = @($plan.lanes | Where-Object laneId -eq "lane-b")[0]
        Assert-QueueContract ($laneB.gnhfAgent -eq "goose") "Canonical command must retain its pinned goose route."
        Assert-QueueContract ($laneB.batchSequence -eq 1) "Dependent lane must be scheduled after the first batch."
        Assert-QueueContract (@($laneB.dependsOn) -contains "lane-a") "Dependent lane must preserve lane-a dependency."
        Assert-QueueContract ($laneB.repository.pullRequest.status -eq "skipped") "Fixture PR discovery must be explicitly skipped."

        Import-Module $contractPath -Force
        foreach ($lane in @($plan.lanes)) {
            $request = Test-GnhfPromptContractFile -Path ([string]$lane.contracts.requestPath) -ExpectedKind "regular-sprint-request"
            $compiled = Test-GnhfPromptContractFile -Path ([string]$lane.contracts.compiledPromptPath) -ExpectedKind "compiled-gnhf-prompt-result"
            Assert-QueueContract $request.Valid "Lane '$($lane.laneId)' request invalid: $($request.Errors -join '; ')"
            Assert-QueueContract $compiled.Valid "Lane '$($lane.laneId)' compiled prompt invalid: $($compiled.Errors -join '; ')"
        }

        $planOnly = Invoke-ChildPwsh -Arguments @("-File", $executorPath, "-PlanPath", $fixture.PlanPath, "-PlanOnly")
        Assert-QueueContract ($planOnly.ExitCode -eq 0) "Queue PlanOnly failed: $($planOnly.Text)"
        $executionPlan = $planOnly.Text | ConvertFrom-Json -Depth 50
        Assert-QueueContract ($executionPlan.schemaVersion -eq "agentswitchboard-gnhf-prompt-queue-execution-plan/v1") "Unexpected execution plan schema."
        Assert-QueueContract (-not (Test-Path -LiteralPath (Join-Path $fixture.OutputRoot "queue-summary.json"))) "PlanOnly must not create runtime summary."
        Assert-RepositoriesUnchanged -Fixture $fixture
        Write-Host "PASS: prompt queue planning, assignment, contract population, and no-mutation proof"
    }
    finally {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-RunStage {
    $fixture = New-PlannedFixture
    try {
        $previousFailLane = $env:AGENTSWITCHBOARD_QUEUE_FIXTURE_FAIL_LANE
        Remove-Item Env:AGENTSWITCHBOARD_QUEUE_FIXTURE_FAIL_LANE -ErrorAction SilentlyContinue
        try {
            $run = Invoke-ChildPwsh -Arguments @(
                "-File", $executorPath,
                "-PlanPath", $fixture.PlanPath,
                "-RuntimeEntrypoint", $fixtureRunnerPath,
                "-AllowAlternateRuntimeEntrypoint"
            )
        }
        finally {
            if ($null -eq $previousFailLane) {
                Remove-Item Env:AGENTSWITCHBOARD_QUEUE_FIXTURE_FAIL_LANE -ErrorAction SilentlyContinue
            }
            else {
                $env:AGENTSWITCHBOARD_QUEUE_FIXTURE_FAIL_LANE = $previousFailLane
            }
        }
        Assert-QueueContract ($run.ExitCode -eq 0) "Queue success harness failed: $($run.Text)"
        $summaryPath = Join-Path $fixture.OutputRoot "queue-summary.json"
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -Depth 50
        Assert-QueueContract ($summary.status -eq "succeeded") "Queue success harness must succeed."
        Assert-QueueContract ([int]$summary.succeeded -eq 3) "All three fixture lanes must succeed."
        foreach ($lane in @($fixture.Plan.lanes)) {
            $result = Get-Content -LiteralPath ([string]$lane.result.resultPath) -Raw | ConvertFrom-Json -Depth 50
            Assert-QueueContract ($result.status -eq "succeeded") "Lane '$($lane.laneId)' must succeed."
            Assert-QueueContract ($result.observedCommit -eq $true) "Lane '$($lane.laneId)' must require commit proof."
            Assert-QueueContract ($result.observedArtifacts -eq $true) "Lane '$($lane.laneId)' must require artifact proof."
        }
        Assert-RepositoriesUnchanged -Fixture $fixture
        Write-Host "PASS: prompt queue batch execution and runtime-result consumption harness"
    }
    finally {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-FailureStage {
    $duplicateFixture = New-QueueFixture
    try {
        $queue = Get-Content -LiteralPath $duplicateFixture.QueuePath -Raw | ConvertFrom-Json -Depth 50
        $queue.lanes[1].repositoryPath = $queue.lanes[0].repositoryPath
        $queue | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $duplicateFixture.QueuePath -Encoding utf8NoBOM
        $run = Invoke-ChildPwsh -Arguments @(
            "-File", $plannerPath,
            "-QueuePath", $duplicateFixture.QueuePath,
            "-OutputRoot", $duplicateFixture.OutputRoot,
            "-SkipPullRequestDiscovery"
        )
        Assert-QueueContract ($run.ExitCode -ne 0) "Duplicate repository queue must be rejected."
        Assert-QueueContract ($run.Text -match "same repository path") "Duplicate repository rejection must be explicit."
        Assert-RepositoriesUnchanged -Fixture $duplicateFixture
    }
    finally {
        Remove-Item -LiteralPath $duplicateFixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }

    $cycleFixture = New-QueueFixture
    try {
        $queue = Get-Content -LiteralPath $cycleFixture.QueuePath -Raw | ConvertFrom-Json -Depth 50
        $queue.lanes[0].dependsOn = @("lane-b")
        $queue | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $cycleFixture.QueuePath -Encoding utf8NoBOM
        $run = Invoke-ChildPwsh -Arguments @(
            "-File", $plannerPath,
            "-QueuePath", $cycleFixture.QueuePath,
            "-OutputRoot", $cycleFixture.OutputRoot,
            "-SkipPullRequestDiscovery"
        )
        Assert-QueueContract ($run.ExitCode -ne 0) "Dependency cycle must be rejected."
        Assert-QueueContract ($run.Text -match "cycle|cannot make progress") "Dependency cycle rejection must be explicit."
        Assert-RepositoriesUnchanged -Fixture $cycleFixture
    }
    finally {
        Remove-Item -LiteralPath $cycleFixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }

    $agentFixture = New-QueueFixture
    try {
        $queue = Get-Content -LiteralPath $agentFixture.QueuePath -Raw | ConvertFrom-Json -Depth 50
        $queue.agents[1].gnhfAgent = "copilot"
        $queue | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $agentFixture.QueuePath -Encoding utf8NoBOM
        $run = Invoke-ChildPwsh -Arguments @(
            "-File", $plannerPath,
            "-QueuePath", $agentFixture.QueuePath,
            "-OutputRoot", $agentFixture.OutputRoot,
            "-SkipPullRequestDiscovery"
        )
        Assert-QueueContract ($run.ExitCode -ne 0) "Missing pinned-agent profile must be rejected."
        Assert-QueueContract ($run.Text -match "pins GNHF agent 'goose'") "Pinned-agent rejection must identify the missing route."
        Assert-RepositoriesUnchanged -Fixture $agentFixture
    }
    finally {
        Remove-Item -LiteralPath $agentFixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }

    $dependencyFixture = New-PlannedFixture
    try {
        $previousFailLane = $env:AGENTSWITCHBOARD_QUEUE_FIXTURE_FAIL_LANE
        $env:AGENTSWITCHBOARD_QUEUE_FIXTURE_FAIL_LANE = "lane-a"
        try {
            $run = Invoke-ChildPwsh -Arguments @(
                "-File", $executorPath,
                "-PlanPath", $dependencyFixture.PlanPath,
                "-RuntimeEntrypoint", $fixtureRunnerPath,
                "-AllowAlternateRuntimeEntrypoint"
            )
        }
        finally {
            if ($null -eq $previousFailLane) {
                Remove-Item Env:AGENTSWITCHBOARD_QUEUE_FIXTURE_FAIL_LANE -ErrorAction SilentlyContinue
            }
            else {
                $env:AGENTSWITCHBOARD_QUEUE_FIXTURE_FAIL_LANE = $previousFailLane
            }
        }
        Assert-QueueContract ($run.ExitCode -ne 0) "Queue with a failed lane must exit nonzero."
        $laneResults = @{}
        foreach ($lane in @($dependencyFixture.Plan.lanes)) {
            $laneResults[[string]$lane.laneId] = Get-Content -LiteralPath ([string]$lane.result.resultPath) -Raw | ConvertFrom-Json -Depth 50
        }
        Assert-QueueContract ($laneResults["lane-a"].status -eq "failed") "lane-a must record fixture failure."
        Assert-QueueContract ($laneResults["lane-c"].status -eq "succeeded") "Independent lane-c must still complete."
        Assert-QueueContract ($laneResults["lane-b"].status -eq "blocked-by-dependency") "lane-b must be blocked after lane-a failure."
        Assert-QueueContract ($laneResults["lane-b"].processExitCode -eq $null) "Blocked dependent lane must not start a process."
        Assert-RepositoriesUnchanged -Fixture $dependencyFixture
    }
    finally {
        Remove-Item -LiteralPath $dependencyFixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "PASS: prompt queue collision, cycle, route, and dependency-failure contracts"
}

switch ($Stage) {
    "Parse" { Test-ParseStage }
    "Plan" { Test-PlanStage }
    "Run" { Test-RunStage }
    "Failures" { Test-FailureStage }
    "All" {
        Test-ParseStage
        Test-PlanStage
        Test-RunStage
        Test-FailureStage
        Write-Host "PASS: AgentSwitchboard multi-prompt queue orchestration contracts"
    }
}
