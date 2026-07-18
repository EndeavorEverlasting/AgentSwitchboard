[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$RequestedNpmVersion,
    [hashtable]$InjectedNpmFacts,
    [hashtable]$InjectedInstalledRuntime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 is required."
}

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) {
    throw "AgentSwitchboard repository not found from installer: $RepoRoot"
}

# Directory first: installation and validation begin only after entering AgentSwitchboard.
Set-Location -LiteralPath $RepoRoot

. (Join-Path $PSScriptRoot "Gnhf.Capability.ps1")
. (Join-Path $PSScriptRoot "Gnhf.Process.ps1")

function Refresh-ProviderRoutePath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath;$(Join-Path $env:APPDATA 'npm');$(Join-Path $HOME '.local\bin')"
}

function Test-ProviderRouteLaunchersPresent {
    param([Parameter(Mandatory)][string]$Root)
    foreach ($relative in @(
        "Start-ProviderRoutedGnhfSprint.ps1",
        "Gnhf.Process.ps1",
        "Gnhf.Capability.ps1",
        "agent-switchboard-provider.cmd"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $relative) -PathType Leaf)) {
            return $false
        }
    }
    return $true
}

function Install-ProviderRouteLaunchersStaged {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$StageRoot
    )

    [void](New-Item -ItemType Directory -Path $StageRoot -Force)
    foreach ($file in @("Gnhf.Process.ps1", "Gnhf.Capability.ps1", "Start-ProviderRoutedGnhfSprint.ps1")) {
        $source = Join-Path $SourceRoot $file
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Required provider-route file is missing: $source"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $StageRoot $file) -Force
    }

    $launcher = @'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-ProviderRoutedGnhfSprint.ps1" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
'@
    Set-Content -LiteralPath (Join-Path $StageRoot "agent-switchboard-provider.cmd") -Value $launcher -Encoding ascii
}

function Promote-ProviderRouteLaunchers {
    param(
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)][string]$InstallRoot
    )
    [void](New-Item -ItemType Directory -Path $InstallRoot -Force)
    foreach ($file in @("Gnhf.Process.ps1", "Gnhf.Capability.ps1", "Start-ProviderRoutedGnhfSprint.ps1", "agent-switchboard-provider.cmd")) {
        Copy-Item -LiteralPath (Join-Path $StageRoot $file) -Destination (Join-Path $InstallRoot $file) -Force
    }
}

$npmFacts = Get-GnhfNpmDistributionFacts -Injected $InjectedNpmFacts
$installed = Get-GnhfInstalledRuntimeFacts -Injected $InjectedInstalledRuntime
$launchersPresent = Test-ProviderRouteLaunchersPresent -Root $InstallRoot
$matrix = Test-ProviderRouteCapabilityMatrix `
    -InstalledRuntime $installed `
    -LaunchersPresent $launchersPresent `
    -OpenCodeModelSelectionAvailable $true
$plan = Select-GnhfDistributionPlan `
    -NpmFacts $npmFacts `
    -InstalledRuntime $installed `
    -CapabilityMatrix $matrix `
    -RequestedNpmVersion $RequestedNpmVersion

Write-Host "`n=== Provider-routed GNHF capability install plan ===" -ForegroundColor Cyan
Write-Host "Repository:        $RepoRoot"
Write-Host "Install root:      $InstallRoot"
Write-Host "npm latest:        $(if ($npmFacts.npmLatest) { $npmFacts.npmLatest } else { '<unavailable>' })"
Write-Host "Installed GNHF:    $(if ($installed.version) { $installed.version } else { '<unavailable>' })"
Write-Host "GNHF --model CLI:  $($installed.cliFlags.model)"
Write-Host "Model authority:   OpenCode (OPENCODE_CONFIG_CONTENT)"
Write-Host "Missing caps:      $(if ($matrix.missing.Count) { $matrix.missing -join ', ' } else { '<none>' })"
Write-Host "Distribution:      $($plan.action) / $($plan.selectedSource) / $($plan.selectedPackageSpec)"
Write-Host "Reason:            $($plan.reason)"
Write-Host "Apply:             $([bool]$Apply)"

if (-not $Apply) {
    Write-Host "`nPlan only. Rerun with -Apply to stage launchers and optionally install a published runtime." -ForegroundColor Yellow
    return
}

