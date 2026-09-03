[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputDirectory,
    [switch]$NoNetwork,
    [switch]$NoWrite,
    [switch]$AllowUnready
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

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

function Get-VersionProbe {
    param(
        [string]$Path,
        [string]$Pattern = '(?<!\d)(\d+\.\d+\.\d+)(?!\d)'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $raw = (& $Path --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { return $null }
        $match = [regex]::Match($raw, $Pattern)
        if (-not $match.Success) { return $null }
        return [pscustomobject]@{ version = $match.Groups[1].Value; raw = $raw }
    }
    catch { return $null }
}

function Get-BashPaths {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($IsWindows) {
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

    $raw = (& $NpmPath @Arguments 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        throw "npm command failed: npm $($Arguments -join ' ')"
    }
    return $raw | ConvertFrom-Json
}

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

$verificationPath = Join-Path $RootPath 'tooling/pi/harness/upstream-verification.json'
if (-not (Test-Path -LiteralPath $verificationPath -PathType Leaf)) {
    throw "Tracked Pi upstream verification is missing: $verificationPath"
}
$verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json

$nodePaths = @(Get-NativeCommandPaths -Names $(if ($IsWindows) { @('node.exe', 'node') } else { @('node') }))
$npmPaths = @(Get-NativeCommandPaths -Names $(if ($IsWindows) { @('npm.cmd', 'npm.exe', 'npm') } else { @('npm') }))
$gitPaths = @(Get-NativeCommandPaths -Names $(if ($IsWindows) { @('git.exe', 'git') } else { @('git') }))
$piPaths = @(Get-NativeCommandPaths -Names $(if ($IsWindows) { @('pi.cmd', 'pi.exe', 'pi') } else { @('pi') }))
$bashPaths = @(Get-BashPaths)

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
$nodeReady = $nodeProbe -and ([version]$nodeProbe.version -ge $minimumNode)
$npmReady = [bool]$npmProbe
$gitReady = [bool]$gitProbe
$bashReady = [bool]$bashProbe

$upstreamState = if ($NoNetwork) { 'tracked-only' } else { 'unresolved' }
$upstreamError = $null
$liveVersion = $null
$liveNodeEngine = $null
$legacyVersion = $null
$legacyDeprecated = $null
$legacyMessage = $null

if (-not $NoNetwork) {
    if (-not $npmReady) {
        $upstreamState = 'unavailable'
        $upstreamError = 'npm is unavailable, so live upstream metadata cannot be resolved.'
    }
    else {
        try {
            $live = Invoke-NpmJson -NpmPath $npmPath -Arguments @('view', [string]$verification.package, 'version', 'engines', '--json')
            $legacy = Invoke-NpmJson -NpmPath $npmPath -Arguments @('view', [string]$verification.legacyPackage.package, 'version', 'deprecated', '--json')

            $liveVersionValue = Get-OptionalPropertyValue -InputObject $live -Name 'version'
            $liveEngines = Get-OptionalPropertyValue -InputObject $live -Name 'engines'
            $liveNodeEngineValue = Get-OptionalPropertyValue -InputObject $liveEngines -Name 'node'
            $legacyVersionValue = Get-OptionalPropertyValue -InputObject $legacy -Name 'version'
            $legacyDeprecatedValue = Get-OptionalPropertyValue -InputObject $legacy -Name 'deprecated'

            $liveVersion = if ($null -eq $liveVersionValue) { $null } else { [string]$liveVersionValue }
            $liveNodeEngine = if ($null -eq $liveNodeEngineValue) { $null } else { [string]$liveNodeEngineValue }
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
                -not [string]::IsNullOrWhiteSpace($legacyVersion) -and
                $null -ne $legacyDeprecated -and
                -not [string]::IsNullOrWhiteSpace($legacyMessage)
            )
            $matchesTracked = $metadataShapeComplete -and (
                $liveVersion -eq [string]$verification.version -and
                $liveNodeEngine -eq [string]$verification.nodeEngine -and
                $legacyVersion -eq [string]$verification.legacyPackage.lastObservedVersion -and
                $legacyDeprecated -eq [bool]$verification.legacyPackage.deprecated -and
                $legacyMessage -eq [string]$verification.legacyPackage.deprecatedMessage
            )
            $upstreamState = if ($matchesTracked) { 'live-match' } else { 'drift' }
            if (-not $metadataShapeComplete) {
                $upstreamError = 'Live npm metadata was reachable but missing one or more expected version, engine, or deprecation fields.'
            }
        }
        catch {
            $upstreamState = 'unavailable'
            $upstreamError = $_.Exception.Message
        }
    }
}

$piState = if (-not $piPath) { 'missing' }
elseif (-not $piProbe) { 'unverified' }
elseif ($piProbe.version -eq [string]$verification.version) { 'exact' }
else { 'version-drift' }

$prerequisitesReady = $nodeReady -and $npmReady -and $gitReady -and $bashReady
$status = if (-not $prerequisitesReady) { 'blocked-prerequisite' }
elseif ($NoNetwork) { 'offline-upstream-unverified' }
elseif ($upstreamState -eq 'drift') { 'upstream-drift' }
elseif ($upstreamState -ne 'live-match') { 'upstream-unavailable' }
elseif ($piState -eq 'version-drift' -or $piState -eq 'unverified') { 'installed-version-drift' }
elseif ($piState -eq 'exact') { 'already-installed' }
else { 'ready-to-install' }

$rows = @(
    [pscustomobject]@{ Gate = 'PowerShell'; Result = 'PASS'; Observed = [string]$PSVersionTable.PSVersion },
    [pscustomobject]@{ Gate = 'Node'; Result = if ($nodeReady) { 'PASS' } else { 'FAIL' }; Observed = if ($nodeProbe) { "$($nodeProbe.version) @ $nodePath" } else { 'missing or unverifiable' } },
    [pscustomobject]@{ Gate = 'npm'; Result = if ($npmReady) { 'PASS' } else { 'FAIL' }; Observed = if ($npmProbe) { "$($npmProbe.version) @ $npmPath" } else { 'missing or unverifiable' } },
    [pscustomobject]@{ Gate = 'Git'; Result = if ($gitReady) { 'PASS' } else { 'FAIL' }; Observed = if ($gitProbe) { "$($gitProbe.version) @ $gitPath" } else { 'missing or unverifiable' } },
    [pscustomobject]@{ Gate = 'Bash'; Result = if ($bashReady) { 'PASS' } else { 'FAIL' }; Observed = if ($bashProbe) { "$($bashProbe.version) @ $bashPath" } else { 'missing or unverifiable' } },
    [pscustomobject]@{ Gate = 'Pi'; Result = if ($piState -eq 'exact') { 'PASS' } elseif ($piState -eq 'missing') { 'INFO' } else { 'FAIL' }; Observed = if ($piProbe) { "$($piProbe.version) @ $piPath" } else { $piState } },
    [pscustomobject]@{ Gate = 'Current upstream'; Result = if ($upstreamState -eq 'live-match') { 'PASS' } elseif ($NoNetwork) { 'SKIP' } else { 'FAIL' }; Observed = if ($liveVersion) { "$liveVersion / node $liveNodeEngine" } else { $upstreamState } },
    [pscustomobject]@{ Gate = 'Legacy package'; Result = if ($legacyDeprecated -eq $true) { 'PASS' } elseif ($NoNetwork) { 'SKIP' } else { 'FAIL' }; Observed = if ($legacyVersion) { "$legacyVersion / deprecated=$legacyDeprecated" } else { $upstreamState } }
)

$result = [ordered]@{
    schema = 'agentswitchboard.pi-workstation-prereqs.v1'
    status = $status
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    machine = [ordered]@{
        computerName = [string]$env:COMPUTERNAME
        platform = if ($IsWindows) { 'windows' } else { 'non-windows' }
        powerShell = [string]$PSVersionTable.PSVersion
    }
    trackedUpstream = [ordered]@{
        verifiedAt = [string]$verification.verifiedAt
        package = [string]$verification.package
        version = [string]$verification.version
        nodeEngine = [string]$verification.nodeEngine
        sourceRepository = [string]$verification.sourceRepository
    }
    observed = [ordered]@{
        node = [ordered]@{ ready = [bool]$nodeReady; version = if ($nodeProbe) { $nodeProbe.version } else { $null }; paths = $nodePaths }
        npm = [ordered]@{ ready = [bool]$npmReady; version = if ($npmProbe) { $npmProbe.version } else { $null }; paths = $npmPaths }
        git = [ordered]@{ ready = [bool]$gitReady; version = if ($gitProbe) { $gitProbe.version } else { $null }; paths = $gitPaths }
        bash = [ordered]@{ ready = [bool]$bashReady; version = if ($bashProbe) { $bashProbe.version } else { $null }; paths = $bashPaths }
        pi = [ordered]@{ state = $piState; version = if ($piProbe) { $piProbe.version } else { $null }; paths = $piPaths }
        upstream = [ordered]@{ state = $upstreamState; version = $liveVersion; nodeEngine = $liveNodeEngine; error = $upstreamError }
        legacyPackage = [ordered]@{ version = $legacyVersion; deprecated = $legacyDeprecated; message = $legacyMessage }
    }
    installDecision = [ordered]@{
        ready = ($status -eq 'ready-to-install')
        command = if ($status -eq 'ready-to-install') { [string]$verification.installCommand } else { $null }
    }
    proofCeiling = 'Read-only local prerequisite and live npm metadata proof. This does not install Pi, mutate Pi configuration, authenticate a provider, prove a model response, or establish endpoint privacy.'
}

Write-Host "`n=== PI WORKSTATION PREREQUISITES ===" -ForegroundColor Cyan
$rows | Format-Table -AutoSize | Out-Host
Write-Host "Decision: $status"
Write-Host "Tracked package: $($verification.package)@$($verification.version)"
Write-Host "npm resolution: $($npmPaths -join '; ')"
if ($upstreamError) { Write-Host "Upstream note: $upstreamError" }
if ($status -eq 'ready-to-install') { Write-Host "Verified install command: $($verification.installCommand)" }

if (-not $NoWrite) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/PiHarness/prereqs'
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $jsonPath = Join-Path $OutputDirectory 'pi-workstation-prereqs.json'
    $mdPath = Join-Path $OutputDirectory 'pi-workstation-prereqs.md'
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8

    $markdown = @(
        '# Pi Workstation Prerequisites',
        '',
        "- Status: $status",
        "- Tracked package: $($verification.package)@$($verification.version)",
        "- Minimum Node: $($verification.minimumNodeVersion)",
        "- npm paths: $($npmPaths -join '; ')",
        "- Bash paths: $($bashPaths -join '; ')",
        "- Pi state: $piState",
        "- Upstream state: $upstreamState",
        '',
        '## Proof ceiling',
        $result.proofCeiling
    )
    $markdown | Set-Content -LiteralPath $mdPath -Encoding utf8
    Write-Host "JSON: $jsonPath"
    Write-Host "Report: $mdPath"
}

if ($AllowUnready) { exit 0 }
if ($status -in @('ready-to-install', 'already-installed')) { exit 0 }
exit 1
