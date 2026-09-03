[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputDirectory,
    [ValidateRange(1, 120)][int]$ProbeTimeoutSeconds = 15,
    [switch]$NoNetwork,
    [switch]$NoWrite,
    [switch]$AllowUnready
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

function Get-OptionalPropertyValue {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-NativeCommandPaths {
    param([Parameter(Mandatory)][string[]]$Names)

    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $Names) {
        foreach ($command in @(Get-Command $name -All -ErrorAction SilentlyContinue)) {
            $source = [string]$command.Source
            if ([string]::IsNullOrWhiteSpace($source) -or $source -like '*.ps1') { continue }
            if (-not $paths.Contains($source)) { [void]$paths.Add($source) }
        }
    }
    return @($paths)
}

function Invoke-BoundedProbe {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][int]$Timeout
    )

    $result = [ordered]@{
        exitCode = $null
        timedOut = $false
        startError = $null
        output = ''
    }

    $process = $null
    try {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardInput = $true
        $psi.CreateNoWindow = $true

        if ($FilePath.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase)) {
            $pwsh = Get-Command pwsh -ErrorAction Stop
            $psi.FileName = $pwsh.Source
            foreach ($prefix in @('-NoLogo', '-NoProfile', '-File', $FilePath)) {
                [void]$psi.ArgumentList.Add($prefix)
            }
        }
        elseif ($FilePath.EndsWith('.cmd', [StringComparison]::OrdinalIgnoreCase) -or $FilePath.EndsWith('.bat', [StringComparison]::OrdinalIgnoreCase)) {
            $cmd = if ($env:ComSpec) { $env:ComSpec } else { (Get-Command cmd.exe -ErrorAction Stop).Source }
            $psi.FileName = $cmd
            foreach ($prefix in @('/d', '/s', '/c', $FilePath)) {
                [void]$psi.ArgumentList.Add($prefix)
            }
        }
        else {
            $psi.FileName = $FilePath
        }

        foreach ($argument in $ArgumentList) {
            [void]$psi.ArgumentList.Add($argument)
        }

        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($Timeout * 1000)) {
            $result.timedOut = $true
            try { $process.Kill($true) } catch {}
            try { $process.WaitForExit() } catch {}
        }
        else {
            $result.exitCode = $process.ExitCode
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $combined = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
        if ($combined.Length -gt 16384) {
            $combined = $combined.Substring(0, 16384) + "`n<output truncated>"
        }
        $result.output = $combined
    }
    catch {
        $result.startError = $_.Exception.Message
    }
    finally {
        if ($process) { $process.Dispose() }
    }

    return [pscustomobject]$result
}

function Get-VersionProbe {
    param(
        [string]$Path,
        [string]$Pattern = '(?<!\d)(\d+\.\d+\.\d+)(?!\d)'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [pscustomobject]@{ state = 'missing'; version = $null; raw = $null; exitCode = $null; timedOut = $false; startError = $null }
    }

    $probe = Invoke-BoundedProbe -FilePath $Path -ArgumentList @('--version') -Timeout $ProbeTimeoutSeconds
    $state = if ($probe.timedOut) { 'timeout' }
    elseif ($probe.startError) { 'start-error' }
    elseif ($probe.exitCode -ne 0) { 'nonzero-exit' }
    elseif ([string]::IsNullOrWhiteSpace([string]$probe.output)) { 'empty-output' }
    else { 'completed' }

    $version = $null
    if ($state -eq 'completed') {
        $match = [regex]::Match([string]$probe.output, $Pattern)
        if ($match.Success) { $version = $match.Groups[1].Value }
        else { $state = 'unparseable-version' }
    }

    return [pscustomobject]@{
        state = $state
        version = $version
        raw = if ($state -eq 'completed') { [string]$probe.output } else { $null }
        exitCode = $probe.exitCode
        timedOut = [bool]$probe.timedOut
        startError = $probe.startError
    }
}

