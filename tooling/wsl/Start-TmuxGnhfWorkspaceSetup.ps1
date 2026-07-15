[CmdletBinding()]
param(
    [ValidateSet("Guided", "Plan", "Apply")]
    [string]$Mode = "Guided",
    [string]$ManifestPath = (Join-Path $PSScriptRoot "tmux-gnhf-workstation.local.json"),
    [switch]$ReplaceExistingWezTermConfig,
    [string]$WslExe = "wsl.exe",
    [string]$RunRoot = "$env:LOCALAPPDATA\AgentSwitchboard\tmux-gnhf\setup-runs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ExitSuccess = 0
$ExitCancelled = 10
$ExitPrerequisite = 20
$ExitResumeRequired = 30
$ExitApplyFailed = 40
$ExitValidationFailed = 50

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "PowerShell 7 or newer is required."
    exit $ExitPrerequisite
}
if ($env:OS -ne "Windows_NT") {
    Write-Error "This guided workstation launcher is Windows-only."
    exit $ExitPrerequisite
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$runDirectory = Join-Path $RunRoot $timestamp
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$operatorLogPath = Join-Path $runDirectory "operator.log"
$summaryPath = Join-Path $runDirectory "operator-summary.json"
$postValidationPath = Join-Path $runDirectory "post-validation.json"

$script:summary = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString("o")
    completedAt = $null
    status = "running"
    exitCode = $null
    mode = $Mode
    manifestPath = $null
    runDirectory = $runDirectory
    operatorLog = $operatorLogPath
    actions = [System.Collections.Generic.List[object]]::new()
    proof = [ordered]@{
        planCompleted = $false
        installation = $false
        configuration = $false
        commandAck = $false
        behaviorObserved = $false
        persistenceObserved = $false
        authentication = $false
        hostedModelResponse = $false
    }
}

function Write-Operator {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet("Info", "Pass", "Plan", "Warn", "Fail")]
        [string]$Level = "Info"
    )

    $prefix = switch ($Level) {
        "Pass" { "[PASS]" }
        "Plan" { "[PLAN]" }
        "Warn" { "[WARN]" }
        "Fail" { "[FAIL]" }
        default { "[INFO]" }
    }
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $prefix $Text"
    Add-Content -LiteralPath $operatorLogPath -Value $line -Encoding utf8
    $color = switch ($Level) {
        "Pass" { "Green" }
        "Plan" { "Yellow" }
        "Warn" { "Yellow" }
        "Fail" { "Red" }
        default { "Gray" }
    }
    Write-Host "$prefix $Text" -ForegroundColor $color
}

function Add-Action {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$Status,
        [string]$Detail = ""
    )
    $script:summary.actions.Add([pscustomobject]@{
        at = (Get-Date).ToString("o")
        step = $Step
        status = $Status
        detail = $Detail
    })
}

function Save-Summary {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][int]$ExitCode
    )
    $script:summary.completedAt = (Get-Date).ToString("o")
    $script:summary.status = $Status
    $script:summary.exitCode = $ExitCode
    $script:summary | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
}

function Stop-Setup {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("Info", "Pass", "Plan", "Warn", "Fail")]
        [string]$Level = "Info"
    )
    Write-Operator -Text $Message -Level $Level
    Save-Summary -Status $Status -ExitCode $ExitCode
    Write-Host ""
    Write-Host "Local log:     $operatorLogPath" -ForegroundColor Cyan
    Write-Host "Local summary: $summaryPath" -ForegroundColor Cyan
    exit $ExitCode
}

function Convert-RecordToLogText {
    param([Parameter(Mandatory)]$Record)
    if ($Record -is [System.Management.Automation.InformationRecord]) {
        return [string]$Record.MessageData
    }
    if ($Record -is [System.Management.Automation.ErrorRecord]) {
        return $Record.ToString()
    }
    if ($Record -is [string]) {
        return $Record
    }
    try {
        return ($Record | ConvertTo-Json -Depth 10 -Compress)
    }
    catch {
        return [string]$Record
    }
}

