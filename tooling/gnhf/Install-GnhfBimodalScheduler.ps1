[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
param(
    [string]$SourceRoot = $PSScriptRoot,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$DefaultRepoPath,
    [string]$ObjectivePath,
    [string]$UsageSnapshotPath,
    [switch]$ResetManifest,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pathHelpersPath = Join-Path $SourceRoot "GnhfFleet.Paths.ps1"
if (-not (Test-Path -LiteralPath $pathHelpersPath -PathType Leaf)) {
    throw "Path helper library not found: $pathHelpersPath"
}
. $pathHelpersPath

$SourceRoot = Resolve-GnhfFleetDirectory -Path $SourceRoot -Description "bimodal scheduler source root"
$InstallRoot = Get-GnhfFleetAbsolutePath -Path $InstallRoot
$planMode = -not $Apply

$requiredSourceFiles = @(
    "GnhfFleet.Paths.ps1",
    "Start-GnhfSprint.ps1",
    "GnhfBimodal.Policy.ps1",
    "GnhfBimodal.Policy.psm1",
    "Invoke-GnhfBimodalScheduler.ps1",
    "Test-GnhfBimodalSchedulerContracts.ps1",
    "gnhf-bimodal.example.json",
    "README.md"
)
$schemaFiles = @(
    "gnhf-usage-snapshot.schema.json",
    "gnhf-routing-decision.schema.json",
    "gnhf-bimodal-run.schema.json"
)
$fixtureFiles = @(
    "gnhf-usage-completion.json",
    "gnhf-usage-efficiency.json"
)

foreach ($relativePath in $requiredSourceFiles) {
    [void](Resolve-GnhfFleetFile -Path (Join-Path $SourceRoot $relativePath) -Description "scheduler source file '$relativePath'")
}
foreach ($fileName in $schemaFiles) {
    [void](Resolve-GnhfFleetFile -Path (Join-Path $SourceRoot "schemas\$fileName") -Description "scheduler schema '$fileName'")
}
foreach ($fileName in $fixtureFiles) {
    [void](Resolve-GnhfFleetFile -Path (Join-Path $SourceRoot "fixtures\$fileName") -Description "scheduler fixture '$fileName'")
}

$validator = Join-Path $SourceRoot "Test-GnhfBimodalSchedulerContracts.ps1"
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
& $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $validator -RootPath $SourceRoot
if ($LASTEXITCODE -ne 0) {
    throw "Bimodal scheduler contract validation failed."
}

$manifestTemplatePath = Join-Path $SourceRoot "gnhf-bimodal.example.json"
$manifestTargetPath = Join-Path $InstallRoot "gnhf-bimodal.json"
$manifestExampleTargetPath = Join-Path $InstallRoot "gnhf-bimodal.example.json"
$launcherPath = Join-Path $InstallRoot "Start-GnhfBimodal.cmd"

$plan = [ordered]@{
    schemaVersion = 1
    operation = if ($Apply) { "apply" } else { "plan" }
    sourceRoot = $SourceRoot
    installRoot = $InstallRoot
    files = @($requiredSourceFiles)
    schemas = @($schemaFiles)
    fixtures = @($fixtureFiles)
    activeManifestPath = $manifestTargetPath
    manifestExists = Test-Path -LiteralPath $manifestTargetPath -PathType Leaf
    resetManifest = [bool]$ResetManifest
    launcherPath = $launcherPath
    valuesSupplied = [ordered]@{
        repoPath = [bool]$DefaultRepoPath
        objectivePath = [bool]$ObjectivePath
        usageSnapshotPath = [bool]$UsageSnapshotPath
    }
}

if ($planMode) {
    $plan | ConvertTo-Json -Depth 8
    Write-Host "`nPlan only. Rerun with -Apply to install the scheduler." -ForegroundColor Yellow
    exit 0
}

if (-not $PSCmdlet.ShouldProcess($InstallRoot, "Install or repair AgentSwitchboard GNHF bimodal scheduler")) {
    exit 0
}

[void](Ensure-GnhfFleetDirectory -Path $InstallRoot)
$schemasRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "schemas")
$fixturesRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "fixtures")
[void](Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "bimodal-runs"))