function Get-ProjectShellPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $settingsPath = Join-Path $RepositoryRoot '.pi/settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { return $null }
    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $configured = Get-OptionalPropertyValue -InputObject $settings -Name 'shellPath'
        if ([string]::IsNullOrWhiteSpace([string]$configured)) { return $null }
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$configured)
        if (-not [System.IO.Path]::IsPathRooted($expanded)) {
            $expanded = Join-Path $RepositoryRoot $expanded
        }
        if (Test-Path -LiteralPath $expanded -PathType Leaf) {
            return (Resolve-Path -LiteralPath $expanded).Path
        }
    }
    catch { return $null }
    return $null
}

function Get-BashPaths {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($IsWindows) {
        $configuredShellPath = Get-ProjectShellPath -RepositoryRoot $RepositoryRoot
        if ($configuredShellPath -and -not $candidates.Contains($configuredShellPath)) {
            [void]$candidates.Add($configuredShellPath)
        }
        foreach ($candidate in @(
            $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Git\bin\bash.exe' }),
            $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe' })
        )) {
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf) -and -not $candidates.Contains($candidate)) {
                [void]$candidates.Add($candidate)
            }
        }
    }
    foreach ($path in @(Get-NativeCommandPaths -Names $(if ($IsWindows) { @('bash.exe', 'bash') } else { @('bash') }))) {
        if (-not $candidates.Contains($path)) { [void]$candidates.Add($path) }
    }
    return @($candidates)
}

function Invoke-NpmJson {
    param(
        [Parameter(Mandatory)][string]$NpmPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $probe = Invoke-BoundedProbe -FilePath $NpmPath -ArgumentList $Arguments -Timeout $ProbeTimeoutSeconds
    if ($probe.timedOut) {
        return [pscustomobject]@{ state = 'timeout'; value = $null; error = "npm probe timed out after $ProbeTimeoutSeconds second(s)."; exitCode = $null }
    }
    if ($probe.startError) {
        return [pscustomobject]@{ state = 'start-error'; value = $null; error = $probe.startError; exitCode = $null }
    }
    if ($probe.exitCode -ne 0) {
        return [pscustomobject]@{ state = 'nonzero-exit'; value = $null; error = "npm probe exited with code $($probe.exitCode)."; exitCode = $probe.exitCode }
    }
    if ([string]::IsNullOrWhiteSpace([string]$probe.output)) {
        return [pscustomobject]@{ state = 'empty-output'; value = $null; error = 'npm probe returned no JSON.'; exitCode = $probe.exitCode }
    }
    try {
        return [pscustomobject]@{ state = 'completed'; value = ([string]$probe.output | ConvertFrom-Json); error = $null; exitCode = $probe.exitCode }
    }
    catch {
        return [pscustomobject]@{ state = 'invalid-json'; value = $null; error = $_.Exception.Message; exitCode = $probe.exitCode }
    }
}

function Normalize-RepositoryUrl {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    $text = if ($Value -is [string]) { [string]$Value } else { [string](Get-OptionalPropertyValue -InputObject $Value -Name 'url') }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $text = $text.Trim()
    if ($text.StartsWith('git+', [StringComparison]::OrdinalIgnoreCase)) { $text = $text.Substring(4) }
    if ($text.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) { $text = $text.Substring(0, $text.Length - 4) }
    return $text.TrimEnd('/')
}

function Get-BoundedPathEvidence {
    param(
        [AllowNull()][string[]]$Paths,
        [ValidateRange(1, 50)][int]$Limit = 8
    )

    $all = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $visible = @($all | Select-Object -First $Limit)
    return [ordered]@{
        state = if ($all.Count -eq 0) { 'empty' } else { 'present' }
        total = $all.Count
        omitted = [Math]::Max(0, $all.Count - $visible.Count)
        paths = @($visible)
    }
}

function Format-BoundedPathEvidence {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Evidence)

    if ([int]$Evidence.total -eq 0) { return '<none>' }
    $text = (@($Evidence.paths) -join '; ')
    if ([int]$Evidence.omitted -gt 0) { $text += " (+$($Evidence.omitted) omitted)" }
    return $text
}

