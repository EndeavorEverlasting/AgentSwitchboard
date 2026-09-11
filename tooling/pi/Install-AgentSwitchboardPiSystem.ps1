[CmdletBinding()]
param(
    [ValidateSet('Inspect','Apply')][string]$Mode = 'Inspect',
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [ValidateRange(15, 600)][int]$NetworkTimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path
$verificationPath = Join-Path $RootPath 'tooling\pi\harness\upstream-verification.json'
if (-not (Test-Path -LiteralPath $verificationPath -PathType Leaf)) {
    throw "Tracked Pi upstream verification is missing: $verificationPath"
}
$verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json -ErrorAction Stop

$version = [string]$verification.version
$tag = [string]$verification.versionTag
$installRoot = Join-Path $env:ProgramFiles "AgentSwitchboard\agents\pi\$version"
$targetExe = Join-Path $installRoot 'pi.exe'
$manifestPath = Join-Path $installRoot 'agentswitchboard-runtime.json'
$binDirectory = Join-Path $env:ProgramFiles 'AgentSwitchboard\bin'
$launcherPath = Join-Path $binDirectory 'pi.cmd'
$aliasPath = Join-Path $binDirectory 'asb-pi.cmd'
$stateBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
$runId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $stateBase "AgentSwitchboard\PiHarness\system-bootstrap\runs\$runId"
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard-pi-system-$runId"
$receiptPath = Join-Path $runRoot 'pi-system-bootstrap.json'
$reportPath = Join-Path $runRoot 'pi-system-bootstrap.md'

$script:status = 'failed'
$script:failureCode = $null
$script:failureMessage = $null
$script:isElevated = $false
$script:architecture = $env:PROCESSOR_ARCHITECTURE
$script:assetName = $null
$script:assetUrl = $null
$script:expectedSha256 = $null
$script:downloadSha256 = $null
$script:binaryInstalled = $false
$script:launcherChanged = $false
$script:machinePathChanged = $false
$script:finalVersion = $null
$script:bashPath = $null
$script:resolvedPiBefore = @()
$script:resolvedPiAfter = @()

function Stop-PiBootstrap {
    param([Parameter(Mandatory)][string]$Code,[Parameter(Mandatory)][string]$Message)
    throw ([InvalidOperationException]::new("$Code|$Message"))
}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-CmdToken {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '[\s&|<>^()%!"]') { return $Value }
    return '"' + ($Value -replace '"', '""') + '"'
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 30
    )
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { $psi.WorkingDirectory = $WorkingDirectory }

    $extension = [IO.Path]::GetExtension($FilePath)
    if ($extension -in @('.cmd','.bat')) {
        $psi.FileName = if ($env:ComSpec) { $env:ComSpec } else { Join-Path $env:SystemRoot 'System32\cmd.exe' }
        foreach ($prefix in @('/d','/s','/c')) { [void]$psi.ArgumentList.Add($prefix) }
        $commandLine = @('call',(ConvertTo-CmdToken -Value $FilePath)) + @($ArgumentList | ForEach-Object { ConvertTo-CmdToken -Value ([string]$_) })
        [void]$psi.ArgumentList.Add(($commandLine -join ' '))
    }
    else {
        $psi.FileName = $FilePath
        foreach ($argument in $ArgumentList) { [void]$psi.ArgumentList.Add([string]$argument) }
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try { $process.Kill($true) } catch {}
        try { $process.WaitForExit() } catch {}
    }
    return [pscustomobject]@{
        ExitCode = if ($timedOut) { $null } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = ([string]$stdoutTask.GetAwaiter().GetResult()).Trim()
        Stderr = ([string]$stderrTask.GetAwaiter().GetResult()).Trim()
    }
}

function Get-PiVersion {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $result = Invoke-BoundedProcess -FilePath $Path -ArgumentList @('--version') -TimeoutSeconds 30
    if ($result.TimedOut -or $result.ExitCode -ne 0) { return $null }
    $combined = (($result.Stdout, $result.Stderr) -join "`n").Trim()
    $match = [regex]::Match($combined, '(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value
}

function Get-PiCommandPaths {
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('pi.cmd','pi.exe','pi')) {
        foreach ($command in @(Get-Command $name -All -ErrorAction SilentlyContinue)) {
            $source = [string]$command.Source
            if ([string]::IsNullOrWhiteSpace($source)) { continue }
            if (-not $paths.Contains($source)) { [void]$paths.Add($source) }
        }
    }
    return @($paths | Select-Object -First 12)
}

function Resolve-BashPath {
    foreach ($candidate in @(
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Git\bin\bash.exe' }),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe' }),
        $(if (Get-Command bash.exe -ErrorAction SilentlyContinue) { (Get-Command bash.exe -ErrorAction SilentlyContinue).Source })
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return $null
}

