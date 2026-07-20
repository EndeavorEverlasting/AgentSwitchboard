[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$FailureMessage = ""
    )
    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("$Name`: $FailureMessage")
    }
}

function Get-Json {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$failures.Add("required-file/$RelativePath`: missing")
        return $null
    }
    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        [void]$failures.Add("json/$RelativePath`: $($_.Exception.Message)")
        return $null
    }
}

$requiredFiles = @(
    ".ai/agent-contract.json",
    ".ai/harness/manifest.json",
    ".ai/harness/artifact-registry.json",
    ".ai/harness/app-composition.graph.json",
    ".ai/harness/app-harness-report.template.md",
    ".ai/harness/schemas/app-composition-graph.schema.json",
    ".ai/harness/schemas/app-harness-validation.schema.json",
    "plans/README.md",
    "plans/plan-registry.json",
    "plans/schemas/public-plan.schema.json",
    "plans/active/ASB-2026-07-public-plans-startup-readiness.plan.json",
    "plans/active/ASB-2026-07-public-plans-startup-readiness.md",
    "plans/active/ASB-2026-07-one-command-harness-proof.plan.json",
    "plans/active/ASB-2026-07-one-command-harness-proof.md",
    ".ai/skills/public-plan-coordination/SKILL.md",
    "tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1",
    "tooling/gnhf/schemas/agent-startup-readiness.schema.json",
    "tooling/gnhf/fixtures/startup-readiness/state.partial.json",
    "AgentSwitchboard.cmd",
    "Test-AppHarness.cmd",
    "scripts/Test-AppHarness.ps1",
    "tests/test_app_harness_validator.py",
    "tests/test_public_plan_contracts.py",
    "templates/repository-agent-contract/AGENTS.md",
    "templates/repository-agent-contract/SKILLS.md",
    "templates/repository-agent-contract/CAPABILITIES.md",
    "templates/repository-agent-contract/TRIGGERS.md",
    "templates/repository-agent-contract/.ai/agent-contract.json",
    "templates/repository-agent-contract/.ai/skills/public-plan-coordination/SKILL.md",
    "templates/repository-agent-contract/plans/README.md",
    "templates/repository-agent-contract/plans/plan-registry.json",
    "templates/repository-agent-contract/plans/schemas/public-plan.schema.json"
)
foreach ($relativePath in $requiredFiles) {
    Add-Result -Passed (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf) -Name "required/$relativePath" -FailureMessage "file is missing"
}

$contract = Get-Json -RelativePath ".ai/agent-contract.json"
$manifest = Get-Json -RelativePath ".ai/harness/manifest.json"
$artifactRegistry = Get-Json -RelativePath ".ai/harness/artifact-registry.json"
$registry = Get-Json -RelativePath "plans/plan-registry.json"
$schema = Get-Json -RelativePath "plans/schemas/public-plan.schema.json"
$startupSchema = Get-Json -RelativePath "tooling/gnhf/schemas/agent-startup-readiness.schema.json"
$fixturePath = Join-Path $RootPath "tooling/gnhf/fixtures/startup-readiness/state.partial.json"
$fixture = Get-Json -RelativePath "tooling/gnhf/fixtures/startup-readiness/state.partial.json"

if ($contract) {
    Add-Result -Passed ($contract.contractVersion -eq "1.4.0") -Name "contract/version" -FailureMessage "expected contract 1.4.0"
    Add-Result -Passed ($contract.entrypoints.plans -eq "plans/plan-registry.json") -Name "contract/plans-entrypoint" -FailureMessage "public plan entrypoint is missing"
    Add-Result -Passed ($contract.entrypoints.startupReadiness -eq "tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1") -Name "contract/startup-entrypoint" -FailureMessage "startup entrypoint is missing"
    Add-Result -Passed ($contract.entrypoints.appHarness -eq "Test-AppHarness.cmd") -Name "contract/app-harness-entrypoint" -FailureMessage "app harness entrypoint is missing"
    Add-Result -Passed ($contract.appHarness.observer -eq "scripts/Test-AppHarness.ps1") -Name "contract/app-harness-observer" -FailureMessage "app harness observer is missing"
    Add-Result -Passed ($contract.appHarness.runtimeAllowed -eq $false) -Name "contract/app-harness-no-runtime" -FailureMessage "app harness permits runtime"
    Add-Result -Passed ($contract.appHarness.networkAllowed -eq $false) -Name "contract/app-harness-no-network" -FailureMessage "app harness permits network"
    Add-Result -Passed ($contract.appHarness.targetMutationAllowed -eq $false) -Name "contract/app-harness-no-target-mutation" -FailureMessage "app harness permits target mutation"
    Add-Result -Passed (@($contract.canonicalSkills) -contains "public-plan-coordination") -Name "contract/public-plan-skill" -FailureMessage "public plan skill is not registered"
}