$backupRoot = Join-Path $InstallRoot ("backups\provider-route-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"))
$stageRoot = Join-Path $InstallRoot ("staging\provider-route-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"))
$statePath = Join-Path $InstallRoot "state.json"
$capabilityPath = Join-Path $InstallRoot "gnhf-runtime-capability.json"
$installResultPath = Join-Path $InstallRoot "provider-route-install-result.json"
$rollback = "Restore fleet files from $backupRoot if present, then rerun Repair-ProviderRoutedGnhf.cmd."

$installResult = [ordered]@{
    schema = "agentswitchboard.provider-route-install-result.v1"
    startedUtc = [DateTime]::UtcNow.ToString("o")
    completedUtc = $null
    status = "started"
    backupRoot = $backupRoot
    stageRoot = $stageRoot
    distributionAction = $plan.action
    selectedPackageSpec = $plan.selectedPackageSpec
    failureClass = $null
    error = $null
    rollbackInstructions = $rollback
}

try {
    [void](New-Item -ItemType Directory -Path $backupRoot -Force)
    [void](New-Item -ItemType Directory -Path $stageRoot -Force)

    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        Copy-Item -LiteralPath $statePath -Destination (Join-Path $backupRoot "state.json") -Force
        $timestamped = Join-Path $InstallRoot ("state.json.{0}.bak" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        Copy-Item -LiteralPath $statePath -Destination $timestamped -Force
    }
    if (Test-Path -LiteralPath $capabilityPath -PathType Leaf) {
        Copy-Item -LiteralPath $capabilityPath -Destination (Join-Path $backupRoot "gnhf-runtime-capability.json") -Force
    }
    foreach ($file in @("Start-ProviderRoutedGnhfSprint.ps1", "Gnhf.Process.ps1", "Gnhf.Capability.ps1", "agent-switchboard-provider.cmd")) {
        $existing = Join-Path $InstallRoot $file
        if (Test-Path -LiteralPath $existing -PathType Leaf) {
            Copy-Item -LiteralPath $existing -Destination (Join-Path $backupRoot $file) -Force
        }
    }

    # Always stage launchers, even when runtime replacement is unnecessary.
    Install-ProviderRouteLaunchersStaged -SourceRoot $PSScriptRoot -StageRoot $stageRoot

    if ($plan.action -eq "blocked") {
        $installResult.failureClass = $(if ($plan.failureClass) { $plan.failureClass } else { "BLOCKED_DISTRIBUTION_UNAVAILABLE" })
        throw $plan.reason
    }

    if ($plan.installFromNpm -and $plan.selectedPackageSpec) {
        $npm = Get-Command npm -ErrorAction Stop
        Write-Host "Installing published package $($plan.selectedPackageSpec)..." -ForegroundColor Yellow
        & $npm.Source install --global $plan.selectedPackageSpec
        if ($LASTEXITCODE -ne 0) {
            throw "npm failed to install $($plan.selectedPackageSpec). Existing runtime was preserved; staged launchers were not promoted."
        }
        Refresh-ProviderRoutePath
        $installed = Get-GnhfInstalledRuntimeFacts
    }

    if (-not $installed.commandPath -or -not $installed.version) {
        throw "GNHF executable was not observed after install planning."
    }

    # Launchers are staged; treat them as present for readiness after promotion.
    $matrix = Test-ProviderRouteCapabilityMatrix `
        -InstalledRuntime $installed `
        -LaunchersPresent $true `
        -OpenCodeModelSelectionAvailable $true

    if ($matrix.runtimeMissing.Count -gt 0) {
        $installResult.failureClass = "BLOCKED_RUNTIME_CAPABILITY"
        throw "Staged runtime is missing required capabilities: $($matrix.runtimeMissing -join ', '). Existing fleet launchers were not overwritten."
    }

    Promote-ProviderRouteLaunchers -StageRoot $stageRoot -InstallRoot $InstallRoot

    try {
        $openCodeNative = Resolve-OpenCodeNativeExecutable
        $null = Set-GnhfOpenCodeNativePathOverride -OpenCodeExePath $openCodeNative
    }
    catch {
        Write-Host "OpenCode native path pin skipped: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $state.gnhf.commandPath = $installed.commandPath
        $state.gnhf.versionOutput = $installed.version.ToString()
        foreach ($pair in @(
            @{ Name = "providerRouteCapabilitySchema"; Value = "agentswitchboard.gnhf-runtime-capability.v1" },
            @{ Name = "gnhfCliModelFlag"; Value = [bool]$installed.cliFlags.model },
            @{ Name = "modelSelectionAuthority"; Value = "opencode" },
            @{ Name = "selectedPackageSpec"; Value = $plan.selectedPackageSpec }
        )) {
            if (-not $state.gnhf.PSObject.Properties[$pair.Name]) {
                $state.gnhf | Add-Member -NotePropertyName $pair.Name -NotePropertyValue $pair.Value
            }
            else {
                $state.gnhf.($pair.Name) = $pair.Value
            }
        }
        # Remove legacy misleading claim that GNHF --model was verified when it was not.
        if ($state.gnhf.PSObject.Properties["modelFlagVerified"]) {
            $state.gnhf.modelFlagVerified = [bool]$installed.cliFlags.model
        }
        if ($state.gnhf.PSObject.Properties["requiredProviderRouteVersion"]) {
            $state.gnhf.requiredProviderRouteVersion = $null
        }
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
    }

    $capability = New-GnhfRuntimeCapabilityDocument `
        -InstallRoot $InstallRoot `
        -NpmFacts $npmFacts `
        -InstalledRuntime $installed `
        -CapabilityMatrix $matrix `
        -DistributionPlan $plan `
        -RollbackInstructions $rollback
    $capability | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $capabilityPath -Encoding utf8NoBOM

    # Never claim readiness if the capability document was not written.
    if (-not (Test-Path -LiteralPath $capabilityPath -PathType Leaf)) {
        throw "Capability document was not written."
    }

    $installResult.status = "succeeded"
    $installResult.completedUtc = [DateTime]::UtcNow.ToString("o")
    $installResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $installResultPath -Encoding utf8NoBOM

    Write-Host "`nProvider-routed GNHF installed (capability-driven)." -ForegroundColor Green
    Write-Host "GNHF:              $($installed.version)"
    Write-Host "Package:           $($plan.selectedPackageSpec)"
    Write-Host "GNHF --model CLI:  $($installed.cliFlags.model)"
    Write-Host "Model authority:   OpenCode"
    Write-Host "Capability doc:    $capabilityPath"
    Write-Host "Launcher:          $(Join-Path $InstallRoot 'agent-switchboard-provider.cmd')"
    Write-Host "Backup:            $backupRoot"
}
catch {
    $installResult.status = "failed"
    $installResult.completedUtc = [DateTime]::UtcNow.ToString("o")
    $installResult.error = $_.Exception.Message
    if (-not $installResult.failureClass) {
        $installResult.failureClass = $(if ($plan.failureClass) { $plan.failureClass } else { "BLOCKED_RUNTIME_CAPABILITY" })
    }

    # Do not leave a ready capability document after failure.
    if (Test-Path -LiteralPath $capabilityPath -PathType Leaf) {
        $failedCapBackup = Join-Path $backupRoot "gnhf-runtime-capability.failed.json"
        Move-Item -LiteralPath $capabilityPath -Destination $failedCapBackup -Force -ErrorAction SilentlyContinue
    }

    $failedMatrix = Test-ProviderRouteCapabilityMatrix `
        -InstalledRuntime $installed `
        -LaunchersPresent (Test-ProviderRouteLaunchersPresent -Root $InstallRoot) `
        -OpenCodeModelSelectionAvailable $true
    $failedDoc = New-GnhfRuntimeCapabilityDocument `
        -InstallRoot $InstallRoot `
        -NpmFacts $npmFacts `
        -InstalledRuntime $installed `
        -CapabilityMatrix $failedMatrix `
        -DistributionPlan ([pscustomobject]@{ selectedSource = "none"; selectedPackageSpec = $plan.selectedPackageSpec }) `
        -FailureClass $installResult.failureClass `
        -RollbackInstructions $rollback
    $failedDoc.ready = $false
    $failedDocPath = Join-Path $InstallRoot "gnhf-runtime-capability.last-failure.json"
    $failedDoc | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $failedDocPath -Encoding utf8NoBOM
    $installResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $installResultPath -Encoding utf8NoBOM

    Write-Error -ErrorRecord $_ -ErrorAction Continue
    Write-Host "Install failed. Existing runtime preserved when possible." -ForegroundColor Yellow
    Write-Host "Rollback: $rollback" -ForegroundColor Cyan
    Write-Host "Failure evidence: $failedDocPath" -ForegroundColor Cyan
    exit 1
}
finally {
    if (Test-Path -LiteralPath $stageRoot -PathType Container) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
