[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
param(
    [string]$SourceRoot = $PSScriptRoot,
    [string]$ManifestPath = (Join-Path $PSScriptRoot "tmux-gnhf-workstation.example.json"),
    [switch]$Apply,
    [switch]$RunAfterInstall,
    [switch]$CreateDesktopShortcut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "This installer requires PowerShell 7. Open pwsh and rerun."
}

function Get-AbsolutePath {
    param([Parameter(Mandatory)][string]$Path)
    [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
}

function Write-AtomicJson {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temp -Encoding utf8NoBOM
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

$SourceRoot = Get-AbsolutePath $SourceRoot
$ManifestPath = Get-AbsolutePath $ManifestPath
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Manifest not found: $ManifestPath"
}
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw "Unsupported manifest schemaVersion: $($manifest.schemaVersion)." }
$workspaceInstallRoot = Get-AbsolutePath ([string]$manifest.workspace.installRoot)

$sourceRepo = @(& git -C $SourceRoot rev-parse --show-toplevel 2>&1)
$sourceRepoExit = $LASTEXITCODE
if ($sourceRepoExit -ne 0 -or -not $sourceRepo) {
    throw "SourceRoot is not inside an AgentSwitchboard Git checkout: $SourceRoot"
}
$sourceRepoPath = ([string]$sourceRepo[0]).Trim()
$sourceStatus = @(& git -C $sourceRepoPath status --short 2>&1)
$sourceStatusExit = $LASTEXITCODE
$sourceStatus = @($sourceStatus | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($sourceStatusExit -ne 0 -or $sourceStatus.Count -gt 0) {
    throw "The AgentSwitchboard source checkout must be clean before installing the runtime proof add-on."
}
$sourceHeadOutput = @(& git -C $sourceRepoPath rev-parse HEAD 2>&1)
if ($LASTEXITCODE -ne 0 -or -not $sourceHeadOutput) { throw "Unable to read the source HEAD." }
$sourceHead = ([string]$sourceHeadOutput[0]).Trim()
if ($sourceHead -notmatch '^[0-9a-fA-F]{40}$') { throw "Source HEAD is not a valid 40-character Git commit: '$sourceHead'." }
$sourceBranchOutput = @(& git -C $sourceRepoPath branch --show-current 2>&1)
if ($LASTEXITCODE -ne 0) { throw "Unable to read the source branch." }
$sourceBranch = if ($sourceBranchOutput.Count -gt 0) { ([string]$sourceBranchOutput[0]).Trim() } else { "" }
$sourceAttached = -not [string]::IsNullOrWhiteSpace($sourceBranch)
if (-not $sourceAttached) {
    if ($Apply) { throw "Detached source checkout is not allowed when applying the runtime proof add-on." }
    $sourceBranch = "detached-plan-only"
}

$sourceFiles = [ordered]@{
    proofScript = Join-Path $SourceRoot "Invoke-WindowsWorkstationLiveProof.ps1"
    commonModule = Join-Path $SourceRoot "WindowsWorkstationLiveProof.Common.psm1"
    sessionProof = Join-Path $SourceRoot "Invoke-WindowsWorkstationSessionProof.ps1"
    gnhfProof = Join-Path $SourceRoot "Invoke-WindowsWorkstationGnhfProof.ps1"
    contractValidator = Join-Path $SourceRoot "Test-WindowsWorkstationLiveProofContracts.ps1"
    schema = Join-Path $SourceRoot "schemas\windows-workstation-live-proof.schema.json"
    manifest = $ManifestPath
}
foreach ($entry in $sourceFiles.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Required source file is missing: $($entry.Value)"
    }
}

$validatorArgs = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", $sourceFiles.contractValidator,
    "-RootPath", $SourceRoot
)
& (Get-Command pwsh.exe -ErrorAction Stop).Source @validatorArgs
if ($LASTEXITCODE -ne 0) { throw "Windows workstation live-proof contracts failed." }

