[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
param(
    [string]$SourceRoot = $PSScriptRoot,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pathsPath = Join-Path $SourceRoot "GnhfFleet.Paths.ps1"
if (-not (Test-Path -LiteralPath $pathsPath -PathType Leaf)) { throw "Path helper library not found: $pathsPath" }
. $pathsPath

$SourceRoot = Resolve-GnhfFleetDirectory -Path $SourceRoot -Description "model catalog and tandem source root"
$InstallRoot = Get-GnhfFleetAbsolutePath -Path $InstallRoot
$files = @(
    "GnhfFleet.Paths.ps1",
    "GnhfModelActivation.ps1",
    "Start-GnhfSprint.ps1",
    "Get-GnhfModelCatalog.ps1",
    "New-GnhfTandemPlan.ps1",
    "Invoke-GnhfTandem.ps1",
    "Install-GnhfModelCatalogTandem.ps1",
    "Test-GnhfModelCatalogAndTandemContracts.ps1",
    "opencode-provider-directory.json",
    "linked-repositories.example.json",
    "MODEL_CATALOG_AND_TANDEM.md"
)
$schemas = @(
    "gnhf-model-catalog.schema.json",
    "gnhf-linked-repositories.schema.json",
    "gnhf-tandem-plan.schema.json",
    "gnhf-handoff-input.schema.json",
    "gnhf-handoff-result.schema.json",
    "gnhf-model-activation.schema.json"
)
foreach ($file in $files) { [void](Resolve-GnhfFleetFile -Path (Join-Path $SourceRoot $file) -Description "model catalog source '$file'") }
foreach ($schema in $schemas) { [void](Resolve-GnhfFleetFile -Path (Join-Path $SourceRoot "schemas\$schema") -Description "model catalog schema '$schema'") }

$validator = Join-Path $SourceRoot "Test-GnhfModelCatalogAndTandemContracts.ps1"
& (Get-Command pwsh -ErrorAction Stop).Source -NoLogo -NoProfile -ExecutionPolicy Bypass -File $validator -RootPath $SourceRoot
if ($LASTEXITCODE -ne 0) { throw "Model catalog and tandem contract validation failed." }

$plan = [ordered]@{
    schemaVersion = "agentswitchboard-model-catalog-tandem-install-plan/v1"
    operation = if ($Apply) { "apply" } else { "plan" }
    sourceRoot = $SourceRoot
    installRoot = $InstallRoot
    files = $files
    schemas = $schemas
    requiredCoreStatePath = Join-Path $InstallRoot "state.json"
    bundledLauncherDependencies = @("GnhfFleet.Paths.ps1", "GnhfModelActivation.ps1", "Start-GnhfSprint.ps1")
    preservesLinkedRepositoryManifest = $true
    automaticAuthentication = $false
    automaticPush = $false
    automaticMerge = $false
}
if (-not $Apply) {
    $plan | ConvertTo-Json -Depth 8
    Write-Host "`nPlan only. Rerun with -Apply to install the model catalog and tandem lane." -ForegroundColor Yellow
    exit 0
}
if (-not $PSCmdlet.ShouldProcess($InstallRoot, "Install AgentSwitchboard model catalog and tandem orchestration")) { exit 0 }

$coreStatePath = Join-Path $InstallRoot "state.json"
if (-not (Test-Path -LiteralPath $coreStatePath -PathType Leaf)) {
    throw "Core GNHF fleet state not found: $coreStatePath. Run the core AgentSwitchboard fleet installer before applying the tandem add-on."
}

[void](Ensure-GnhfFleetDirectory -Path $InstallRoot)
$schemasRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "schemas")
[void](Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "tandem"))
foreach ($file in $files) { [void](Copy-GnhfFleetFile -Source (Join-Path $SourceRoot $file) -Destination (Join-Path $InstallRoot $file)) }
foreach ($schema in $schemas) { [void](Copy-GnhfFleetFile -Source (Join-Path $SourceRoot "schemas\$schema") -Destination (Join-Path $schemasRoot $schema))
}

$linkedExample = Join-Path $InstallRoot "linked-repositories.example.json"
$linkedActive = Join-Path $InstallRoot "linked-repositories.json"
if (-not (Test-Path -LiteralPath $linkedActive -PathType Leaf)) {
    Write-Warning "No active linked-repositories.json was created because the tracked example contains machine-local placeholders. Copy and edit '$linkedExample'."
}
else {
    Write-Host "Preserving existing machine-local linked repository manifest: $linkedActive" -ForegroundColor Green
}

$launchers = [ordered]@{
    refreshCatalog = Join-Path $InstallRoot "Refresh-GnhfModelCatalog.cmd"
    buildPlan = Join-Path $InstallRoot "New-GnhfTandemPlan.cmd"
    startTandem = Join-Path $InstallRoot "Start-GnhfTandem.cmd"
}
@'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-GnhfModelCatalog.ps1" -OutputPath "%~dp0model-catalog.json" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
'@ | Set-Content -LiteralPath $launchers.refreshCatalog -Encoding ascii
@'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-GnhfTandemPlan.ps1" -CatalogPath "%~dp0model-catalog.json" -RepositoriesPath "%~dp0linked-repositories.json" -OutputPath "%~dp0tandem\plan.json" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
'@ | Set-Content -LiteralPath $launchers.buildPlan -Encoding ascii
@'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-GnhfTandem.ps1" -PlanPath "%~dp0tandem\plan.json" -InstallRoot "%~dp0" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
'@ | Set-Content -LiteralPath $launchers.startTandem -Encoding ascii

$summary = [ordered]@{
    schemaVersion = "agentswitchboard-model-catalog-tandem-install/v1"
    installedAt = (Get-Date).ToString("o")
    installRoot = $InstallRoot
    modelCatalogPath = Join-Path $InstallRoot "model-catalog.json"
    linkedRepositoriesPath = $linkedActive
    linkedRepositoriesExamplePath = $linkedExample
    tandemPlanPath = Join-Path $InstallRoot "tandem\plan.json"
    launchers = $launchers
    operatorGuidePath = Join-Path $InstallRoot "MODEL_CATALOG_AND_TANDEM.md"
    coreStatePath = $coreStatePath
    bundledLauncherDependencies = @("GnhfFleet.Paths.ps1", "GnhfModelActivation.ps1", "Start-GnhfSprint.ps1")
    automaticAuthentication = $false
    automaticPush = $false
    automaticMerge = $false
}
$summaryPath = Join-Path $InstallRoot "model-catalog-tandem-install-summary.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
Write-Host "`nModel catalog and tandem orchestration installed: $InstallRoot" -ForegroundColor Green
Write-Host "Summary: $summaryPath"
Write-Host "1. Refresh: $($launchers.refreshCatalog)" -ForegroundColor Cyan
Write-Host "2. Configure: $linkedActive"
Write-Host "3. Plan: $($launchers.buildPlan)" -ForegroundColor Cyan
Write-Host "4. Review: pwsh -File `"$InstallRoot\Invoke-GnhfTandem.ps1`" -PlanPath `"$InstallRoot\tandem\plan.json`" -PlanOnly" -ForegroundColor Cyan
Write-Host "5. Run: $($launchers.startTandem)" -ForegroundColor Cyan