function Invoke-WorkspaceInstaller {
    param(
        [Parameter(Mandatory)][string]$ResolvedManifestPath,
        [switch]$Apply
    )

    $installerPath = Join-Path $PSScriptRoot "Install-TmuxGnhfWorkspace.ps1"
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw "Workspace installer is missing: $installerPath"
    }

    $arguments = @{
        ManifestPath = $ResolvedManifestPath
        WslExe = $WslExe
    }
    if ($Apply) {
        $arguments.Apply = $true
    }
    if ($ReplaceExistingWezTermConfig) {
        $arguments.ReplaceExistingWezTermConfig = $true
    }

    $records = [System.Collections.Generic.List[object]]::new()
    & $installerPath @arguments *>&1 | ForEach-Object {
        $records.Add($_)
        $text = Convert-RecordToLogText -Record $_
        if ($text) {
            Add-Content -LiteralPath $operatorLogPath -Value $text -Encoding utf8
            if ($_ -isnot [pscustomobject]) {
                Write-Host $text
            }
        }
    }

    $result = $records |
        Where-Object {
            $_ -is [psobject] -and
            $_.PSObject.Properties.Name -contains "schemaVersion" -and
            $_.PSObject.Properties.Name -contains "status"
        } |
        Select-Object -Last 1

    if (-not $result) {
        throw "The workspace installer returned no structured result. Review $operatorLogPath."
    }
    return $result
}

function Get-DistributionNames {
    $wslCommand = Get-Command $WslExe -ErrorAction SilentlyContinue
    if (-not $wslCommand) {
        return @()
    }

    $output = & $wslCommand.Source --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }
    return @($output | ForEach-Object {
        ([string]$_).Replace([char]0, "").Trim()
    } | Where-Object { $_ })
}

function Test-DistributionReady {
    param([Parameter(Mandatory)][string]$Distribution)
    $output = & $WslExe -d $Distribution -e bash -lc "id -u >/dev/null 2>&1 && printf READY" 2>$null
    return ($LASTEXITCODE -eq 0 -and ($output -join "") -match "READY")
}

function Enable-WslFeatures {
    Write-Operator -Text "Windows must enable WSL and VirtualMachinePlatform. A UAC prompt is expected." -Level Warn
    foreach ($feature in @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")) {
        $process = Start-Process -FilePath "dism.exe" -Verb RunAs -Wait -PassThru -ArgumentList @(
            "/online",
            "/enable-feature",
            "/featurename:$feature",
            "/all",
            "/norestart"
        )
        Add-Action -Step "enable-$feature" -Status "exit-$($process.ExitCode)"
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "DISM failed to enable $feature with exit code $($process.ExitCode)."
        }
    }
}

function Install-WslDistribution {
    param([Parameter(Mandatory)][string]$Distribution)
    Write-Operator -Text "Installing WSL distribution '$Distribution'. Complete any Windows or Ubuntu prompts shown." -Level Warn
    & $WslExe --install -d $Distribution 2>&1 | ForEach-Object {
        $text = [string]$_
        Add-Content -LiteralPath $operatorLogPath -Value $text -Encoding utf8
        Write-Host $text
    }
    $exitCode = $LASTEXITCODE
    Add-Action -Step "install-wsl-distribution" -Status "exit-$exitCode" -Detail $Distribution
    if ($exitCode -ne 0) {
        throw "wsl --install failed with exit code $exitCode."
    }
}