$coreStart = Join-Path $workspaceInstallRoot "Start-TmuxGnhfWorkspace.ps1"
$coreStatus = Join-Path $workspaceInstallRoot "Get-TmuxGnhfWorkspaceStatus.ps1"
$coreSummary = Join-Path $workspaceInstallRoot "state\setup-summary.json"
$plan = [ordered]@{
    schemaVersion = "agentswitchboard-windows-workstation-live-proof-install-plan/v1"
    operation = if ($Apply) { "apply" } else { "plan" }
    sourceRepoPath = $sourceRepoPath
    sourceBranch = $sourceBranch
    sourceAttached = $sourceAttached
    sourceHead = $sourceHead
    manifestPath = $ManifestPath
    workspaceInstallRoot = $workspaceInstallRoot
    requiredCoreFiles = @($coreStart, $coreStatus, $coreSummary)
    requiredCoreSummary = [ordered]@{
        schemaVersion = 1
        status = "completed"
        distribution = [string]$manifest.distribution
        sessionName = [string]$manifest.workspace.sessionName
        installRoot = $workspaceInstallRoot
    }
    installedFiles = @(
        "Invoke-WindowsWorkstationLiveProof.ps1",
        "WindowsWorkstationLiveProof.Common.psm1",
        "Invoke-WindowsWorkstationSessionProof.ps1",
        "Invoke-WindowsWorkstationGnhfProof.ps1",
        "Test-WindowsWorkstationLiveProofContracts.ps1",
        "tmux-gnhf-workstation.json",
        "schemas\windows-workstation-live-proof.schema.json",
        "windows-workstation-live-proof.config.json",
        "Run-WindowsWorkstationLiveProof.cmd"
    )
    runAfterInstall = [bool]$RunAfterInstall
    automaticAuthentication = $false
    automaticPush = $false
    personalDataMutation = $false
}

if (-not $Apply) {
    $plan | ConvertTo-Json -Depth 12
    Write-Host "`nPlan only. Rerun with -Apply after the core tmux/GNHF workspace has been installed." -ForegroundColor Yellow
    exit 0
}

if (-not $PSCmdlet.ShouldProcess($workspaceInstallRoot, "Install Windows workstation live runtime proof lane")) { exit 0 }
foreach ($required in @($coreStart, $coreStatus, $coreSummary)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Core workstation dependency is missing: $required. Run Setup-TmuxGnhfWorkspace.cmd before installing this proof lane."
    }
}