function Get-AbsolutePath {
    param([Parameter(Mandatory)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Test-PathInsideRoot {
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Root
    )

    $candidateFull = (Get-AbsolutePath -Path $Candidate).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $rootFull = (Get-AbsolutePath -Path $Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($candidateFull.Equals($rootFull, $comparison)) { return $true }
    $rootPrefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    return $candidateFull.StartsWith($rootPrefix, $comparison)
}

function Save-PreflightReport {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Result,
        [Parameter(Mandatory)][string[]]$MarkdownLines
    )

    if ($NoWrite) { return }
    $null = New-Item -ItemType Directory -Path $script:ResolvedOutputDirectory -Force
    $jsonPath = Join-Path $script:ResolvedOutputDirectory 'pi-workstation-prereqs.json'
    $mdPath = Join-Path $script:ResolvedOutputDirectory 'pi-workstation-prereqs.md'
    $Result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    $MarkdownLines | Set-Content -LiteralPath $mdPath -Encoding utf8
    Write-Host "JSON: $jsonPath"
    Write-Host "Report: $mdPath"
}

$ResolvedOutputDirectory = $null
if (-not $NoWrite) {
    $candidateOutputDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/PiHarness/prereqs'
    }
    else {
        $OutputDirectory
    }
    $ResolvedOutputDirectory = Get-AbsolutePath -Path $candidateOutputDirectory
    if (Test-PathInsideRoot -Candidate $ResolvedOutputDirectory -Root $RootPath) {
        Write-Error "[OUTPUT_DIRECTORY_INSIDE_REPOSITORY] Pi workstation evidence must remain outside the repository: $ResolvedOutputDirectory"
        exit 1
    }
}

$verificationRelativePath = 'tooling/pi/harness/upstream-verification.json'
$verificationPath = Join-Path $RootPath $verificationRelativePath
if (-not (Test-Path -LiteralPath $verificationPath -PathType Leaf)) {
    $result = [ordered]@{
        schema = 'agentswitchboard.pi-workstation-prereqs.v1'
        status = 'blocked-prerequisite'
        repository = 'EndeavorEverlasting/AgentSwitchboard'
        root = $RootPath
        error = [ordered]@{
            code = 'UPSTREAM_VERIFICATION_MISSING'
            message = "Tracked Pi upstream verification is missing: $verificationPath"
        }
        recoveryAction = "Restore $verificationRelativePath from the current repository revision, then rerun this preflight."
        proofCeiling = 'No workstation install decision can be made without the tracked upstream verification record.'
    }
    Write-Host "`n=== PI WORKSTATION PREREQUISITES ===" -ForegroundColor Cyan
    Write-Host 'Decision: blocked-prerequisite'
    Write-Host "Error: $($result.error.code)"
    Write-Host "Recovery: $($result.recoveryAction)"
    Save-PreflightReport -Result $result -MarkdownLines @(
        '# Pi Workstation Prerequisites', '', '- Status: blocked-prerequisite', "- Error: $($result.error.code)", "- Recovery: $($result.recoveryAction)", '', '## Proof ceiling', $result.proofCeiling
    )
    exit 1
}

try {
    $verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json
}
catch {
    $result = [ordered]@{
        schema = 'agentswitchboard.pi-workstation-prereqs.v1'
        status = 'blocked-prerequisite'
        repository = 'EndeavorEverlasting/AgentSwitchboard'
        root = $RootPath
        error = [ordered]@{
            code = 'UPSTREAM_VERIFICATION_INVALID'
            message = $_.Exception.Message
        }
        recoveryAction = "Repair or restore $verificationRelativePath from the current repository revision, then rerun this preflight."
        proofCeiling = 'No workstation install decision can be made from an unreadable upstream verification record.'
    }
    Write-Host "`n=== PI WORKSTATION PREREQUISITES ===" -ForegroundColor Cyan
    Write-Host 'Decision: blocked-prerequisite'
    Write-Host "Error: $($result.error.code)"
    Write-Host "Recovery: $($result.recoveryAction)"
    Save-PreflightReport -Result $result -MarkdownLines @(
        '# Pi Workstation Prerequisites', '', '- Status: blocked-prerequisite', "- Error: $($result.error.code)", "- Recovery: $($result.recoveryAction)", '', '## Proof ceiling', $result.proofCeiling
    )
    exit 1
}

$currentPlatform = if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } elseif ($IsMacOS) { 'macOS' } else { 'Unknown' }
$requiredVerificationStrings = @(
    [string]$verification.package,
    [string]$verification.version,
    [string]$verification.versionTag,
    [string]$verification.sourceRepository,
    [string]$verification.sourceUrl,
    [string]$verification.minimumNodeVersion,
    [string]$verification.nodeEngine,
    [string]$verification.executable,
    [string]$verification.installCommand,
    [string]$verification.rollbackCommand,
    [string]$verification.expectedExecutableMapping.command,
    [string]$verification.expectedExecutableMapping.packageRelativePath
)
$verificationComplete = -not ($requiredVerificationStrings | Where-Object { [string]::IsNullOrWhiteSpace($_) })
$verificationComplete = $verificationComplete -and @($verification.supportedOperatingSystems).Count -gt 0
$verificationComplete = $verificationComplete -and @($verification.expectedFiles).Count -gt 0
$verificationComplete = $verificationComplete -and @($verification.officialEvidence).Count -gt 0
$verificationComplete = $verificationComplete -and (@($verification.supportedOperatingSystems) -contains $currentPlatform)
if (-not $verificationComplete) {
    $result = [ordered]@{
        schema = 'agentswitchboard.pi-workstation-prereqs.v1'
        status = 'blocked-prerequisite'
        repository = 'EndeavorEverlasting/AgentSwitchboard'
        root = $RootPath
        error = [ordered]@{
            code = 'UPSTREAM_VERIFICATION_INCOMPLETE'
            message = "Tracked Pi upstream verification is incomplete for platform '$currentPlatform'."
        }
        recoveryAction = "Complete the official upstream adoption evidence in $verificationRelativePath before installation is eligible."
        proofCeiling = 'No workstation install decision can be made from an incomplete upstream adoption record.'
    }
    Write-Host "`n=== PI WORKSTATION PREREQUISITES ===" -ForegroundColor Cyan
    Write-Host 'Decision: blocked-prerequisite'
    Write-Host "Error: $($result.error.code)"
    Write-Host "Recovery: $($result.recoveryAction)"
    Save-PreflightReport -Result $result -MarkdownLines @(
        '# Pi Workstation Prerequisites', '', '- Status: blocked-prerequisite', "- Error: $($result.error.code)", "- Recovery: $($result.recoveryAction)", '', '## Proof ceiling', $result.proofCeiling
    )
    exit 1
}

