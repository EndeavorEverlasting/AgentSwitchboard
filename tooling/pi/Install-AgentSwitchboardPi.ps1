[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [ValidateSet('Install', 'Verify', 'Uninstall')]
    [string]$Mode = 'Install',

    [switch]$Force,

    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

$verificationPath = Join-Path $RootPath 'tooling/pi/harness/upstream-verification.json'
$registryPath = Join-Path $RootPath 'tooling/pi/harness/pi-adapter.registry.json'
if (-not (Test-Path -LiteralPath $verificationPath -PathType Leaf)) {
    throw "Pi upstream verification record is missing: $verificationPath"
}
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    throw "Pi adapter registry is missing: $registryPath"
}

$verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json
$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
$packageName = [string]$verification.package
$pinnedVersion = [version]([string]$verification.version)
$minimumNodeVersion = [version]([string]$verification.minimumNodeVersion)
$packageSpec = "$packageName@$pinnedVersion"

$startedAt = Get-Date
$runId = '{0}-{1}' -f $startedAt.ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    if ($IsWindows -and $env:LOCALAPPDATA) {
        $OutputDirectory = Join-Path $env:LOCALAPPDATA "AgentSwitchboard/PiHarness/install/$runId"
    }
    else {
        $stateRoot = if ($env:XDG_STATE_HOME) { $env:XDG_STATE_HOME } else { Join-Path $HOME '.local/state' }
        $OutputDirectory = Join-Path $stateRoot "AgentSwitchboard/PiHarness/install/$runId"
    }
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$summaryPath = Join-Path $OutputDirectory 'pi-install-summary.json'
$stdoutPath = Join-Path $OutputDirectory 'npm-stdout.txt'
$stderrPath = Join-Path $OutputDirectory 'npm-stderr.txt'
$steps = [System.Collections.Generic.List[object]]::new()

$summary = [ordered]@{
    schema = 'agentswitchboard.pi-install-result.v1'
    runId = $runId
    startedAt = $startedAt.ToUniversalTime().ToString('o')
    completedAt = $null
    status = 'running'
    mode = $Mode
    repositoryRoot = $RootPath
    package = $packageName
    pinnedVersion = $pinnedVersion.ToString()
    minimumNodeVersion = $minimumNodeVersion.ToString()
    node = $null
    npm = $null
    pi = $null
    configurationMutation = 'none'
    authenticationMutation = 'none'
    evidenceRoot = $OutputDirectory
    steps = $steps
    error = $null
    proofLevel = 'installer-command-and-version-readback'
    proofCeiling = 'Package installation or removal command, executable resolution, and exact version readback only. Provider authentication, model availability, project trust, network privacy, extensions, model response, and agent delivery are not proven.'
}

function Add-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [string]$Evidence = ''
    )

    [void]$steps.Add([pscustomobject]@{
        name = $Name
        status = $Status
        evidence = $Evidence
        recordedAt = (Get-Date).ToUniversalTime().ToString('o')
    })
}

function Resolve-NativeCommand {
    param([Parameter(Mandatory)][string[]]$Names)

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command -and $command.Source -and $command.Source -notlike '*.ps1') {
            return $command.Source
        }
    }
    return $null
}

function ConvertTo-CmdToken {
    param([Parameter(Mandatory)][string]$Value)

    if ($Value -notmatch '[\s&|<>^()%!"]') { return $Value }
    return '"' + ($Value -replace '"', '""') + '"'
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 600
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $extension = [IO.Path]::GetExtension($FilePath)
    if ($IsWindows -and $extension -in @('.cmd', '.bat')) {
        $psi.FileName = if ($env:ComSpec) { $env:ComSpec } else { Join-Path $env:SystemRoot 'System32/cmd.exe' }
        [void]$psi.ArgumentList.Add('/d')
        [void]$psi.ArgumentList.Add('/s')
        [void]$psi.ArgumentList.Add('/c')
        $commandLine = @('call', (ConvertTo-CmdToken -Value $FilePath)) + @($ArgumentList | ForEach-Object { ConvertTo-CmdToken -Value ([string]$_) })
        [void]$psi.ArgumentList.Add(($commandLine -join ' '))
    }
    else {
        $psi.FileName = $FilePath
        foreach ($argument in $ArgumentList) {
            [void]$psi.ArgumentList.Add($argument)
        }
    }

    $process = [System.Diagnostics.Process]::new()
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
        Stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        Stderr = $stderrTask.GetAwaiter().GetResult().Trim()
    }
}