try {
    $coreSetup = Get-Content -LiteralPath $coreSummary -Raw | ConvertFrom-Json -Depth 20
    $summaryInstallRoot = Get-AbsolutePath ([string]$coreSetup.installRoot)
    $trimChars = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $expectedInstallRoot = $workspaceInstallRoot.TrimEnd($trimChars)
    $actualInstallRoot = $summaryInstallRoot.TrimEnd($trimChars)
    if ($coreSetup.schemaVersion -ne 1) { throw "schemaVersion must be 1" }
    if ([string]$coreSetup.status -ne "completed") { throw "status must be completed" }
    if ([string]$coreSetup.distribution -ne [string]$manifest.distribution) { throw "distribution does not match the local workstation manifest" }
    if ([string]$coreSetup.sessionName -ne [string]$manifest.workspace.sessionName) { throw "sessionName does not match the local workstation manifest" }
    if (-not $actualInstallRoot.Equals($expectedInstallRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "installRoot does not match the local workstation manifest" }
    if ($coreSetup.validation.keepAliveRunning -ne $true -or $coreSetup.validation.sessionAvailable -ne $true) { throw "core validation did not prove keepalive and session readiness" }
}
catch {
    throw "Core workstation setup summary is stale, failed, or belongs to a different workspace: $coreSummary. $($_.Exception.Message)"
}

New-Item -ItemType Directory -Path $workspaceInstallRoot -Force | Out-Null
$schemaRoot = Join-Path $workspaceInstallRoot "schemas"
New-Item -ItemType Directory -Path $schemaRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceFiles.proofScript -Destination (Join-Path $workspaceInstallRoot "Invoke-WindowsWorkstationLiveProof.ps1") -Force
Copy-Item -LiteralPath $sourceFiles.commonModule -Destination (Join-Path $workspaceInstallRoot "WindowsWorkstationLiveProof.Common.psm1") -Force
Copy-Item -LiteralPath $sourceFiles.sessionProof -Destination (Join-Path $workspaceInstallRoot "Invoke-WindowsWorkstationSessionProof.ps1") -Force
Copy-Item -LiteralPath $sourceFiles.gnhfProof -Destination (Join-Path $workspaceInstallRoot "Invoke-WindowsWorkstationGnhfProof.ps1") -Force
Copy-Item -LiteralPath $sourceFiles.contractValidator -Destination (Join-Path $workspaceInstallRoot "Test-WindowsWorkstationLiveProofContracts.ps1") -Force
Copy-Item -LiteralPath $sourceFiles.schema -Destination (Join-Path $schemaRoot "windows-workstation-live-proof.schema.json") -Force
Copy-Item -LiteralPath $sourceFiles.manifest -Destination (Join-Path $workspaceInstallRoot "tmux-gnhf-workstation.json") -Force

$configPath = Join-Path $workspaceInstallRoot "windows-workstation-live-proof.config.json"
$config = [ordered]@{
    schemaVersion = "agentswitchboard-windows-workstation-live-proof-config/v1"
    installedAt = (Get-Date).ToString("o")
    sourceRepoPath = $sourceRepoPath
    sourceBranch = $sourceBranch
    sourceHead = $sourceHead
    manifestPath = Join-Path $workspaceInstallRoot "tmux-gnhf-workstation.json"
    artifactRoot = Join-Path $workspaceInstallRoot "runtime-proof"
    automaticAuthentication = $false
    automaticPush = $false
}
Write-AtomicJson -Value $config -Path $configPath

$installedCmd = Join-Path $workspaceInstallRoot "Run-WindowsWorkstationLiveProof.cmd"
@'
@echo off
setlocal
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-WindowsWorkstationLiveProof.ps1" -ManifestPath "%~dp0tmux-gnhf-workstation.json" %*
set "_code=%ERRORLEVEL%"
if not "%_code%"=="0" (
  echo.
  echo Runtime proof failed. Review the artifact path printed above.
  pause >nul
)
endlocal & exit /b %_code%
'@ | Set-Content -LiteralPath $installedCmd -Encoding ascii

$shortcutPath = $null
if ($CreateDesktopShortcut) {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "AgentSwitchboard Live Proof.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $installedCmd
    $shortcut.WorkingDirectory = $workspaceInstallRoot
    $shortcut.Description = "Run focus-independent WezTerm, WSL, tmux, OpenCode, and GNHF runtime proof"
    $shortcut.Save()
}

$installedValidator = Join-Path $workspaceInstallRoot "Test-WindowsWorkstationLiveProofContracts.ps1"
& (Get-Command pwsh.exe -ErrorAction Stop).Source -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installedValidator -RootPath $workspaceInstallRoot -InstalledMode
if ($LASTEXITCODE -ne 0) { throw "Installed runtime proof contracts failed." }

$installedProof = Join-Path $workspaceInstallRoot "Invoke-WindowsWorkstationLiveProof.ps1"
& (Get-Command pwsh.exe -ErrorAction Stop).Source -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installedProof -ManifestPath (Join-Path $workspaceInstallRoot "tmux-gnhf-workstation.json") -PlanOnly | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Installed runtime proof plan failed." }

$summaryPath = Join-Path $workspaceInstallRoot "windows-workstation-live-proof-install-summary.json"
$summary = [ordered]@{
    schemaVersion = "agentswitchboard-windows-workstation-live-proof-install/v1"
    installedAt = (Get-Date).ToString("o")
    sourceRepoPath = $sourceRepoPath
    sourceBranch = $sourceBranch
    sourceHead = $sourceHead
    workspaceInstallRoot = $workspaceInstallRoot
    coreSetupSummaryPath = $coreSummary
    proofScript = $installedProof
    launcher = $installedCmd
    configPath = $configPath
    schemaPath = Join-Path $schemaRoot "windows-workstation-live-proof.schema.json"
    shortcut = $shortcutPath
    automaticAuthentication = $false
    automaticPush = $false
}
Write-AtomicJson -Value $summary -Path $summaryPath

Write-Host "`n[PASS] Windows workstation live-proof lane installed." -ForegroundColor Green
Write-Host "[PASS] Launcher: $installedCmd" -ForegroundColor Green
Write-Host "[PASS] Summary:  $summaryPath" -ForegroundColor Green

if ($RunAfterInstall) {
    & $env:ComSpec /d /c "`"$installedCmd`""
    exit $LASTEXITCODE
}
