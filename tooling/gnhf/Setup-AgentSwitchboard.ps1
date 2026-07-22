[CmdletBinding()]
param(
    [string]$DefaultRepoPath,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$GnhfRepoPath,
    [string]$AgyAcpCommand,
    [switch]$InstallOpenCodeAndCopilot,
    [switch]$SkipHermesInstall,
    [switch]$ResetManifest,
    [switch]$RebuildGnhf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$startedAt = Get-Date
$timestamp = $startedAt.ToString("yyyyMMdd-HHmmss-fff")
$setupLogRoot = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\setup-logs\$timestamp"
New-Item -ItemType Directory -Path $setupLogRoot -Force | Out-Null
$transcriptPath = Join-Path $setupLogRoot "setup-transcript.txt"
$summaryPath = Join-Path $setupLogRoot "setup-summary.json"

$summary = [ordered]@{
    schemaVersion = 1
    startedAt = $startedAt.ToString("o")
    completedAt = $null
    status = "running"
    installRoot = $InstallRoot
    defaultRepoPath = $DefaultRepoPath
    transcriptPath = $transcriptPath
    summaryPath = $summaryPath
    steps = [System.Collections.Generic.List[object]]::new()
    agents = $null
    error = $null
}

function Add-SetupStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [string]$Evidence
    )

    [void]$summary.steps.Add([pscustomobject]@{
        name = $Name
        status = $Status
        evidence = $Evidence
        recordedAt = (Get-Date).ToString("o")
    })
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function Refresh-CurrentPath {
    $segments = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in @(
        [Environment]::GetEnvironmentVariable("Path", "Machine"),
        [Environment]::GetEnvironmentVariable("Path", "User"),
        (Join-Path $env:APPDATA "npm"),
        (Join-Path $HOME ".local\bin"),
        (Join-Path $env:LOCALAPPDATA "agy\bin"),
        (Join-Path $env:LOCALAPPDATA "hermes\bin")
    )) {
        if (-not [string]::IsNullOrWhiteSpace($segment)) {
            foreach ($entry in ($segment -split ";")) {
                if (-not [string]::IsNullOrWhiteSpace($entry) -and -not $segments.Contains($entry)) {
                    [void]$segments.Add($entry)
                }
            }
        }
    }
    $env:Path = $segments -join ";"
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 30
    )

    $result = [ordered]@{
        FilePath = $FilePath
        Arguments = $ArgumentList
        ExitCode = $null
        TimedOut = $false
        Output = ""
    }

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $FilePath
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        foreach ($argument in $ArgumentList) {
            [void]$psi.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $result.TimedOut = $true
            try {
                $process.Kill($true)
                $process.WaitForExit()
            }
            catch {}
        }
        else {
            $result.ExitCode = $process.ExitCode
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $result.Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
    catch {
        $result.Output = $_.Exception.Message
    }

    return [pscustomobject]$result
}

function Get-HermesRecord {
    Refresh-CurrentPath
    $command = Get-Command hermes -ErrorAction SilentlyContinue
    if (-not $command) {
        return [pscustomobject]@{
            available = $false
            commandPath = $null
            version = $null
            agentSpec = "acp:hermes acp"
            integration = "acp"
            evidence = "hermes command not found. Rerun Setup-AgentSwitchboard.cmd or install Hermes manually."
        }
    }

    $versionProbe = Invoke-Probe -FilePath $command.Source -ArgumentList @("--version")
    $acpProbe = Invoke-Probe -FilePath $command.Source -ArgumentList @("acp", "--help")
    $versionReady = (-not $versionProbe.TimedOut -and $versionProbe.ExitCode -eq 0)
    $acpReady = (-not $acpProbe.TimedOut -and $acpProbe.ExitCode -eq 0)
    $ready = ($versionReady -and $acpReady)
    $version = if ($versionReady -and $versionProbe.Output) {
        ($versionProbe.Output -split "\r?\n" | Select-Object -First 1).Trim()
    }
    elseif ($versionReady) {
        "detected"
    }
    else {
        $null
    }

    $evidence = if ($ready) {
        "Hermes version and 'hermes acp --help' probes exited successfully."
    }
    else {
        "Hermes is not ACP-ready. Version probe: exit=$($versionProbe.ExitCode), timeout=$($versionProbe.TimedOut), output=$($versionProbe.Output). ACP probe: exit=$($acpProbe.ExitCode), timeout=$($acpProbe.TimedOut), output=$($acpProbe.Output)."
    }

    return [pscustomobject]@{
        available = $ready
        commandPath = $command.Source
        version = $version
        agentSpec = "acp:hermes acp"
        integration = "acp"
        evidence = $evidence
    }
}