foreach ($relativePath in $requiredSourceFiles) {
    [void](Copy-GnhfFleetFile -Source (Join-Path $SourceRoot $relativePath) -Destination (Join-Path $InstallRoot $relativePath))
}
foreach ($fileName in $schemaFiles) {
    [void](Copy-GnhfFleetFile -Source (Join-Path $SourceRoot "schemas\$fileName") -Destination (Join-Path $schemasRoot $fileName))
}
foreach ($fileName in $fixtureFiles) {
    [void](Copy-GnhfFleetFile -Source (Join-Path $SourceRoot "fixtures\$fileName") -Destination (Join-Path $fixturesRoot $fileName))
}
[void](Copy-GnhfFleetFile -Source $manifestTemplatePath -Destination $manifestExampleTargetPath)

$allManifestValuesSupplied = $DefaultRepoPath -and $ObjectivePath -and $UsageSnapshotPath
if ($allManifestValuesSupplied) {
    $resolvedRepoPath = Resolve-GnhfFleetDirectory -Path $DefaultRepoPath -Description "default scheduler repository"
    $resolvedObjectivePath = Resolve-GnhfFleetFile -Path $ObjectivePath -Description "scheduler objective"
    $resolvedUsagePath = Resolve-GnhfFleetFile -Path $UsageSnapshotPath -Description "scheduler usage snapshot"

    if ($ResetManifest -or -not (Test-Path -LiteralPath $manifestTargetPath -PathType Leaf)) {
        $manifestText = Get-Content -LiteralPath $manifestTemplatePath -Raw
        $manifestText = $manifestText.Replace("__REPO_PATH__", $resolvedRepoPath.Replace("\", "\\"))
        $manifestText = $manifestText.Replace("__OBJECTIVE_PATH__", $resolvedObjectivePath.Replace("\", "\\"))
        $manifestText = $manifestText.Replace("__USAGE_SNAPSHOT_PATH__", $resolvedUsagePath.Replace("\", "\\"))
        $defaultWorktreeRoot = "$resolvedRepoPath-agent-switchboard-worktrees"
        $manifestText = $manifestText.Replace("__WORKTREE_ROOT__", $defaultWorktreeRoot.Replace("\", "\\"))
        Set-Content -LiteralPath $manifestTargetPath -Value $manifestText -Encoding utf8NoBOM
        Write-Host "Wrote active bimodal manifest: $manifestTargetPath" -ForegroundColor Green
    }
    else {
        Write-Host "Preserving existing customized bimodal manifest: $manifestTargetPath" -ForegroundColor Green
    }
}
elseif ($ResetManifest) {
    throw "-ResetManifest requires -DefaultRepoPath, -ObjectivePath, and -UsageSnapshotPath so placeholders are not installed as an active configuration."
}
elseif (-not (Test-Path -LiteralPath $manifestTargetPath -PathType Leaf)) {
    Write-Warning "No active bimodal manifest was created because repository, objective, and usage snapshot paths were not all supplied. Copy and edit '$manifestExampleTargetPath' before execution."
}

$launcherContent = @'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-GnhfBimodalScheduler.ps1" -ConfigPath "%~dp0gnhf-bimodal.json" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
'@
Set-Content -LiteralPath $launcherPath -Value $launcherContent -Encoding ascii

$installedValidator = Join-Path $InstallRoot "Test-GnhfBimodalSchedulerContracts.ps1"
& $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installedValidator -RootPath $InstallRoot
if ($LASTEXITCODE -ne 0) {
    throw "Installed bimodal scheduler validation failed."
}

$summary = [ordered]@{
    schemaVersion = 1
    installedAt = (Get-Date).ToString("o")
    installRoot = $InstallRoot
    activeManifestPath = if (Test-Path -LiteralPath $manifestTargetPath -PathType Leaf) { $manifestTargetPath } else { $null }
    manifestExamplePath = $manifestExampleTargetPath
    launcherPath = $launcherPath
    defaultMode = "maximize-sprint-completion"
    secondaryMode = "maximize-token-efficiency"
    automaticPush = $false
    automaticMerge = $false
}
$summaryPath = Join-Path $InstallRoot "bimodal-install-summary.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM

Write-Host "`nBimodal scheduler installed: $InstallRoot" -ForegroundColor Green
Write-Host "Summary: $summaryPath"
if ($summary.activeManifestPath) {
    Write-Host "Plan: pwsh -File `"$InstallRoot\Invoke-GnhfBimodalScheduler.ps1`" -ConfigPath `"$manifestTargetPath`" -PlanOnly" -ForegroundColor Cyan
    Write-Host "Run:  `"$launcherPath`"" -ForegroundColor Cyan
}