if ($manifest) {
    Add-Result -Passed ($manifest.entrypoints.publicPlanRegistry -eq "plans/plan-registry.json") -Name "manifest/plan-registry" -FailureMessage "public plan registry is not wired"
    Add-Result -Passed ($manifest.entrypoints.publicPlanValidator -eq "scripts/Test-PublicPlanContracts.ps1") -Name "manifest/plan-validator" -FailureMessage "public plan validator is not wired"
    Add-Result -Passed ($manifest.entrypoints.startupLauncher -eq "AgentSwitchboard.cmd") -Name "manifest/startup-launcher" -FailureMessage "startup launcher is not wired"
    Add-Result -Passed ($manifest.entrypoints.appCompositionGraph -eq ".ai/harness/app-composition.graph.json") -Name "manifest/app-graph" -FailureMessage "app composition graph is not wired"
    Add-Result -Passed ($manifest.entrypoints.appHarnessValidator -eq "scripts/Test-AppHarness.ps1") -Name "manifest/app-validator" -FailureMessage "app harness validator is not wired"
    Add-Result -Passed ($manifest.startupReadiness.tracked -eq $false) -Name "manifest/startup-untracked" -FailureMessage "startup reports must remain untracked"
    Add-Result -Passed ($manifest.appHarnessValidation.tracked -eq $false) -Name "manifest/app-harness-untracked" -FailureMessage "app harness evidence must remain untracked"
    Add-Result -Passed ($manifest.appHarnessValidation.readOnly -eq $true) -Name "manifest/app-harness-read-only" -FailureMessage "app harness must be read-only"
    Add-Result -Passed ($manifest.publicPlans.tracked -eq $true) -Name "manifest/plans-tracked" -FailureMessage "public plans must be tracked"
}

if ($artifactRegistry) {
    $artifactIds = @($artifactRegistry.artifacts | ForEach-Object { [string]$_.artifactId })
    foreach ($artifactId in @("agent-startup-readiness", "agent-startup-readiness-operator-report", "app-harness-validation-json", "app-harness-validation-report")) {
        Add-Result -Passed ($artifactIds -contains $artifactId) -Name "artifacts/$artifactId" -FailureMessage "required artifact is not registered"
    }
    foreach ($artifact in @($artifactRegistry.artifacts | Where-Object { $_.artifactId -like "agent-startup-readiness*" -or $_.artifactId -like "app-harness-validation*" })) {
        Add-Result -Passed ($artifact.tracked -eq $false) -Name "artifacts/$($artifact.artifactId)/untracked" -FailureMessage "generated evidence must remain untracked"
        Add-Result -Passed ($artifact.sensitivity -eq "local-operational") -Name "artifacts/$($artifact.artifactId)/sensitivity" -FailureMessage "unexpected sensitivity"
    }
}