function Get-MachinePathEntries {
    $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    return @($machinePath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-MachinePathContainsBin {
    foreach ($entry in @(Get-MachinePathEntries)) {
        if ($entry.TrimEnd('\') -ieq $binDirectory.TrimEnd('\')) { return $true }
    }
    return $false
}

function Test-MachinePathBinFirst {
    $entries = @(Get-MachinePathEntries)
    if ($entries.Count -eq 0) { return $false }
    return $entries[0].TrimEnd('\') -ieq $binDirectory.TrimEnd('\')
}

function Ensure-MachinePathFirst {
    $entries = @(Get-MachinePathEntries)
    $filtered = @($entries | Where-Object { $_.TrimEnd('\') -ine $binDirectory.TrimEnd('\') })
    $desired = @($binDirectory) + $filtered
    $current = $entries -join ';'
    $next = $desired -join ';'
    if ($current -cne $next) {
        [Environment]::SetEnvironmentVariable('Path',$next,'Machine')
        $script:machinePathChanged = $true
    }
}

function Get-ArchitectureRecord {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { return $verification.nativeRelease.windows.x64 }
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { return $verification.nativeRelease.windows.arm64 }
    Stop-PiBootstrap 'PI_WINDOWS_ARCHITECTURE_UNSUPPORTED' "Unsupported Windows architecture: $env:PROCESSOR_ARCHITECTURE"
}

function Test-OwnedLauncher {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $true }
    $head = (Get-Content -LiteralPath $Path -TotalCount 4 -ErrorAction Stop) -join "`n"
    return $head.Contains('AgentSwitchboard managed Pi launcher v1')
}

function New-LauncherContent {
    return (@(
        '@echo off',
        'rem AgentSwitchboard managed Pi launcher v1',
        '"' + $targetExe + '" %*',
        'exit /b %ERRORLEVEL%'
    ) -join "`r`n") + "`r`n"
}

function Write-BootstrapEvidence {
    $receipt = [ordered]@{
        schema = 'agentswitchboard.pi-system-bootstrap.v1'
        runId = $runId
        mode = $Mode
        status = $script:status
        failureCode = $script:failureCode
        failureMessage = $script:failureMessage
        version = $version
        versionTag = $tag
        architecture = $script:architecture
        elevated = $script:isElevated
        installRoot = $installRoot
        executable = $targetExe
        launcher = $launcherPath
        aliasLauncher = $aliasPath
        assetName = $script:assetName
        assetUrl = $script:assetUrl
        expectedSha256 = $script:expectedSha256
        downloadSha256 = $script:downloadSha256
        binaryInstalled = $script:binaryInstalled
        launcherChanged = $script:launcherChanged
        machinePathContainsBin = (Test-MachinePathContainsBin)
        machinePathBinFirst = (Test-MachinePathBinFirst)
        machinePathChanged = $script:machinePathChanged
        bashPath = $script:bashPath
        finalVersion = $script:finalVersion
        resolvedPiBefore = @($script:resolvedPiBefore)
        resolvedPiAfter = @($script:resolvedPiAfter)
        packageManagerRequired = $false
        nodeRuntimeRequired = $false
        configurationMutation = 'none'
        authenticationMutation = 'none'
        projectTrustMutation = 'none'
        proofCeiling = 'Proves tracked standalone Pi release identity, archive digest, machine-owned runtime placement, ASB launcher state, machine PATH presence and precedence, Git Bash discovery, and direct version execution. Provider authentication, model response, project trust, and child-agent delivery require separate runtime evidence.'
    }
    $receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
    @(
        '# Pi system bootstrap', '',
        "- Status: ``$($script:status)``",
        "- Failure: ``$($script:failureCode)``",
        "- Version: ``$version``",
        "- Executable: ``$targetExe``",
        "- Launcher: ``$launcherPath``",
        "- Machine PATH contains ASB bin: ``$(Test-MachinePathContainsBin)``",
        "- Machine PATH starts with ASB bin: ``$(Test-MachinePathBinFirst)``",
        "- Git Bash: ``$($script:bashPath)``",
        "- Final version: ``$($script:finalVersion)``", '',
        'The runtime is system-wide; Pi credentials, subscriptions, settings, trust decisions, sessions, and project resources remain user/project scoped.',
        'No npm, Node.js, provider credential, global Pi setting, or project trust mutation is required by this bootstrap.'
    ) | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
    Write-Host "PI_SYSTEM_BOOTSTRAP_STATUS=$($script:status)"
    Write-Host "PI_SYSTEM_BOOTSTRAP_FAILURE_CODE=$($script:failureCode)"
    Write-Host "PI_SYSTEM_BOOTSTRAP_RECEIPT=$receiptPath"
    Write-Host "PI_SYSTEM_BOOTSTRAP_EXECUTABLE=$targetExe"
    Write-Host "PI_SYSTEM_BOOTSTRAP_VERSION=$($script:finalVersion)"
    Write-Host "PI_SYSTEM_BOOTSTRAP_PATH_FIRST=$(Test-MachinePathBinFirst)"
    Write-Host "PI_SYSTEM_BOOTSTRAP_BASH=$($script:bashPath)"
}

try {
    $null = New-Item -ItemType Directory -Path $runRoot -Force
    if ($env:OS -ne 'Windows_NT') { Stop-PiBootstrap 'WINDOWS_REQUIRED' 'The system-wide Pi bootstrap is Windows-only.' }
    if ($PSVersionTable.PSVersion.Major -lt 7) { Stop-PiBootstrap 'POWERSHELL7_REQUIRED' 'PowerShell 7 is required.' }
    if ([string]::IsNullOrWhiteSpace($env:ProgramFiles)) { Stop-PiBootstrap 'PROGRAMFILES_REQUIRED' 'ProgramFiles is unavailable.' }
    if ([string]::IsNullOrWhiteSpace($version) -or $tag -ne "v$version") { Stop-PiBootstrap 'PI_TRACKED_VERSION_INVALID' 'Tracked Pi version/tag identity is incomplete or inconsistent.' }

    $archRecord = Get-ArchitectureRecord
    $script:assetName = [string]$archRecord.assetName
    $script:assetUrl = [string]$archRecord.downloadUrl
    $script:expectedSha256 = [string]$archRecord.sha256
    if ([string]::IsNullOrWhiteSpace($script:assetName) -or [string]::IsNullOrWhiteSpace($script:assetUrl) -or $script:expectedSha256 -notmatch '^[0-9a-fA-F]{64}$') {
        Stop-PiBootstrap 'PI_TRACKED_ASSET_INVALID' 'Tracked Windows release asset identity is incomplete.'
    }

    $script:isElevated = Test-IsElevated
    $script:bashPath = Resolve-BashPath
    $script:resolvedPiBefore = @(Get-PiCommandPaths)
    $script:finalVersion = Get-PiVersion -Path $targetExe

    if ($Mode -eq 'Inspect') {
        $script:status = if ($script:finalVersion -eq $version -and (Test-MachinePathBinFirst) -and (Test-Path -LiteralPath $launcherPath -PathType Leaf) -and $script:bashPath) { 'ready' } else { 'inspect-complete' }
        return
    }

    if (-not [Environment]::Is64BitOperatingSystem) { Stop-PiBootstrap 'PI_64BIT_WINDOWS_REQUIRED' 'Pi system bootstrap requires 64-bit Windows.' }
    if (-not $script:isElevated) { Stop-PiBootstrap 'ADMINISTRATOR_REQUIRED' 'Apply requires an elevated PowerShell session for Program Files and Machine PATH.' }
    if (-not $script:bashPath) { Stop-PiBootstrap 'GIT_BASH_REQUIRED' 'Pi requires Bash on Windows. Install Git for Windows or configure a reviewed Bash path, then retry.' }
    if (-not (Test-OwnedLauncher -Path $launcherPath) -or -not (Test-OwnedLauncher -Path $aliasPath)) {
        Stop-PiBootstrap 'PI_LAUNCHER_PATH_ALREADY_OWNED' "An unmanaged launcher already occupies the AgentSwitchboard Pi launcher path under $binDirectory."
    }
    if (Test-Path -LiteralPath $installRoot -PathType Container) {
        $owned = Test-Path -LiteralPath $manifestPath -PathType Leaf
        if (-not $owned -and (Get-ChildItem -LiteralPath $installRoot -Force | Select-Object -First 1)) {
            Stop-PiBootstrap 'PI_INSTALL_DIRECTORY_ALREADY_OWNED' "The versioned Pi install directory exists without an AgentSwitchboard runtime manifest: $installRoot"
        }
    }

    $existingManifestMatches = $false
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $existingManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
            $existingManifestMatches = ([string]$existingManifest.version -eq $version -and [string]$existingManifest.sha256 -ieq $script:expectedSha256)
        }
        catch { $existingManifestMatches = $false }
    }

    if ($script:finalVersion -ne $version -or -not $existingManifestMatches) {
        $null = New-Item -ItemType Directory -Path $stageRoot -Force
        $archivePath = Join-Path $stageRoot $script:assetName
        $extractRoot = Join-Path $stageRoot 'extract'
        try {
            Invoke-WebRequest -Uri $script:assetUrl -OutFile $archivePath -Headers @{'User-Agent'='AgentSwitchboard-Pi-System-Bootstrap'} -TimeoutSec $NetworkTimeoutSeconds -ErrorAction Stop
        }
        catch { Stop-PiBootstrap 'PI_RELEASE_DOWNLOAD_FAILED' "Unable to download tracked Pi release asset within the bounded network window: $($_.Exception.Message)" }

        $actualSha = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $script:downloadSha256 = $actualSha
        if ($actualSha -ne $script:expectedSha256.ToLowerInvariant()) { Stop-PiBootstrap 'PI_RELEASE_SHA256_MISMATCH' 'Downloaded Pi archive SHA-256 does not match the tracked official release digest.' }

        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
        $stagedExe = Join-Path $extractRoot 'pi.exe'
        if (-not (Test-Path -LiteralPath $stagedExe -PathType Leaf)) { Stop-PiBootstrap 'PI_RELEASE_LAYOUT_UNEXPECTED' 'Tracked Windows Pi archive did not contain root-level pi.exe.' }
        foreach ($requiredRelative in @('package.json','README.md','docs','node_modules')) {
            if (-not (Test-Path -LiteralPath (Join-Path $extractRoot $requiredRelative))) { Stop-PiBootstrap 'PI_RELEASE_LAYOUT_UNEXPECTED' "Tracked Windows Pi archive is missing required runtime surface: $requiredRelative" }
        }
        $stagedVersion = Get-PiVersion -Path $stagedExe
        if ($stagedVersion -ne $version) { Stop-PiBootstrap 'PI_STAGED_VERSION_MISMATCH' "Staged Pi version '$stagedVersion' does not match tracked version '$version'." }

        if (Test-Path -LiteralPath $installRoot) { Remove-Item -LiteralPath $installRoot -Recurse -Force }
        $parent = Split-Path -Parent $installRoot
        $null = New-Item -ItemType Directory -Path $parent -Force
        Move-Item -LiteralPath $extractRoot -Destination $installRoot
        [ordered]@{
            schema = 'agentswitchboard.pi-managed-runtime.v1'
            version = $version
            sourceRepository = [string]$verification.sourceRepository
            assetName = $script:assetName
            sha256 = $script:expectedSha256.ToLowerInvariant()
            installedAt = [DateTime]::UtcNow.ToString('o')
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        $script:binaryInstalled = $true
    }

    $null = New-Item -ItemType Directory -Path $binDirectory -Force
    $desiredLauncher = New-LauncherContent
    foreach ($path in @($launcherPath,$aliasPath)) {
        $current = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Content -LiteralPath $path -Raw } else { $null }
        if ($current -cne $desiredLauncher) {
            [IO.File]::WriteAllText($path,$desiredLauncher,[Text.Encoding]::ASCII)
            $script:launcherChanged = $true
        }
    }
    Ensure-MachinePathFirst

    $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
    $user = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = (@($machine,$user) -join ';')
    $script:finalVersion = Get-PiVersion -Path $targetExe
    $script:resolvedPiAfter = @(Get-PiCommandPaths)
    if ($script:finalVersion -ne $version) { Stop-PiBootstrap 'PI_FINAL_VERSION_FAILED' 'Direct Pi version proof failed after installation.' }
    if (-not (Test-MachinePathContainsBin)) { Stop-PiBootstrap 'PI_MACHINE_PATH_FAILED' 'AgentSwitchboard bin is not present in Machine PATH after Apply.' }
    if (-not (Test-MachinePathBinFirst)) { Stop-PiBootstrap 'PI_MACHINE_PATH_PRECEDENCE_FAILED' 'AgentSwitchboard bin is present but is not the first Machine PATH entry after Apply.' }
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) { Stop-PiBootstrap 'PI_LAUNCHER_FAILED' 'Canonical Pi launcher was not created.' }
    $launcherVersion = Get-PiVersion -Path $launcherPath
    if ($launcherVersion -ne $version) { Stop-PiBootstrap 'PI_LAUNCHER_VERSION_FAILED' "Canonical Pi launcher resolved version '$launcherVersion' instead of '$version'." }
    $script:status = 'success'
}
catch {
    $raw = [string]$_.Exception.Message
    if ($raw -match '^([A-Z0-9_]+)\|(.*)$') {
        $script:failureCode = $Matches[1]
        $script:failureMessage = $Matches[2]
    }
    else {
        $script:failureCode = 'PI_SYSTEM_BOOTSTRAP_UNEXPECTED_FAILURE'
        $script:failureMessage = $raw
    }
    $script:status = 'failed'
}
finally {
    if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) { $null = New-Item -ItemType Directory -Path $runRoot -Force }
    if (-not $script:bashPath) { $script:bashPath = Resolve-BashPath }
    if (-not $script:finalVersion) { $script:finalVersion = Get-PiVersion -Path $targetExe }
    Write-BootstrapEvidence
    if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:status -eq 'failed') {
    Write-Error "$($script:failureCode): $($script:failureMessage)"
    exit 1
}
exit 0