$nodePaths = @(Get-NativeCommandPaths -Names $(if ($IsWindows) { @('node.exe', 'node') } else { @('node') }))
$npmPaths = @(Get-NativeCommandPaths -Names $(if ($IsWindows) { @('npm.cmd', 'npm.exe', 'npm') } else { @('npm') }))
$gitPaths = @(Get-NativeCommandPaths -Names $(if ($IsWindows) { @('git.exe', 'git') } else { @('git') }))
$piPaths = @(Get-NativeCommandPaths -Names $(if ($IsWindows) { @('pi.cmd', 'pi.exe', 'pi') } else { @('pi') }))
$bashPaths = @(Get-BashPaths -RepositoryRoot $RootPath)

$nodePathEvidence = Get-BoundedPathEvidence -Paths $nodePaths
$npmPathEvidence = Get-BoundedPathEvidence -Paths $npmPaths
$gitPathEvidence = Get-BoundedPathEvidence -Paths $gitPaths
$piPathEvidence = Get-BoundedPathEvidence -Paths $piPaths
$bashPathEvidence = Get-BoundedPathEvidence -Paths $bashPaths

$nodePath = $nodePaths | Select-Object -First 1
$npmPath = $npmPaths | Select-Object -First 1
$gitPath = $gitPaths | Select-Object -First 1
$piPath = $piPaths | Select-Object -First 1
$bashPath = $bashPaths | Select-Object -First 1