if ($registry) {
    Add-Result -Passed ($registry.schemaVersion -eq 1) -Name "registry/schema-version" -FailureMessage "expected schemaVersion 1"
    Add-Result -Passed ($registry.policy.planIsNotPullRequest -eq $true) -Name "registry/plan-pr-distinction" -FailureMessage "plan and PR are not distinguished"
    Add-Result -Passed ($registry.policy.machineReadableRequired -eq $true) -Name "registry/machine-readable" -FailureMessage "machine-readable plans are not required"
    $registeredPlanIds = @($registry.plans | ForEach-Object { [string]$_.planId })
    foreach ($requiredPlanId in @("ASB-2026-07-PUBLIC-PLANS-STARTUP", "ASB-2026-07-ONE-COMMAND-HARNESS-PROOF")) {
        Add-Result -Passed ($registeredPlanIds -contains $requiredPlanId) -Name "registry/plan/$requiredPlanId" -FailureMessage "required plan is not indexed"
    }
    foreach ($entry in @($registry.plans)) {
        $planPath = Join-Path $RootPath ([string]$entry.path)
        $summaryPath = Join-Path $RootPath ([string]$entry.summaryPath)
        Add-Result -Passed (Test-Path -LiteralPath $planPath -PathType Leaf) -Name "registry/path/$($entry.planId)" -FailureMessage "plan path is missing"
        Add-Result -Passed (Test-Path -LiteralPath $summaryPath -PathType Leaf) -Name "registry/summary/$($entry.planId)" -FailureMessage "plan summary is missing"
        if (Test-Path -LiteralPath $planPath -PathType Leaf) {
            $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
            Add-Result -Passed ($plan.planId -eq $entry.planId) -Name "plan/id/$($entry.planId)" -FailureMessage "registry and plan IDs differ"
            Add-Result -Passed ($plan.visibility -eq "public") -Name "plan/visibility/$($entry.planId)" -FailureMessage "plan is not public"
            Add-Result -Passed ($plan.repository -eq "EndeavorEverlasting/AgentSwitchboard") -Name "plan/repository/$($entry.planId)" -FailureMessage "repository identity is incorrect"
            Add-Result -Passed (@($plan.tasks).Count -gt 0) -Name "plan/tasks/$($entry.planId)" -FailureMessage "plan has no tasks"
            Add-Result -Passed (@($plan.forbiddenScope).Count -gt 0) -Name "plan/forbidden/$($entry.planId)" -FailureMessage "forbidden scope is empty"
            Add-Result -Passed (-not [string]::IsNullOrWhiteSpace([string]$plan.proof.ceiling)) -Name "plan/proof-ceiling/$($entry.planId)" -FailureMessage "proof ceiling is missing"
            Add-Result -Passed ($plan.delivery.commitRequired -eq $true) -Name "plan/commit-required/$($entry.planId)" -FailureMessage "plan does not require a commit"
            if ($entry.planId -eq "ASB-2026-07-PUBLIC-PLANS-STARTUP") {
                Add-Result -Passed ($plan.delivery.pullRequest.number -eq 34) -Name "plan/pr/$($entry.planId)" -FailureMessage "startup plan is not bound to PR #34"
            }
            elseif ($entry.planId -eq "ASB-2026-07-ONE-COMMAND-HARNESS-PROOF") {
                Add-Result -Passed ($null -ne $plan.delivery.pullRequest -and $plan.delivery.pullRequest.number -gt 0) -Name "plan/pr/$($entry.planId)" -FailureMessage "app harness plan is not bound to its delivery PR"
                Add-Result -Passed ($plan.delivery.branch -eq "feat/one-command-harness-proof") -Name "plan/branch/$($entry.planId)" -FailureMessage "app harness plan branch is incorrect"
                Add-Result -Passed (@($plan.expectedArtifacts) -contains "scripts/Test-AppHarness.ps1") -Name "plan/artifact/$($entry.planId)" -FailureMessage "observer artifact is not declared"
            }
        }
    }
}
if ($schema) {
    Add-Result -Passed ($schema.'$id' -like "*plans/schemas/public-plan.schema.json") -Name "schema/public-plan-id" -FailureMessage "schema ID is incorrect"
    Add-Result -Passed ($schema.additionalProperties -eq $false) -Name "schema/public-plan-closed" -FailureMessage "schema must fail closed"
}
if ($startupSchema) {
    Add-Result -Passed ($startupSchema.'$id' -like "*agent-startup-readiness.schema.json") -Name "schema/startup-id" -FailureMessage "startup schema ID is incorrect"
    Add-Result -Passed ($startupSchema.additionalProperties -eq $false) -Name "schema/startup-closed" -FailureMessage "startup schema must fail closed"
}

$skillPath = Join-Path $RootPath ".ai/skills/public-plan-coordination/SKILL.md"
if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
    $skill = Get-Content -LiteralPath $skillPath -Raw
    foreach ($token in @(
        "id: public-plan-coordination",
        "status: canonical",
        "## Trigger",
        "## Inputs",
        "## Procedure",
        "## Outputs",
        "## Deterministic validation",
        "## Forbidden scope",
        "## Stop and escalate",
        "plan and pull request distinct",
        "same branch or PR",
        "product behavior in deterministic code"
    )) {
        Add-Result -Passed ($skill.Contains($token)) -Name "skill/$token" -FailureMessage "required public-plan skill token is missing"
    }
}

$launcherPath = Join-Path $RootPath "AgentSwitchboard.cmd"
if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
    $launcher = Get-Content -LiteralPath $launcherPath -Raw
    $reportIndex = $launcher.IndexOf("Get-AgentSwitchboardStartupReport.ps1", [StringComparison]::Ordinal)
    $startIndex = $launcher.IndexOf("Start-AgentSwitchboard.ps1", [StringComparison]::Ordinal)
    Add-Result -Passed ($reportIndex -ge 0) -Name "launcher/readiness" -FailureMessage "startup readiness is not invoked"
    Add-Result -Passed ($startIndex -gt $reportIndex) -Name "launcher/order" -FailureMessage "sprint launch occurs before readiness"
    Add-Result -Passed ($launcher.Contains("%ERRORLEVEL%")) -Name "launcher/exit-code" -FailureMessage "native exit code is not preserved"
}

