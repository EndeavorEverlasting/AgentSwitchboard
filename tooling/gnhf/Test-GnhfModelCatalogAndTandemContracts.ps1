[CmdletBinding()]
param([string]$RootPath = $PSScriptRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Test-Contract {
    param([bool]$Condition, [string]$Name, [string]$Message = "contract failed")
    if ($Condition) { [void]$passes.Add($Name); Write-Host "[PASS] $Name" -ForegroundColor Green }
    else { [void]$failures.Add("$Name`: $Message"); Write-Host "[FAIL] $Name - $Message" -ForegroundColor Red }
}

$requiredFiles = @(
    "Get-GnhfModelCatalog.ps1",
    "New-GnhfTandemPlan.ps1",
    "Invoke-GnhfTandem.ps1",
    "Install-GnhfModelCatalogTandem.ps1",
    "opencode-provider-directory.json",
    "linked-repositories.example.json",
    "MODEL_CATALOG_AND_TANDEM.md",
    "schemas/gnhf-model-catalog.schema.json",
    "schemas/gnhf-linked-repositories.schema.json",
    "schemas/gnhf-tandem-plan.schema.json",
    "schemas/gnhf-handoff-input.schema.json",
    "schemas/gnhf-handoff-result.schema.json"
)
foreach ($relative in $requiredFiles) { Test-Contract (Test-Path -LiteralPath (Join-Path $RootPath $relative) -PathType Leaf) "required/$relative" }

foreach ($relative in @("Get-GnhfModelCatalog.ps1", "New-GnhfTandemPlan.ps1", "Invoke-GnhfTandem.ps1", "Install-GnhfModelCatalogTandem.ps1")) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RootPath $relative), [ref]$tokens, [ref]$errors)
    Test-Contract ($errors.Count -eq 0) "parse/$relative" (($errors | ForEach-Object Message) -join "; ")
}

$directory = Get-Content -LiteralPath (Join-Path $RootPath "opencode-provider-directory.json") -Raw | ConvertFrom-Json -Depth 40
$linked = Get-Content -LiteralPath (Join-Path $RootPath "linked-repositories.example.json") -Raw | ConvertFrom-Json -Depth 40
Test-Contract ([string]$directory.schemaVersion -eq "agentswitchboard-opencode-provider-directory/v1") "directory/schema"
Test-Contract (@($directory.providers).Count -ge 48) "directory/provider-expansion" "expected every documented provider plus OpenCode Go"
$providerIds = @($directory.providers | ForEach-Object id)
foreach ($requiredProvider in @("deepseek", "openai", "anthropic", "google-vertex", "github-copilot", "openrouter", "opencode-zen", "opencode-go", "xai", "moonshotai", "minimax", "zai")) {
    Test-Contract ($requiredProvider -in $providerIds) "directory/provider/$requiredProvider"
}
Test-Contract ([string]$linked.schemaVersion -eq "agentswitchboard-linked-repositories/v1") "linked/schema"
$sysAdmin = @($linked.repositories | Where-Object id -eq "sysadminsuite")
Test-Contract ($sysAdmin.Count -eq 1 -and $sysAdmin[0].enabled -eq $true) "linked/sysadminsuite-enabled"
Test-Contract (@($linked.repositories).Count -ge 6) "linked/repository-family"
Test-Contract (@($sysAdmin[0].preferredModels) -contains "deepseek/deepseek-v4-pro") "linked/deepseek-first"
Test-Contract ([int]$linked.maxParallelRepos -ge 2) "linked/tandem-cap"