$nodeProbe = Get-VersionProbe -Path $nodePath -Pattern 'v?(\d+\.\d+\.\d+)'
$npmProbe = Get-VersionProbe -Path $npmPath
$gitProbe = Get-VersionProbe -Path $gitPath -Pattern '(\d+\.\d+\.\d+)'
$piProbe = Get-VersionProbe -Path $piPath
$bashProbe = Get-VersionProbe -Path $bashPath -Pattern '(\d+\.\d+(?:\.\d+)?)'

$minimumNode = [version]([string]$verification.minimumNodeVersion)
$nodeReady = -not [string]::IsNullOrWhiteSpace([string]$nodeProbe.version) -and ([version]$nodeProbe.version -ge $minimumNode)
$npmReady = -not [string]::IsNullOrWhiteSpace([string]$npmProbe.version)
$gitReady = -not [string]::IsNullOrWhiteSpace([string]$gitProbe.version)
$bashReady = -not [string]::IsNullOrWhiteSpace([string]$bashProbe.version)

$upstreamState = if ($NoNetwork) { 'tracked-only' } else { 'unresolved' }
$upstreamError = $null
$upstreamFailureCode = $null
$liveVersion = $null
$liveNodeEngine = $null
$liveRepositoryUrl = $null
$liveExecutablePath = $null
$legacyVersion = $null
$legacyDeprecated = $null
$legacyMessage = $null

