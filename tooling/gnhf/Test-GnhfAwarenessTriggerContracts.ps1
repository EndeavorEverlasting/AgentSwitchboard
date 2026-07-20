[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "fixtures/GnhfPromptQueue.TestHelpers.ps1")

$plannerPath = Join-Path $PSScriptRoot "New-GnhfPromptQueuePlan.ps1"
$executorPath = Join-Path $PSScriptRoot "Invoke-GnhfPromptQueue.ps1"
$fixtureRunnerPath = Join-Path $PSScriptRoot "fixtures/Invoke-FakeCursorQueueRunner.ps1"
$triggerHelperPath = Join-Path $PSScriptRoot "queue/GnhfPromptQueue.Triggers.ps1"
$triggerSchemaPath = Join-Path $PSScriptRoot "schemas/awareness-trigger-flags.v1.schema.json"

foreach ($path in @($plannerPath, $executorPath, $fixtureRunnerPath, $triggerHelperPath, $PSCommandPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    $messages = @($errors | ForEach-Object Message)
    Assert-QueueContract ($messages.Count -eq 0) "$path must parse. $($messages -join '; ')"
}
$schema = Get-Content -LiteralPath $triggerSchemaPath -Raw | ConvertFrom-Json -Depth 40
Assert-QueueContract ($schema.properties.schemaVersion.const -eq "agentswitchboard-awareness-trigger-flags/v1") "Trigger schema version is not bound."
Assert-QueueContract ($schema.properties.flaggingPhase.const -eq "pre-agent-launch") "Trigger schema must bind the pre-launch phase."
Assert-QueueContract ($schema.properties.awarenessGate.properties.required.const -eq $true) "Trigger schema must require the awareness gate."

function New-AwarenessFixturePlan {
    $fixture = New-QueueFixture
    $planRun = Invoke-ChildPwsh -Arguments @(
        "-File", $plannerPath,
        "-QueuePath", $fixture.QueuePath,
        "-OutputRoot", $fixture.OutputRoot,
        "-SkipPullRequestDiscovery"
    )
    Assert-QueueContract ($planRun.ExitCode -eq 0) "Trigger fixture planning failed: $($planRun.Text)"
    $planPath = Join-Path $fixture.OutputRoot "queue-plan.json"
    $fixture | Add-Member -NotePropertyName PlanPath -NotePropertyValue $planPath
    $fixture | Add-Member -NotePropertyName Plan -NotePropertyValue (Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 50)
    return $fixture
}

$fixture = New-AwarenessFixturePlan
try {
    $plan = $fixture.Plan
    Assert-QueueContract ($plan.preAwarenessFlagging.required -eq $true) "Trigger flagging must be mandatory."
    Assert-QueueContract ($plan.preAwarenessFlagging.completed -eq $true) "Trigger flagging must complete during planning."
    Assert-QueueContract ([int]$plan.preAwarenessFlagging.applicationCount -eq 3) "Every fixture app must be registered."
    Assert-QueueContract ([int]$plan.preAwarenessFlagging.laneSnapshotCount -eq 3) "Every lane must receive a trigger snapshot."

    $activeTotal = 0
    $criticalTotal = 0
    foreach ($lane in @($plan.lanes)) {
        $triggerPath = [string]$lane.triggerFlags.path
        Assert-QueueContract (Test-Path -LiteralPath $triggerPath -PathType Leaf) "Lane '$($lane.laneId)' trigger snapshot is missing."
        $actualHash = (Get-FileHash -LiteralPath $triggerPath -Algorithm SHA256).Hash
        Assert-QueueContract ($actualHash -ceq [string]$lane.triggerFlags.sha256) "Lane '$($lane.laneId)' trigger hash is not bound to the plan."
        $snapshot = Get-Content -LiteralPath $triggerPath -Raw | ConvertFrom-Json -Depth 40
        Assert-QueueContract ($snapshot.flaggingPhase -eq "pre-agent-launch") "Lane '$($lane.laneId)' was not flagged before launch."
        Assert-QueueContract ($snapshot.application.id -eq $lane.application.id) "Lane '$($lane.laneId)' application identity does not match."
        Assert-QueueContract ($snapshot.awarenessGate.satisfied -eq $true) "Lane '$($lane.laneId)' awareness gate is not satisfied."
        $activeTotal += [int]$snapshot.activeTriggerCount
        $criticalTotal += [int]$snapshot.criticalTriggerCount

        $compiled = Get-Content -LiteralPath ([string]$lane.contracts.compiledPromptPath) -Raw | ConvertFrom-Json -Depth 50
        Assert-QueueContract ($compiled.prompt.Contains($triggerPath)) "Lane '$($lane.laneId)' prompt does not identify its trigger snapshot."
        Assert-QueueContract ($compiled.prompt.Contains($actualHash)) "Lane '$($lane.laneId)' prompt does not bind the trigger hash."
        Assert-QueueContract ($compiled.prompt.Contains("Before completing repository analysis or producing any awareness assessment")) "Lane '$($lane.laneId)' lacks the awareness instruction."
        Assert-QueueContract (@($compiled.readFirst) -contains $triggerPath) "Lane '$($lane.laneId)' does not read trigger flags first."
    }
    Assert-QueueContract ($activeTotal -eq 4) "The fixture must expose four active triggers."
    Assert-QueueContract ($criticalTotal -eq 0) "An absent risk file must not activate a critical trigger."

    $planOnly = Invoke-ChildPwsh -Arguments @("-File", $executorPath, "-PlanPath", $fixture.PlanPath, "-PlanOnly")
    Assert-QueueContract ($planOnly.ExitCode -eq 0) "PlanOnly trigger gate failed: $($planOnly.Text)"
    $executionPlan = $planOnly.Text | ConvertFrom-Json -Depth 50
    Assert-QueueContract (@($executionPlan.lanes | Where-Object { $_.awarenessGateSatisfied -ne $true }).Count -eq 0) "PlanOnly must verify every awareness gate."
    Assert-RepositoriesUnchanged -Fixture $fixture
}
finally {
    Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
}

$modifiedFixture = New-AwarenessFixturePlan
try {
    $lane = @($modifiedFixture.Plan.lanes | Select-Object -First 1)[0]
    "modified evidence" | Add-Content -LiteralPath ([string]$lane.triggerFlags.path) -Encoding utf8
    $run = Invoke-ChildPwsh -Arguments @("-File", $executorPath, "-PlanPath", $modifiedFixture.PlanPath, "-PlanOnly")
    Assert-QueueContract ($run.ExitCode -ne 0) "Modified trigger evidence must stop execution."
    Assert-QueueContract ($run.Text -match "hash mismatch|altered") "Modified trigger evidence must report a hash failure."
    Assert-RepositoriesUnchanged -Fixture $modifiedFixture
}
finally {
    Remove-Item -LiteralPath $modifiedFixture.Root -Recurse -Force -ErrorAction SilentlyContinue
}

$unknownFixture = New-QueueFixture
try {
    $queue = Get-Content -LiteralPath $unknownFixture.QueuePath -Raw | ConvertFrom-Json -Depth 50
    $queue.lanes[0].applicationId = "unknown-app"
    $queue | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $unknownFixture.QueuePath -Encoding utf8NoBOM
    $run = Invoke-ChildPwsh -Arguments @("-File", $plannerPath, "-QueuePath", $unknownFixture.QueuePath, "-OutputRoot", $unknownFixture.OutputRoot, "-SkipPullRequestDiscovery")
    Assert-QueueContract ($run.ExitCode -ne 0) "Unknown application references must be rejected."
    Assert-QueueContract ($run.Text -match "unknown or disabled application") "Unknown application rejection must be explicit."
    Assert-RepositoriesUnchanged -Fixture $unknownFixture
}
finally {
    Remove-Item -LiteralPath $unknownFixture.Root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "PASS: application triggers are flagged, bound, and gated before awareness analysis"