function Initialize-WslDistribution {
    param([Parameter(Mandatory)][string]$Distribution)
    Write-Operator -Text "Ubuntu may ask you to create its Linux username and password. This is local WSL initialization, not provider authentication." -Level Warn
    & $WslExe -d $Distribution -e bash -lc "printf 'WSL_READY\n'" 2>&1 | ForEach-Object {
        $text = [string]$_
        Add-Content -LiteralPath $operatorLogPath -Value $text -Encoding utf8
        Write-Host $text
    }
    $exitCode = $LASTEXITCODE
    Add-Action -Step "initialize-wsl-distribution" -Status "exit-$exitCode" -Detail $Distribution
    if ($exitCode -ne 0 -or -not (Test-DistributionReady -Distribution $Distribution)) {
        throw "WSL distribution '$Distribution' did not complete its first-run initialization."
    }
}

function Install-LinuxPackagesAsRoot {
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string[]]$Packages
    )
    if ($Packages.Count -eq 0) {
        Write-Operator -Text "No Linux packages were declared." -Level Pass
        return
    }
    foreach ($package in $Packages) {
        if ($package -notmatch '^[a-z0-9][a-z0-9+.-]*$') {
            throw "Unsafe Linux package name in manifest: $package"
        }
    }

    $packageText = $Packages -join " "
    Write-Operator -Text "Installing or reusing Linux packages as WSL root: $packageText" -Level Info
    $command = "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq $packageText"
    & $WslExe -d $Distribution -u root -e bash -lc $command 2>&1 | ForEach-Object {
        $text = [string]$_
        Add-Content -LiteralPath $operatorLogPath -Value $text -Encoding utf8
        Write-Host $text
    }
    $exitCode = $LASTEXITCODE
    Add-Action -Step "install-linux-packages" -Status "exit-$exitCode" -Detail $packageText
    if ($exitCode -ne 0) {
        throw "Linux package installation failed with exit code $exitCode."
    }
}

function New-RuntimeManifests {
    param(
        [Parameter(Mandatory)]$WorkstationManifest,
        [Parameter(Mandatory)]$BaseManifest
    )

    $runtimeBase = $BaseManifest | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    if ($runtimeBase.PSObject.Properties.Name -contains "skipPackageInstallation") {
        $runtimeBase.skipPackageInstallation = $true
    }
    else {
        $runtimeBase | Add-Member -NotePropertyName skipPackageInstallation -NotePropertyValue $true
    }
    $runtimeBasePath = Join-Path $runDirectory "wsl-base.runtime.json"
    $runtimeBase | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $runtimeBasePath -Encoding utf8NoBOM

    $runtimeWorkstation = $WorkstationManifest | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $runtimeWorkstation.wslBootstrapManifest = $runtimeBasePath
    $runtimeWorkstationPath = Join-Path $runDirectory "tmux-gnhf-workstation.runtime.json"
    $runtimeWorkstation | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $runtimeWorkstationPath -Encoding utf8NoBOM

    return $runtimeWorkstationPath
}

Write-Operator -Text "AgentSwitchboard guided tmux + GNHF workstation setup" -Level Info
Write-Operator -Text "Mode: $Mode" -Level Info
Write-Operator -Text "Local evidence directory: $runDirectory" -Level Info
Write-Operator -Text "Provider authentication, tokens, paid model calls, Git push, and WSL unregister are outside this setup." -Level Info