if (-not $NoNetwork) {
    if (-not $npmReady) {
        $upstreamState = 'unavailable'
        $upstreamFailureCode = if ($npmProbe.timedOut) { 'NPM_VERSION_PROBE_TIMEOUT' } else { 'NPM_UNAVAILABLE' }
        $upstreamError = "npm is unavailable for live upstream metadata. Probe state: $($npmProbe.state)."
    }
    else {
        $liveProbe = Invoke-NpmJson -NpmPath $npmPath -Arguments @('view', [string]$verification.package, 'version', 'engines', 'repository', 'bin', '--json')
        $legacyProbe = Invoke-NpmJson -NpmPath $npmPath -Arguments @('view', [string]$verification.legacyPackage.package, 'version', 'deprecated', '--json')
        if ($liveProbe.state -ne 'completed' -or $legacyProbe.state -ne 'completed') {
            $upstreamState = 'unavailable'
            $failedProbe = if ($liveProbe.state -ne 'completed') { $liveProbe } else { $legacyProbe }
            $upstreamFailureCode = if ($failedProbe.state -eq 'timeout') { 'UPSTREAM_PROBE_TIMEOUT' } else { 'UPSTREAM_PROBE_FAILED' }
            $upstreamError = $failedProbe.error
        }
        else {
            $live = $liveProbe.value
            $legacy = $legacyProbe.value
            $liveVersionValue = Get-OptionalPropertyValue -InputObject $live -Name 'version'
            $liveEngines = Get-OptionalPropertyValue -InputObject $live -Name 'engines'
            $liveNodeEngineValue = Get-OptionalPropertyValue -InputObject $liveEngines -Name 'node'
            $liveRepository = Get-OptionalPropertyValue -InputObject $live -Name 'repository'
            $liveBin = Get-OptionalPropertyValue -InputObject $live -Name 'bin'
            $liveExecutableValue = Get-OptionalPropertyValue -InputObject $liveBin -Name ([string]$verification.executable)
            $legacyVersionValue = Get-OptionalPropertyValue -InputObject $legacy -Name 'version'
            $legacyDeprecatedValue = Get-OptionalPropertyValue -InputObject $legacy -Name 'deprecated'

            $liveVersion = if ($null -eq $liveVersionValue) { $null } else { [string]$liveVersionValue }
            $liveNodeEngine = if ($null -eq $liveNodeEngineValue) { $null } else { [string]$liveNodeEngineValue }
            $liveRepositoryUrl = Normalize-RepositoryUrl -Value $liveRepository
            $liveExecutablePath = if ($null -eq $liveExecutableValue) { $null } else { [string]$liveExecutableValue }
            $legacyVersion = if ($null -eq $legacyVersionValue) { $null } else { [string]$legacyVersionValue }
            $legacyMessage = if ($null -eq $legacyDeprecatedValue) { $null } else { [string]$legacyDeprecatedValue }
            $legacyDeprecated = if ($legacyDeprecatedValue -is [bool]) {
                [bool]$legacyDeprecatedValue
            }
            elseif ($legacyDeprecatedValue -is [string]) {
                -not [string]::IsNullOrWhiteSpace($legacyMessage)
            }
            else {
                $null
            }

            $metadataShapeComplete = (
                -not [string]::IsNullOrWhiteSpace($liveVersion) -and
                -not [string]::IsNullOrWhiteSpace($liveNodeEngine) -and
                -not [string]::IsNullOrWhiteSpace($liveRepositoryUrl) -and
                -not [string]::IsNullOrWhiteSpace($liveExecutablePath) -and
                -not [string]::IsNullOrWhiteSpace($legacyVersion) -and
                $null -ne $legacyDeprecated -and
                -not [string]::IsNullOrWhiteSpace($legacyMessage)
            )
            $trackedRepositoryUrl = Normalize-RepositoryUrl -Value ([string]$verification.sourceUrl)
            $matchesTracked = $metadataShapeComplete -and (
                $liveVersion -eq [string]$verification.version -and
                $liveNodeEngine -eq [string]$verification.nodeEngine -and
                $liveRepositoryUrl -eq $trackedRepositoryUrl -and
                $liveExecutablePath -eq [string]$verification.expectedExecutableMapping.packageRelativePath -and
                $legacyVersion -eq [string]$verification.legacyPackage.lastObservedVersion -and
                $legacyDeprecated -eq [bool]$verification.legacyPackage.deprecated -and
                $legacyMessage -eq [string]$verification.legacyPackage.deprecatedMessage
            )
            $upstreamState = if ($matchesTracked) { 'live-match' } else { 'drift' }
            if (-not $metadataShapeComplete) {
                $upstreamFailureCode = 'UPSTREAM_METADATA_INCOMPLETE'
                $upstreamError = 'Live npm metadata was reachable but missing one or more expected version, engine, repository, executable, or deprecation fields.'
            }
            elseif (-not $matchesTracked) {
                $upstreamFailureCode = 'UPSTREAM_METADATA_DRIFT'
                $upstreamError = 'Live npm metadata differs from the tracked upstream adoption record.'
            }
        }
    }
}

$piState = if (-not $piPath) { 'missing' }
elseif ([string]::IsNullOrWhiteSpace([string]$piProbe.version)) { if ($piProbe.timedOut) { 'probe-timeout' } else { 'unverified' } }
elseif ($piProbe.version -eq [string]$verification.version) { 'exact' }
else { 'version-drift' }

$prerequisitesReady = $nodeReady -and $npmReady -and $gitReady -and $bashReady
$status = if (-not $prerequisitesReady) { 'blocked-prerequisite' }
elseif ($NoNetwork) { 'offline-upstream-unverified' }
elseif ($upstreamState -eq 'drift') { 'upstream-drift' }
elseif ($upstreamState -ne 'live-match') { 'upstream-unavailable' }
elseif ($piState -in @('version-drift', 'unverified', 'probe-timeout')) { 'installed-version-drift' }
elseif ($piState -eq 'exact') { 'already-installed' }
else { 'ready-to-install' }