function Refresh-NpmPath {
    param([Parameter(Mandatory)][string]$NpmPath)

    $prefixResult = Invoke-CapturedProcess -FilePath $NpmPath -ArgumentList @('prefix', '-g') -TimeoutSeconds 60
    if ($prefixResult.TimedOut -or $prefixResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($prefixResult.Stdout)) {
        throw "Unable to resolve the npm global prefix. stdout=$($prefixResult.Stdout) stderr=$($prefixResult.Stderr)"
    }

    $prefix = ($prefixResult.Stdout -split "`r?`n" | Select-Object -Last 1).Trim()
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @(
        $prefix,
        (Join-Path $prefix 'bin'),
        $(if ($IsWindows -and $env:APPDATA) { Join-Path $env:APPDATA 'npm' })
    )) {
        if ($candidate -and -not $candidates.Contains($candidate)) {
            [void]$candidates.Add($candidate)
        }
    }

    $current = @($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ })
    foreach ($candidate in $candidates) {
        if (-not ($current | Where-Object { $_ -eq $candidate })) {
            $current = @($candidate) + $current
        }
    }
    $env:PATH = $current -join [IO.Path]::PathSeparator
    return $prefix
}

function Resolve-PiCommand {
    $names = if ($IsWindows) { @('pi.cmd', 'pi.exe', 'pi') } else { @('pi') }
    $resolved = Resolve-NativeCommand -Names $names
    if ($resolved) { return $resolved }

    $fileNames = if ($IsWindows) { @('pi.cmd', 'pi.exe') } else { @('pi') }
    foreach ($directory in @($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ })) {
        foreach ($name in $fileNames) {
            $candidate = Join-Path $directory $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }
    return $null
}

function Get-PiVersion {
    param([Parameter(Mandatory)][string]$PiPath)

    $result = Invoke-CapturedProcess -FilePath $PiPath -ArgumentList @('--version') -TimeoutSeconds 60
    if ($result.TimedOut -or $result.ExitCode -ne 0) {
        throw "Pi version probe failed. stdout=$($result.Stdout) stderr=$($result.Stderr)"
    }
    $match = [regex]::Match(($result.Stdout + "`n" + $result.Stderr), '(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if (-not $match.Success) {
        throw "Pi version probe did not return a semantic version. stdout=$($result.Stdout) stderr=$($result.Stderr)"
    }
    return [pscustomobject]@{
        Version = [version]$match.Groups[1].Value
        Raw = (($result.Stdout, $result.Stderr) -join "`n").Trim()
    }
}