function Install-HermesIfNeeded {
    $record = Get-HermesRecord
    if ($record.available) {
        Add-SetupStep -Name "hermes-install" -Status "reused" -Evidence "Using healthy Hermes installation at '$($record.commandPath)'."
        return $record
    }

    if ($SkipHermesInstall) {
        Add-SetupStep -Name "hermes-install" -Status "skipped" -Evidence $record.evidence
        return $record
    }

    Write-Section "Install or repair Hermes"
    $installerUri = "https://hermes-agent.nousresearch.com/install.ps1"
    $installerPath = Join-Path $setupLogRoot "hermes-install.ps1"
    try {
        Invoke-WebRequest -Uri $installerUri -OutFile $installerPath -UseBasicParsing
        Add-SetupStep -Name "hermes-installer-download" -Status "passed" -Evidence "Downloaded official installer from $installerUri."

        & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installerPath
        if ($LASTEXITCODE -ne 0) {
            throw "Hermes installer exited with code $LASTEXITCODE."
        }

        Refresh-CurrentPath
        $record = Get-HermesRecord
        if ($record.available) {
            Add-SetupStep -Name "hermes-install" -Status "passed" -Evidence $record.evidence
        }
        else {
            Add-SetupStep -Name "hermes-install" -Status "blocked" -Evidence $record.evidence
        }
        return $record
    }
    catch {
        Add-SetupStep -Name "hermes-install" -Status "failed" -Evidence $_.Exception.Message
        Write-Warning "Hermes installation failed. Core fleet setup will continue and Hermes will be recorded as BLOCKED. $($_.Exception.Message)"
        return (Get-HermesRecord)
    }
}