$rows = @(
    [pscustomobject]@{ Gate = 'PowerShell'; Result = 'PASS'; Observed = [string]$PSVersionTable.PSVersion },
    [pscustomobject]@{ Gate = 'Node'; Result = if ($nodeReady) { 'PASS' } else { 'FAIL' }; Observed = if ($nodeReady) { "$($nodeProbe.version) @ $nodePath" } else { "$($nodeProbe.state) @ $nodePath" } },
    [pscustomobject]@{ Gate = 'npm'; Result = if ($npmReady) { 'PASS' } else { 'FAIL' }; Observed = if ($npmReady) { "$($npmProbe.version) @ $npmPath" } else { "$($npmProbe.state) @ $npmPath" } },
    [pscustomobject]@{ Gate = 'Git'; Result = if ($gitReady) { 'PASS' } else { 'FAIL' }; Observed = if ($gitReady) { "$($gitProbe.version) @ $gitPath" } else { "$($gitProbe.state) @ $gitPath" } },
    [pscustomobject]@{ Gate = 'Bash'; Result = if ($bashReady) { 'PASS' } else { 'FAIL' }; Observed = if ($bashReady) { "$($bashProbe.version) @ $bashPath" } else { "$($bashProbe.state) @ $bashPath" } },
    [pscustomobject]@{ Gate = 'Pi'; Result = if ($piState -eq 'exact') { 'PASS' } elseif ($piState -eq 'missing') { 'INFO' } else { 'FAIL' }; Observed = if ($piState -eq 'missing') { 'missing' } else { "$piState @ $piPath" } },
    [pscustomobject]@{ Gate = 'Current upstream'; Result = if ($upstreamState -eq 'live-match') { 'PASS' } elseif ($NoNetwork) { 'SKIP' } else { 'FAIL' }; Observed = if ($liveVersion) { "$liveVersion / node $liveNodeEngine / $liveRepositoryUrl" } else { $upstreamState } },
    [pscustomobject]@{ Gate = 'Legacy package'; Result = if ($legacyDeprecated -eq $true) { 'PASS' } elseif ($NoNetwork) { 'SKIP' } else { 'FAIL' }; Observed = if ($legacyVersion) { "$legacyVersion / deprecated=$legacyDeprecated" } else { $upstreamState } }
)