try {
    if ($registry.upstream.package -ne $packageName -or [string]$registry.upstream.pinnedVersion -ne $pinnedVersion.ToString()) {
        throw 'Pi registry and upstream verification record disagree on package identity or version.'
    }
    Add-Step -Name 'upstream-contract' -Status 'passed' -Evidence "$packageSpec; Node >= $minimumNodeVersion"

    $nodePath = Resolve-NativeCommand -Names $(if ($IsWindows) { @('node.exe', 'node') } else { @('node') })
    $npmPath = Resolve-NativeCommand -Names $(if ($IsWindows) { @('npm.cmd', 'npm.exe', 'npm') } else { @('npm') })
    if (-not $nodePath) { throw "Node.js is required. Install Node.js $minimumNodeVersion or newer, then rerun this command." }
    if (-not $npmPath) { throw 'A native npm command is required and was not found on PATH.' }

    $nodeProbe = Invoke-CapturedProcess -FilePath $nodePath -ArgumentList @('--version') -TimeoutSeconds 30
    if ($nodeProbe.TimedOut -or $nodeProbe.ExitCode -ne 0) {
        throw "Node version probe failed. stdout=$($nodeProbe.Stdout) stderr=$($nodeProbe.Stderr)"
    }
    $nodeMatch = [regex]::Match($nodeProbe.Stdout, 'v?(\d+\.\d+\.\d+)')
    if (-not $nodeMatch.Success) { throw "Unable to parse Node version from '$($nodeProbe.Stdout)'." }
    $nodeVersion = [version]$nodeMatch.Groups[1].Value
    if ($nodeVersion -lt $minimumNodeVersion) {
        throw "Pi $pinnedVersion requires Node.js $minimumNodeVersion or newer. Found $nodeVersion at $nodePath."
    }
    $summary.node = [ordered]@{ path = $nodePath; version = $nodeVersion.ToString() }
    Add-Step -Name 'node' -Status 'passed' -Evidence "$nodePath :: $nodeVersion"

    $npmProbe = Invoke-CapturedProcess -FilePath $npmPath -ArgumentList @('--version') -TimeoutSeconds 30
    if ($npmProbe.TimedOut -or $npmProbe.ExitCode -ne 0) {
        throw "npm version probe failed. stdout=$($npmProbe.Stdout) stderr=$($npmProbe.Stderr)"
    }
    $npmPrefix = Refresh-NpmPath -NpmPath $npmPath
    $summary.npm = [ordered]@{ path = $npmPath; version = $npmProbe.Stdout.Trim(); globalPrefix = $npmPrefix }
    Add-Step -Name 'npm' -Status 'passed' -Evidence "$npmPath :: $($npmProbe.Stdout.Trim()) :: prefix=$npmPrefix"

    $piPath = Resolve-PiCommand
    $installedVersion = $null
    if ($piPath) { $installedVersion = Get-PiVersion -PiPath $piPath }

    if ($Mode -eq 'Uninstall') {
        if (-not $piPath) {
            Add-Step -Name 'uninstall' -Status 'skipped' -Evidence 'Pi executable is already absent.'
        }
        elseif ($PSCmdlet.ShouldProcess($packageName, 'Uninstall verified global Pi CLI package')) {
            $uninstall = Invoke-CapturedProcess -FilePath $npmPath -ArgumentList @('uninstall', '-g', $packageName) -TimeoutSeconds 600
            $uninstall.Stdout | Set-Content -LiteralPath $stdoutPath -Encoding utf8
            $uninstall.Stderr | Set-Content -LiteralPath $stderrPath -Encoding utf8
            if ($uninstall.TimedOut -or $uninstall.ExitCode -ne 0) {
                throw "Pi uninstall failed. stdout=$stdoutPath stderr=$stderrPath"
            }
            Refresh-NpmPath -NpmPath $npmPath | Out-Null
            if (Resolve-PiCommand) { throw 'Pi executable remains resolvable after npm uninstall.' }
            Add-Step -Name 'uninstall' -Status 'passed' -Evidence "Removed $packageName. Settings, credentials, sessions, and project files were not deleted."
        }
        $summary.status = 'success'
        return
    }

    $needsInstall = $Force -or -not $piPath -or $installedVersion.Version -ne $pinnedVersion
    if ($Mode -eq 'Verify' -and $needsInstall) {
        $found = if ($installedVersion) { $installedVersion.Version.ToString() } else { 'missing' }
        throw "Pi verification failed. Expected $pinnedVersion; found $found. Run Install-AgentSwitchboardPi.ps1 -Mode Install."
    }

    if ($Mode -eq 'Install' -and $needsInstall) {
        if ($PSCmdlet.ShouldProcess($packageSpec, 'Install exact global Pi CLI package with lifecycle scripts disabled')) {
            $install = Invoke-CapturedProcess -FilePath $npmPath -ArgumentList @('install', '-g', '--ignore-scripts', $packageSpec) -TimeoutSeconds 900
            $install.Stdout | Set-Content -LiteralPath $stdoutPath -Encoding utf8
            $install.Stderr | Set-Content -LiteralPath $stderrPath -Encoding utf8
            if ($install.TimedOut -or $install.ExitCode -ne 0) {
                throw "Pi installation failed. stdout=$stdoutPath stderr=$stderrPath"
            }
            Add-Step -Name 'install' -Status 'passed' -Evidence "Installed $packageSpec with --ignore-scripts. stdout=$stdoutPath stderr=$stderrPath"
        }
        Refresh-NpmPath -NpmPath $npmPath | Out-Null
        $piPath = Resolve-PiCommand
        if (-not $piPath) { throw 'npm reported success, but the pi executable is not resolvable.' }
        $installedVersion = Get-PiVersion -PiPath $piPath
    }
    elseif ($Mode -eq 'Install') {
        Add-Step -Name 'install' -Status 'reused' -Evidence "Exact Pi version $pinnedVersion is already installed at $piPath."
    }

    if (-not $piPath -or -not $installedVersion) { throw 'Pi executable or version readback is unavailable.' }
    if ($installedVersion.Version -ne $pinnedVersion) {
        throw "Pi version mismatch after operation. Expected $pinnedVersion; found $($installedVersion.Version)."
    }

    $listProbe = Invoke-CapturedProcess -FilePath $npmPath -ArgumentList @('list', '-g', '--depth=0', $packageName) -TimeoutSeconds 60
    if ($listProbe.TimedOut -or $listProbe.ExitCode -ne 0 -or -not $listProbe.Stdout.Contains("$packageName@$pinnedVersion")) {
        throw "npm package readback failed for $packageSpec. stdout=$($listProbe.Stdout) stderr=$($listProbe.Stderr)"
    }

    $summary.pi = [ordered]@{ path = $piPath; version = $installedVersion.Version.ToString(); rawVersion = $installedVersion.Raw }
    Add-Step -Name 'pi-version' -Status 'passed' -Evidence "$piPath :: $($installedVersion.Raw)"
    Add-Step -Name 'package-readback' -Status 'passed' -Evidence ($listProbe.Stdout -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($packageName) } | Select-Object -First 1)
    $summary.status = 'success'
}
catch {
    $summary.status = 'failed'
    $summary.error = $_.Exception.ToString()
    Add-Step -Name 'pi-installation' -Status 'failed' -Evidence $_.Exception.Message
    Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
    $summary.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    Write-Host ''
    Write-Host ("Status: {0}" -f $summary.status) -ForegroundColor $(if ($summary.status -eq 'success') { 'Green' } else { 'Red' })
    Write-Host "Summary: $summaryPath"
}

if ($summary.status -ne 'success') { exit 1 }
exit 0