function Copy-SetupFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Setup bundle file not found: $Source"
    }

    $sourceFull = [IO.Path]::GetFullPath($Source)
    $destinationFull = [IO.Path]::GetFullPath($Destination)
    if (-not $sourceFull.Equals($destinationFull, [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $sourceFull -Destination $destinationFull -Force
    }
}

$failed = $false
$transcriptStarted = $false
try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
    $transcriptStarted = $true
    Write-Section "AgentSwitchboard robust setup"
    Write-Host "Transcript: $transcriptPath"
    Write-Host "Summary:    $summaryPath"

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "AgentSwitchboard setup requires PowerShell 7. Open pwsh and rerun Setup-AgentSwitchboard.cmd."
    }
    Add-SetupStep -Name "powershell-version" -Status "passed" -Evidence "PowerShell $($PSVersionTable.PSVersion)."

    if ([string]::IsNullOrWhiteSpace($DefaultRepoPath)) {
        $candidateRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
        if (Test-Path -LiteralPath (Join-Path $candidateRepo ".git")) {
            $DefaultRepoPath = $candidateRepo
            $summary.defaultRepoPath = $DefaultRepoPath
        }
    }

    Refresh-CurrentPath
    $hermesRecord = Install-HermesIfNeeded

    Write-Section "Install or repair GNHF fleet"
    $coreInstaller = Join-Path $PSScriptRoot "Install-AgentSwitchboardGnhf.ps1"
    if (-not (Test-Path -LiteralPath $coreInstaller -PathType Leaf)) {
        throw "Core fleet installer not found: $coreInstaller"
    }

    $installParameters = @{
        InstallRoot = $InstallRoot
    }
    if ($DefaultRepoPath) { $installParameters["DefaultRepoPath"] = $DefaultRepoPath }
    if ($GnhfRepoPath) { $installParameters["GnhfRepoPath"] = $GnhfRepoPath }
    if ($AgyAcpCommand) { $installParameters["AgyAcpCommand"] = $AgyAcpCommand }
    if ($InstallOpenCodeAndCopilot) { $installParameters["InstallOpenCodeAndCopilot"] = $true }
    if ($ResetManifest) { $installParameters["ResetManifest"] = $true }
    if ($RebuildGnhf) { $installParameters["RebuildGnhf"] = $true }

    & $coreInstaller @installParameters
    Add-SetupStep -Name "core-fleet-install" -Status "passed" -Evidence "Core installer completed."

    $InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
    $statePath = Join-Path $InstallRoot "state.json"
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Core installer did not produce fleet state: $statePath"
    }

    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $state.agents | Add-Member -NotePropertyName "hermes" -NotePropertyValue $hermesRecord -Force
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
    Add-SetupStep -Name "hermes-state" -Status $(if ($hermesRecord.available) { "passed" } else { "blocked" }) -Evidence $hermesRecord.evidence

    foreach ($fileName in @(
        "Setup-AgentSwitchboard.ps1",
        "Setup-AgentSwitchboard.cmd",
        "Test-HermesSetupContracts.ps1",
        "gnhf-fleet.example.json"
    )) {
        Copy-SetupFile -Source (Join-Path $PSScriptRoot $fileName) -Destination (Join-Path $InstallRoot $fileName)
    }

    $hermesPromptSource = Join-Path $PSScriptRoot "prompts\hermes-implementation.md"
    $installedPrompts = Join-Path $InstallRoot "prompts"
    New-Item -ItemType Directory -Path $installedPrompts -Force | Out-Null
    Copy-SetupFile -Source $hermesPromptSource -Destination (Join-Path $installedPrompts "hermes-implementation.md")
    Add-SetupStep -Name "setup-bundle-copy" -Status "passed" -Evidence "Setup launchers, validators, manifest template, and Hermes prompt were installed under $InstallRoot."

    Write-Section "Validate setup contracts"
    $coreValidator = Join-Path $PSScriptRoot "Test-GnhfFleetContracts.ps1"
    $hermesValidator = Join-Path $PSScriptRoot "Test-HermesSetupContracts.ps1"
    & pwsh -NoLogo -NoProfile -File $coreValidator
    if ($LASTEXITCODE -ne 0) { throw "Core fleet contract validation failed with exit code $LASTEXITCODE." }
    & pwsh -NoLogo -NoProfile -File $hermesValidator
    if ($LASTEXITCODE -ne 0) { throw "Hermes setup contract validation failed with exit code $LASTEXITCODE." }
    Add-SetupStep -Name "contract-validation" -Status "passed" -Evidence "Core and Hermes setup validators passed."

    $summary.agents = $state.agents
    $summary.status = if ($hermesRecord.available) { "success" } else { "partial" }
}
catch {
    $failed = $true
    $summary.status = "failed"
    $summary.error = $_.Exception.ToString()
    Add-SetupStep -Name "setup" -Status "failed" -Evidence $_.Exception.Message
    Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
    $summary.completedAt = (Get-Date).ToString("o")
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }

    Write-Host "`nSetup status: $($summary.status)" -ForegroundColor $(if ($summary.status -eq "success") { "Green" } elseif ($summary.status -eq "partial") { "Yellow" } else { "Red" })
    Write-Host "Transcript:   $transcriptPath"
    Write-Host "Summary:      $summaryPath"
    Write-Host "Fleet root:   $InstallRoot"
}

if ($failed) {
    throw "AgentSwitchboard setup failed. Review '$transcriptPath' and '$summaryPath'."
}

if ($summary.status -eq "partial") {
    Write-Warning "Core setup completed, but Hermes is BLOCKED. Review the setup summary and rerun Setup-AgentSwitchboard.cmd after repairing the recorded cause."
}
else {
    Write-Host "AgentSwitchboard and Hermes are ready for authentication and bounded sprint launch." -ForegroundColor Green
}