$catalogText = Get-Content -LiteralPath (Join-Path $RootPath "Get-GnhfModelCatalog.ps1") -Raw
$tandemPlanText = Get-Content -LiteralPath (Join-Path $RootPath "New-GnhfTandemPlan.ps1") -Raw
$tandemRunText = Get-Content -LiteralPath (Join-Path $RootPath "Invoke-GnhfTandem.ps1") -Raw
$installerText = Get-Content -LiteralPath (Join-Path $RootPath "Install-GnhfModelCatalogTandem.ps1") -Raw
Test-Contract ($catalogText.Contains('opencode') -and $catalogText.Contains('models') -and $catalogText.Contains('--refresh')) "catalog/runtime-refresh"
Test-Contract ($catalogText.Contains('auth') -and $catalogText.Contains('list')) "catalog/auth-inventory"
Test-Contract ($catalogText.Contains('Move-Item') -and $catalogText.Contains('.tmp')) "catalog/atomic-write"
Test-Contract (-not $catalogText.Contains('DEEPSEEK_API_KEY') -and -not $catalogText.Contains('OPENAI_API_KEY') -and -not $catalogText.Contains('sk-')) "catalog/no-secret-handling"
Test-Contract ($tandemPlanText.Contains('same repository path') -and $tandemPlanText.Contains('dirty')) "plan/worktree-collision-guards"
Test-Contract ($tandemPlanText.Contains('preferredModels') -and $tandemPlanText.Contains('preferredProviders')) "plan/model-preferences"
Test-Contract ($tandemPlanText.Contains('MaxCatalogAgeMinutes') -and $tandemPlanText.Contains('authenticationStatus')) "plan/fresh-authenticated-catalog"
Test-Contract ($tandemPlanText.Contains('executionObjectivePath') -and $tandemPlanText.Contains('originalObjectivePath')) "plan/generated-objective-handoff"
Test-Contract ($tandemPlanText.Contains('handoff-input/v1') -and $tandemPlanText.Contains('expectedResultPath')) "plan/clear-handoffs"
Test-Contract ($tandemRunText.Contains('Start-GnhfSprint.ps1')) "runtime/reuses-repo-launcher"
Test-Contract ($tandemRunText.Contains('MaxParallelRepos') -and $tandemRunText.Contains('Start-TandemLane')) "runtime/parallel-orchestration"
Test-Contract ($tandemRunText.Contains('dependsOn') -and $tandemRunText.Contains('blocked-by-dependency')) "runtime/dependency-handoffs"
Test-Contract ($tandemRunText.Contains('AGENTSWITCHBOARD_HANDOFF_INPUT') -and $tandemRunText.Contains('AGENTSWITCHBOARD_HANDOFF_RESULT')) "runtime/handoff-environment"
Test-Contract ($tandemRunText.Contains('OPENCODE_CONFIG_CONTENT') -and $tandemRunText.Contains('small_model')) "runtime/exact-opencode-model-application"
Test-Contract ($tandemRunText.Contains('runtimeModelConfiguration')) "runtime/model-configuration-evidence"
Test-Contract ($tandemRunText.Contains('automaticPush = $false') -and $tandemRunText.Contains('automaticMerge = $false')) "runtime/no-automatic-integration"
Test-Contract ($tandemRunText.Contains('process.Kill($true)')) "runtime/bounded-process-tree"
Test-Contract ($installerText.Contains('Start-GnhfSprint.ps1') -and $installerText.Contains('GnhfFleet.Paths.ps1') -and $installerText.Contains('GnhfModelActivation.ps1')) "installer/core-launcher-dependencies"
Test-Contract ($installerText.Contains('Core GNHF fleet state not found') -and $installerText.Contains('state.json')) "installer/core-state-gate"

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("AgentSwitchboard-TandemContracts-" + [guid]::NewGuid().ToString("N"))
try {
    [void](New-Item -ItemType Directory -Path $tempRoot -Force)
    $catalogPath = Join-Path $tempRoot "catalog.json"
    $manifestPath = Join-Path $tempRoot "linked.json"
    $planPath = Join-Path $tempRoot "plan.json"
    [ordered]@{
        schemaVersion = "agentswitchboard-gnhf-model-catalog/v1"
        capturedAt = (Get-Date).ToString("o")
        source = [ordered]@{ command = "opencode models --refresh"; refresh = $true; providerDirectoryHash = ("A" * 64) }
        authentication = [ordered]@{ command = "opencode auth list"; reportedProviderIds = @("deepseek", "openai") }
        providers = @(
            [ordered]@{ providerId = "deepseek"; displayName = "DeepSeek"; documented = $true; modelCount = 1; authenticationStatus = "reported" },
            [ordered]@{ providerId = "openai"; displayName = "OpenAI"; documented = $true; modelCount = 1; authenticationStatus = "reported" }
        )
        models = @(
            [ordered]@{ fullId = "deepseek/deepseek-v4-pro"; providerId = "deepseek"; modelId = "deepseek-v4-pro"; available = $true; agentAdapters = @("opencode"); routingTags = @("runtime-discovered") },
            [ordered]@{ fullId = "openai/gpt-5"; providerId = "openai"; modelId = "gpt-5"; available = $true; agentAdapters = @("opencode"); routingTags = @("runtime-discovered") }
        )
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
    [ordered]@{
        schemaVersion = "agentswitchboard-linked-repositories/v1"
        maxParallelRepos = 2
        providerPreference = @("deepseek", "openai")
        repositories = @(
            [ordered]@{ id = "sysadminsuite"; enabled = $true; repository = "EndeavorEverlasting/SysAdminSuite"; path = (Join-Path $tempRoot "sas"); objectivePath = (Join-Path $tempRoot "sas.md"); agent = "opencode"; preferredProviders = @("deepseek"); preferredModels = @("deepseek/deepseek-v4-pro"); maxIterations = 2; maxTokens = 50000; timeoutMinutes = 30; stopWhen = "committed and validated"; dependsOn = @(); ownedScope = @("tests"); forbiddenScope = @("credentials") },
            [ordered]@{ id = "foundry"; enabled = $true; repository = "EndeavorEverlasting/foundry"; path = (Join-Path $tempRoot "foundry"); objectivePath = (Join-Path $tempRoot "foundry.md"); agent = "opencode"; preferredProviders = @("openai"); preferredModels = @(); maxIterations = 2; maxTokens = 50000; timeoutMinutes = 30; stopWhen = "committed and validated"; dependsOn = @("sysadminsuite"); ownedScope = @("analysis"); forbiddenScope = @("credentials") }
        )
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
    & (Join-Path $RootPath "New-GnhfTandemPlan.ps1") -CatalogPath $catalogPath -RepositoriesPath $manifestPath -OutputPath $planPath -SkipRepositoryValidation
    Test-Contract (Test-Path -LiteralPath $planPath -PathType Leaf) "fixture/plan-created"
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 40
    Test-Contract (@($plan.lanes).Count -eq 2) "fixture/two-lanes"
    Test-Contract ([string]$plan.lanes[0].modelId -eq "deepseek/deepseek-v4-pro") "fixture/deepseek-sysadmin"
    Test-Contract ([string]$plan.lanes[1].modelId -eq "openai/gpt-5") "fixture/model-distribution"
    Test-Contract ((Test-Path -LiteralPath $plan.lanes[0].handoff.inputPath) -and (Test-Path -LiteralPath $plan.lanes[1].handoff.inputPath)) "fixture/handoff-inputs"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Result: $($passes.Count) passed / $($failures.Count) failed" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
Write-Host "Result: $($passes.Count) passed / 0 failed" -ForegroundColor Green
exit 0