$result = [ordered]@{
    schema = 'agentswitchboard.pi-workstation-prereqs.v1'
    status = $status
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    root = $RootPath
    machine = [ordered]@{
        computerName = [string]$env:COMPUTERNAME
        platform = $currentPlatform
        powerShell = [string]$PSVersionTable.PSVersion
    }
    trackedUpstream = [ordered]@{
        verifiedAt = [string]$verification.verifiedAt
        package = [string]$verification.package
        version = [string]$verification.version
        nodeEngine = [string]$verification.nodeEngine
        sourceRepository = [string]$verification.sourceRepository
        sourceUrl = [string]$verification.sourceUrl
        rollbackCommand = [string]$verification.rollbackCommand
        expectedFiles = @($verification.expectedFiles)
    }
    observed = [ordered]@{
        node = [ordered]@{ ready = [bool]$nodeReady; version = $nodeProbe.version; probeState = $nodeProbe.state; timedOut = [bool]$nodeProbe.timedOut; pathState = $nodePathEvidence.state; pathCount = $nodePathEvidence.total; pathsOmitted = $nodePathEvidence.omitted; paths = $nodePathEvidence.paths }
        npm = [ordered]@{ ready = [bool]$npmReady; version = $npmProbe.version; probeState = $npmProbe.state; timedOut = [bool]$npmProbe.timedOut; pathState = $npmPathEvidence.state; pathCount = $npmPathEvidence.total; pathsOmitted = $npmPathEvidence.omitted; paths = $npmPathEvidence.paths }
        git = [ordered]@{ ready = [bool]$gitReady; version = $gitProbe.version; probeState = $gitProbe.state; timedOut = [bool]$gitProbe.timedOut; pathState = $gitPathEvidence.state; pathCount = $gitPathEvidence.total; pathsOmitted = $gitPathEvidence.omitted; paths = $gitPathEvidence.paths }
        bash = [ordered]@{ ready = [bool]$bashReady; version = $bashProbe.version; probeState = $bashProbe.state; timedOut = [bool]$bashProbe.timedOut; pathState = $bashPathEvidence.state; pathCount = $bashPathEvidence.total; pathsOmitted = $bashPathEvidence.omitted; paths = $bashPathEvidence.paths }
        pi = [ordered]@{ state = $piState; version = $piProbe.version; probeState = $piProbe.state; timedOut = [bool]$piProbe.timedOut; pathState = $piPathEvidence.state; pathCount = $piPathEvidence.total; pathsOmitted = $piPathEvidence.omitted; paths = $piPathEvidence.paths }
        upstream = [ordered]@{ state = $upstreamState; version = $liveVersion; nodeEngine = $liveNodeEngine; repositoryUrl = $liveRepositoryUrl; executablePath = $liveExecutablePath; failureCode = $upstreamFailureCode; error = $upstreamError }
        legacyPackage = [ordered]@{ version = $legacyVersion; deprecated = $legacyDeprecated; message = $legacyMessage }
    }
    installDecision = [ordered]@{
        ready = ($status -eq 'ready-to-install')
        command = if ($status -eq 'ready-to-install') { [string]$verification.installCommand } else { $null }
        rollbackCommand = if ($status -eq 'ready-to-install') { [string]$verification.rollbackCommand } else { $null }
    }
    probeTimeoutSeconds = $ProbeTimeoutSeconds
    proofCeiling = 'Read-only local prerequisite and bounded live npm metadata proof. This does not install Pi, mutate Pi configuration, authenticate a provider, prove a model response, or establish endpoint privacy.'
}

Write-Host "`n=== PI WORKSTATION PREREQUISITES ===" -ForegroundColor Cyan
$rows | Format-Table -AutoSize | Out-Host
Write-Host "Decision: $status"
Write-Host "Tracked package: $($verification.package)@$($verification.version)"
Write-Host "npm resolution: $(Format-BoundedPathEvidence -Evidence $npmPathEvidence)"
if ($upstreamFailureCode) { Write-Host "Upstream classification: $upstreamFailureCode" }
if ($upstreamError) { Write-Host "Upstream note: $upstreamError" }
if ($status -eq 'ready-to-install') { Write-Host "Verified install command: $($verification.installCommand)" }

$markdown = @(
    '# Pi Workstation Prerequisites',
    '',
    "- Status: $status",
    "- Tracked package: $($verification.package)@$($verification.version)",
    "- Minimum Node: $($verification.minimumNodeVersion)",
    "- Probe timeout: $ProbeTimeoutSeconds second(s)",
    "- Node paths: $(Format-BoundedPathEvidence -Evidence $nodePathEvidence)",
    "- npm paths: $(Format-BoundedPathEvidence -Evidence $npmPathEvidence)",
    "- Git paths: $(Format-BoundedPathEvidence -Evidence $gitPathEvidence)",
    "- Bash paths: $(Format-BoundedPathEvidence -Evidence $bashPathEvidence)",
    "- Pi paths: $(Format-BoundedPathEvidence -Evidence $piPathEvidence)",
    "- Pi state: $piState",
    "- Upstream state: $upstreamState",
    "- Upstream failure code: $upstreamFailureCode",
    '',
    '## Proof ceiling',
    $result.proofCeiling
)
Save-PreflightReport -Result $result -MarkdownLines $markdown

if ($AllowUnready) { exit 0 }
if ($status -in @('ready-to-install', 'already-installed')) { exit 0 }
exit 1