$appHarnessCommandPath = Join-Path $RootPath "Test-AppHarness.cmd"
if (Test-Path -LiteralPath $appHarnessCommandPath -PathType Leaf) {
    $appHarnessCommand = Get-Content -LiteralPath $appHarnessCommandPath -Raw
    Add-Result -Passed ($appHarnessCommand.Contains("scripts\Test-AppHarness.ps1")) -Name "app-harness/command-route" -FailureMessage "root command does not route to observer"
    Add-Result -Passed (-not $appHarnessCommand.Contains("AgentSwitchboard.cmd")) -Name "app-harness/no-app-launch" -FailureMessage "aggregate command launches the application"
    Add-Result -Passed ($appHarnessCommand.Contains("%ERRORLEVEL%")) -Name "app-harness/exit-code" -FailureMessage "aggregate command does not preserve exit code"
}

$startupScript = Join-Path $RootPath "tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1"
if ((Test-Path -LiteralPath $startupScript -PathType Leaf) -and $fixture) {
    $fixtureHashBefore = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agentswitchboard-startup-contract-" + [guid]::NewGuid().ToString("N"))
    [void](New-Item -ItemType Directory -Path $tempRoot -Force)
    try {
        & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $startupScript -StatePath $fixturePath -InstallRoot $tempRoot -OutputRoot $tempRoot | Out-Null
        Add-Result -Passed ($LASTEXITCODE -eq 0) -Name "startup/fixture-exit" -FailureMessage "fixture report exited nonzero"

        $reportPath = Get-ChildItem -LiteralPath $tempRoot -Filter "agent-startup-readiness-*.json" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Add-Result -Passed ($null -ne $reportPath) -Name "startup/report-created" -FailureMessage "JSON report was not created"
        if ($reportPath) {
            $report = Get-Content -LiteralPath $reportPath.FullName -Raw | ConvertFrom-Json
            Add-Result -Passed ($report.schema -eq "agentswitchboard.agent-startup-readiness.v1") -Name "startup/schema" -FailureMessage "wrong report schema"
            Add-Result -Passed ($report.overallStatus -eq "partial") -Name "startup/partial" -FailureMessage "fixture should be partial"
            Add-Result -Passed (@($report.agents).Count -eq 6) -Name "startup/agent-count" -FailureMessage "expected six agent rows"
            $openCode = @($report.agents | Where-Object { $_.agentId -eq "opencode" })[0]
            $deepSeek = @($report.agents | Where-Object { $_.agentId -eq "deepseek" })[0]
            $goose = @($report.agents | Where-Object { $_.agentId -eq "goose" })[0]
            Add-Result -Passed ($openCode.status -eq "adapter-ready") -Name "startup/opencode-ready" -FailureMessage "OpenCode should be adapter-ready"
            Add-Result -Passed ($deepSeek.status -eq "verification-required") -Name "startup/deepseek-proof-boundary" -FailureMessage "DeepSeek must require runtime verification"
            Add-Result -Passed ($goose.status -eq "blocked") -Name "startup/goose-blocked" -FailureMessage "Goose fixture should be blocked"
        }

        $missingState = Join-Path $tempRoot "missing-state.json"
        & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $startupScript -StatePath $missingState -InstallRoot $tempRoot -OutputRoot (Join-Path $tempRoot "missing") | Out-Null
        Add-Result -Passed ($LASTEXITCODE -eq 0) -Name "startup/missing-state-exit" -FailureMessage "missing state should orient rather than crash"
        $missingReportPath = Get-ChildItem -LiteralPath (Join-Path $tempRoot "missing") -Filter "agent-startup-readiness-*.json" -File | Select-Object -First 1
        if ($missingReportPath) {
            $missingReport = Get-Content -LiteralPath $missingReportPath.FullName -Raw | ConvertFrom-Json
            Add-Result -Passed ($missingReport.overallStatus -eq "not-configured") -Name "startup/not-configured" -FailureMessage "missing state should be not-configured"
        }
        else {
            Add-Result -Passed $false -Name "startup/missing-report" -FailureMessage "missing-state report was not created"
        }

        $fixtureHashAfter = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash
        Add-Result -Passed ($fixtureHashBefore -eq $fixtureHashAfter) -Name "startup/fixture-read-only" -FailureMessage "fixture was modified"
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "PUBLIC PLAN AND STARTUP READINESS CONTRACT" -ForegroundColor Cyan
foreach ($pass in $passes) {
    Write-Host "[PASS] $pass" -ForegroundColor Green
}
foreach ($failure in $failures) {
    Write-Host "[FAIL] $failure" -ForegroundColor Red
}
Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) {
    exit 1
}
exit 0