try {
    $exampleManifestPath = Join-Path $PSScriptRoot "tmux-gnhf-workstation.example.json"
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        if (-not (Test-Path -LiteralPath $exampleManifestPath -PathType Leaf)) {
            throw "Example manifest is missing: $exampleManifestPath"
        }
        Copy-Item -LiteralPath $exampleManifestPath -Destination $ManifestPath -Force
        Add-Action -Step "create-local-manifest" -Status "created" -Detail $ManifestPath
        Write-Operator -Text "Created the computer-local manifest from safe defaults: $ManifestPath" -Level Pass
    }

    $resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
    $script:summary.manifestPath = $resolvedManifestPath
    $manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1) {
        throw "Unsupported workstation manifest schemaVersion: $($manifest.schemaVersion)"
    }
    $distribution = [string]$manifest.distribution
    if ($distribution -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Unsafe WSL distribution name: $distribution"
    }

    $baseManifestValue = [string]$manifest.wslBootstrapManifest
    $baseManifestPath = if ([System.IO.Path]::IsPathRooted($baseManifestValue)) {
        [System.IO.Path]::GetFullPath($baseManifestValue)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $resolvedManifestPath) $baseManifestValue))
    }
    $baseManifest = Get-Content -LiteralPath $baseManifestPath -Raw | ConvertFrom-Json
    $packages = @($baseManifest.packages | ForEach-Object { [string]$_ })

    $wslCommand = Get-Command $WslExe -ErrorAction SilentlyContinue
    if (-not $wslCommand) {
        Write-Operator -Text "WSL is not available. The safe next action is to enable Windows WSL features and reboot." -Level Plan
        if ($Mode -eq "Plan") {
            Stop-Setup -Status "plan-action-required" -ExitCode $ExitSuccess -Message "Plan complete. Double-click the CMD normally when ready to enable WSL." -Level Pass
        }
        if ($Mode -eq "Guided" -and (Read-Host "Type ENABLE to enable WSL features, or press Enter to stop") -cne "ENABLE") {
            Stop-Setup -Status "cancelled" -ExitCode $ExitCancelled -Message "No Windows features were changed." -Level Warn
        }
        Enable-WslFeatures
        Stop-Setup -Status "reboot-required" -ExitCode $ExitResumeRequired -Message "WSL features were enabled. Reboot Windows, sign into this same daily account, and double-click the CMD again." -Level Warn
    }

    $distributionNames = Get-DistributionNames
    if ($distributionNames -notcontains $distribution) {
        Write-Operator -Text "WSL distribution '$distribution' is missing and would be installed." -Level Plan
        if ($Mode -eq "Plan") {
            Stop-Setup -Status "plan-action-required" -ExitCode $ExitSuccess -Message "Plan complete. Double-click the CMD normally when ready to install $distribution." -Level Pass
        }
        if ($Mode -eq "Guided" -and (Read-Host "Type INSTALL to install $distribution, or press Enter to stop") -cne "INSTALL") {
            Stop-Setup -Status "cancelled" -ExitCode $ExitCancelled -Message "The WSL distribution was not installed." -Level Warn
        }
        Install-WslDistribution -Distribution $distribution
        Stop-Setup -Status "distribution-installed-resume-required" -ExitCode $ExitResumeRequired -Message "The distribution installation command completed. Reboot if Windows requests it, finish Ubuntu first-run setup, then double-click the CMD again." -Level Warn
    }

    if (-not (Test-DistributionReady -Distribution $distribution)) {
        if ($Mode -eq "Plan") {
            Stop-Setup -Status "plan-action-required" -ExitCode $ExitSuccess -Message "The distribution exists but needs first-run initialization. Double-click the CMD normally to continue." -Level Warn
        }
        Initialize-WslDistribution -Distribution $distribution
    }

    Write-Operator -Text "Running the repository-owned read-only plan." -Level Info
    $planResult = Invoke-WorkspaceInstaller -ResolvedManifestPath $resolvedManifestPath
    Add-Action -Step "workspace-plan" -Status ([string]$planResult.status)
    $script:summary.proof.planCompleted = $true
    if ($planResult.status -notin @("plan-only", "completed")) {
        Stop-Setup -Status "resume-required" -ExitCode $ExitResumeRequired -Message "The plan found a prerequisite that must be completed before apply. Review the local log, complete it, and rerun this same CMD." -Level Warn
    }

    if ($Mode -eq "Plan") {
        Stop-Setup -Status "plan-only" -ExitCode $ExitSuccess -Message "Read-only plan completed. No workstation changes were applied." -Level Pass
    }

    if ($Mode -eq "Guided") {
        Write-Host ""
        Write-Host "The read-only plan completed." -ForegroundColor Cyan
        Write-Host "Type INSTALL to apply the declared setup. Any other response stops safely." -ForegroundColor Yellow
        if ((Read-Host "Confirmation") -cne "INSTALL") {
            Stop-Setup -Status "cancelled" -ExitCode $ExitCancelled -Message "Apply was not confirmed. No apply-stage changes were made." -Level Warn
        }
    }

    Install-LinuxPackagesAsRoot -Distribution $distribution -Packages $packages
    $runtimeManifestPath = New-RuntimeManifests -WorkstationManifest $manifest -BaseManifest $baseManifest
    Add-Action -Step "prepare-runtime-manifests" -Status "completed" -Detail $runtimeManifestPath

    $applyStartedAt = Get-Date
    Write-Operator -Text "Applying the repository-owned workstation setup." -Level Info
    $applyResult = Invoke-WorkspaceInstaller -ResolvedManifestPath $runtimeManifestPath -Apply
    Add-Action -Step "workspace-apply" -Status ([string]$applyResult.status)
    if ($applyResult.status -ne "completed") {
        throw "Workspace apply returned status '$($applyResult.status)'."
    }

    $wslSetupRoot = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\wsl-setup"
    $latestWslSummary = Get-ChildItem -LiteralPath $wslSetupRoot -Filter "setup-summary.json" -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $applyStartedAt.AddSeconds(-2) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latestWslSummary) {
        $wslSummary = Get-Content -LiteralPath $latestWslSummary.FullName -Raw | ConvertFrom-Json
        Add-Action -Step "verify-wsl-bootstrap-summary" -Status ([string]$wslSummary.status) -Detail $latestWslSummary.FullName
        if ($wslSummary.status -ne "completed") {
            throw "The nested WSL bootstrap did not complete cleanly. Status: $($wslSummary.status)"
        }
    }
    else {
        throw "The nested WSL bootstrap summary was not found after apply."
    }

    $installRootText = [Environment]::ExpandEnvironmentVariables([string]$manifest.workspace.installRoot)
    $installRoot = [System.IO.Path]::GetFullPath($installRootText)
    $statusScriptPath = Join-Path $installRoot "Get-TmuxGnhfWorkspaceStatus.ps1"
    if (-not (Test-Path -LiteralPath $statusScriptPath -PathType Leaf)) {
        throw "Post-install status script is missing: $statusScriptPath"
    }
    $postStatus = & $statusScriptPath
    $postStatus | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $postValidationPath -Encoding utf8NoBOM
    if (-not $postStatus.keepAliveRunning -or -not $postStatus.sessionAvailable) {
        $script:summary.proof.installation = $true
        $script:summary.proof.configuration = $true
        Add-Action -Step "post-install-status" -Status "failed" -Detail $postValidationPath
        Stop-Setup -Status "validation-failed" -ExitCode $ExitValidationFailed -Message "Installation completed, but command validation did not find both the owned keepalive and tmux session. Review post-validation.json." -Level Fail
    }

    $script:summary.proof.installation = $true
    $script:summary.proof.configuration = $true
    $script:summary.proof.commandAck = $true
    Add-Action -Step "post-install-status" -Status "passed" -Detail $postValidationPath
    Stop-Setup -Status "completed" -ExitCode $ExitSuccess -Message "Workstation setup and command-level validation completed. Use the AgentSwitchboard tmux desktop shortcut next; authenticate OpenCode manually before model work." -Level Pass
}
catch {
    Add-Action -Step "unhandled-failure" -Status "failed" -Detail $_.Exception.Message
    Write-Operator -Text $_.Exception.Message -Level Fail
    Save-Summary -Status "failed" -ExitCode $ExitApplyFailed
    Write-Host ""
    Write-Host "Local log:     $operatorLogPath" -ForegroundColor Cyan
    Write-Host "Local summary: $summaryPath" -ForegroundColor Cyan
    Write-Host "No automatic provider authentication, Git push, WSL reset, or secret collection was attempted." -ForegroundColor Yellow
    exit $ExitApplyFailed
}
