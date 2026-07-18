Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ProviderRouteRequiredCapabilities = @(
    "gnhf.executable",
    "gnhf.agent.opencode",
    "gnhf.worktree",
    "gnhf.max-iterations",
    "gnhf.max-tokens",
    "gnhf.prevent-sleep",
    "gnhf.stop-when",
    "opencode.model-selection",
    "provider.route.launchers"
)

function Get-ProviderRouteRequiredCapabilities {
    return @($script:ProviderRouteRequiredCapabilities)
}

function ConvertTo-GnhfVersion {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, '(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if (-not $match.Success) { return $null }
    return [version]$match.Groups[1].Value
}

function Get-GnhfCliFlagMap {
    param([AllowNull()][string]$HelpText)
    $flags = [ordered]@{
        agent = $false
        worktree = $false
        "max-iterations" = $false
        "max-tokens" = $false
        "prevent-sleep" = $false
        "stop-when" = $false
        model = $false
        push = $false
        "current-branch" = $false
        mock = $false
    }
    if ([string]::IsNullOrWhiteSpace($HelpText)) {
        return [pscustomobject]$flags
    }
    foreach ($name in @($flags.Keys)) {
        $pattern = '(?m)^\s*(?:-[A-Za-z],\s*)?--' + [regex]::Escape($name) + '\b'
        $flags[$name] = ($HelpText -match $pattern)
    }
    return [pscustomobject]$flags
}

function Test-NpmVersionPublished {
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string[]]$PublishedVersions
    )
    return ($PublishedVersions -contains $Version)
}

function Get-GnhfNpmDistributionFacts {
    [CmdletBinding()]
    param(
        [hashtable]$Injected = $null
    )

    if ($null -ne $Injected) {
        return [pscustomobject]@{
            npmDistTags = $Injected.npmDistTags
            npmLatest = $Injected.npmLatest
            npmPublishedVersions = @($Injected.npmPublishedVersions)
            querySucceeded = [bool]$Injected.querySucceeded
            queryError = [string]$Injected.queryError
        }
    }

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        return [pscustomobject]@{
            npmDistTags = $null
            npmLatest = $null
            npmPublishedVersions = @()
            querySucceeded = $false
            queryError = "npm command unavailable"
        }
    }

    try {
        $tagsJson = & $npm.Source view gnhf dist-tags --json 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "dist-tags query failed: $tagsJson" }
        $versionsJson = & $npm.Source view gnhf versions --json 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "versions query failed: $versionsJson" }
        $latestText = (& $npm.Source view gnhf version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw "version query failed: $latestText" }

        $tags = $tagsJson | ConvertFrom-Json
        $versions = @($versionsJson | ConvertFrom-Json)
        return [pscustomobject]@{
            npmDistTags = $tags
            npmLatest = $latestText
            npmPublishedVersions = @($versions | ForEach-Object { [string]$_ })
            querySucceeded = $true
            queryError = $null
        }
    }
    catch {
        return [pscustomobject]@{
            npmDistTags = $null
            npmLatest = $null
            npmPublishedVersions = @()
            querySucceeded = $false
            queryError = $_.Exception.Message
        }
    }
}

function Get-GnhfInstalledRuntimeFacts {
    [CmdletBinding()]
    param(
        [hashtable]$Injected = $null
    )

    if ($null -ne $Injected) {
        return [pscustomobject]@{
            commandPath = $Injected.commandPath
            version = $(if ($Injected.version) { [version]$Injected.version } else { $null })
            versionOutput = [string]$Injected.versionOutput
            helpText = [string]$Injected.helpText
            cliFlags = Get-GnhfCliFlagMap -HelpText ([string]$Injected.helpText)
        }
    }

    $command = Get-Command gnhf -ErrorAction SilentlyContinue
    if (-not $command) {
        return [pscustomobject]@{
            commandPath = $null
            version = $null
            versionOutput = $null
            helpText = $null
            cliFlags = Get-GnhfCliFlagMap -HelpText $null
        }
    }

    $versionOutput = (& $command.Source --version 2>&1 | Out-String).Trim()
    $helpText = (& $command.Source --help 2>&1 | Out-String)
    return [pscustomobject]@{
        commandPath = $command.Source
        version = ConvertTo-GnhfVersion -Text $versionOutput
        versionOutput = $versionOutput
        helpText = $helpText
        cliFlags = Get-GnhfCliFlagMap -HelpText $helpText
    }
}

function Test-ProviderRouteCapabilityMatrix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InstalledRuntime,
        [Parameter(Mandatory)][bool]$LaunchersPresent,
        [Parameter(Mandatory)][bool]$OpenCodeModelSelectionAvailable
    )

    $flags = $InstalledRuntime.cliFlags
    $observed = [ordered]@{
        "gnhf.executable" = @{
            state = $(if ($InstalledRuntime.commandPath -and $InstalledRuntime.version) { "verified" } else { "absent" })
            evidence = $(if ($InstalledRuntime.version) { "version $($InstalledRuntime.version)" } else { "gnhf unavailable" })
        }
        "gnhf.agent.opencode" = @{
            state = $(if ($InstalledRuntime.helpText -match '(?i)\bopencode\b') { "verified" } else { "absent" })
            evidence = "help agent list"
        }
        "gnhf.worktree" = @{
            state = $(if ($flags.worktree) { "verified" } else { "absent" })
            evidence = "--worktree"
        }
        "gnhf.max-iterations" = @{
            state = $(if ($flags.'max-iterations') { "verified" } else { "absent" })
            evidence = "--max-iterations"
        }
        "gnhf.max-tokens" = @{
            state = $(if ($flags.'max-tokens') { "verified" } else { "absent" })
            evidence = "--max-tokens"
        }
        "gnhf.prevent-sleep" = @{
            state = $(if ($flags.'prevent-sleep') { "verified" } else { "absent" })
            evidence = "--prevent-sleep"
        }
        "gnhf.stop-when" = @{
            state = $(if ($flags.'stop-when') { "verified" } else { "absent" })
            evidence = "--stop-when"
        }
        "gnhf.cli.model" = @{
            state = $(if ($flags.model) { "verified" } else { "absent" })
            evidence = "--model (optional; OpenCode owns model selection)"
        }
        "opencode.model-selection" = @{
            state = $(if ($OpenCodeModelSelectionAvailable) { "verified" } else { "absent" })
            evidence = "OPENCODE_CONFIG_CONTENT and/or opencode run --model"
        }
        "provider.route.launchers" = @{
            state = $(if ($LaunchersPresent) { "verified" } else { "absent" })
            evidence = "Start-ProviderRoutedGnhfSprint.ps1 + Gnhf.Process.ps1 + provider cmd"
        }
    }

    $required = Get-ProviderRouteRequiredCapabilities
    $missing = @(
        foreach ($name in $required) {
            if ($observed[$name].state -ne "verified") { $name }
        }
    )
    $runtimeMissing = @($missing | Where-Object { $_ -ne "provider.route.launchers" })

    return [pscustomobject]@{
        required = $required
        observed = [pscustomobject]$observed
        missing = $missing
        runtimeMissing = $runtimeMissing
        ready = ($missing.Count -eq 0)
        repairRequired = ($missing.Count -gt 0)
        runtimeRepairRequired = ($runtimeMissing.Count -gt 0)
        launcherRepairRequired = ($missing -contains "provider.route.launchers")
    }
}

function Select-GnhfDistributionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$NpmFacts,
        [Parameter(Mandatory)]$InstalledRuntime,
        [Parameter(Mandatory)]$CapabilityMatrix,
        [string]$RequestedNpmVersion
    )

    $plan = [ordered]@{
        action = "keep-installed"
        selectedSource = "installed-existing"
        selectedPackageSpec = $null
        installFromNpm = $false
        reason = $null
        failureClass = $null
    }

    # Explicit version requests are validated against npm publication facts first.
    # Upstream source package.json is never treated as publication proof.
    if ($RequestedNpmVersion) {
        if (-not ($NpmFacts.querySucceeded -and (Test-NpmVersionPublished -Version $RequestedNpmVersion -PublishedVersions $NpmFacts.npmPublishedVersions))) {
            $plan.failureClass = "BLOCKED_DISTRIBUTION_UNAVAILABLE"
            $plan.action = "blocked"
            $plan.installFromNpm = $false
            $plan.selectedSource = "none"
            $plan.reason = "Requested gnhf@$RequestedNpmVersion is not published on npm (or npm query failed: $($NpmFacts.queryError)). Source package.json is not publication proof."
            return [pscustomobject]$plan
        }
    }

    if (-not $CapabilityMatrix.runtimeRepairRequired -and $InstalledRuntime.commandPath -and -not $RequestedNpmVersion) {
        $plan.action = "refresh-launchers"
        $plan.reason = "Installed GNHF satisfies runtime capabilities; launchers will be staged and promoted without npm mutation."
        $plan.selectedPackageSpec = $(if ($InstalledRuntime.version) { "gnhf@$($InstalledRuntime.version)" } else { $null })
        $plan.installFromNpm = $false
        return [pscustomobject]$plan
    }

    if (-not $InstalledRuntime.commandPath) {
        $plan.action = "install-runtime"
        $plan.installFromNpm = $true
    }
    elseif ($RequestedNpmVersion) {
        $plan.action = "select-requested-published"
        $plan.installFromNpm = $true
    }
    else {
        $plan.action = "repair-runtime"
        $plan.installFromNpm = $true
    }

    $targetVersion = $null
    if ($RequestedNpmVersion) {
        $targetVersion = $RequestedNpmVersion
    }
    elseif ($NpmFacts.querySucceeded -and $NpmFacts.npmLatest) {
        $targetVersion = [string]$NpmFacts.npmLatest
    }
    else {
        if ($InstalledRuntime.commandPath -and $InstalledRuntime.version) {
            # Keep existing runtime when registry is unavailable; launcher install may still proceed if capabilities otherwise pass.
            $plan.action = "keep-installed"
            $plan.installFromNpm = $false
            $plan.selectedSource = "installed-existing"
            $plan.selectedPackageSpec = "gnhf@$($InstalledRuntime.version)"
            $plan.reason = "npm registry unavailable; preserving installed runtime. $($NpmFacts.queryError)"
            $plan.failureClass = $(if ($CapabilityMatrix.runtimeRepairRequired) { "BLOCKED_RUNTIME_CAPABILITY" } else { $null })
            return [pscustomobject]$plan
        }
        $plan.action = "blocked"
        $plan.installFromNpm = $false
        $plan.selectedSource = "none"
        $plan.failureClass = "BLOCKED_DISTRIBUTION_UNAVAILABLE"
        $plan.reason = "No installed GNHF and npm registry query failed: $($NpmFacts.queryError)"
        return [pscustomobject]$plan
    }

    $plan.selectedSource = "npm-published"
    $plan.selectedPackageSpec = "gnhf@$targetVersion"
    $plan.reason = "Install or select published package $($plan.selectedPackageSpec) after capability comparison (not version guessing)."
    return [pscustomobject]$plan
}

function New-GnhfRuntimeCapabilityDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)]$NpmFacts,
        [Parameter(Mandatory)]$InstalledRuntime,
        [Parameter(Mandatory)]$CapabilityMatrix,
        [Parameter(Mandatory)]$DistributionPlan,
        [string]$UpstreamSourceVersion = $null,
        [string]$UpstreamSourceCommit = $null,
        [string]$FailureClass = $null,
        [string]$RollbackInstructions = $null
    )

    $capabilityPath = Join-Path $InstallRoot "gnhf-runtime-capability.json"
    return [ordered]@{
        schema = "agentswitchboard.gnhf-runtime-capability.v1"
        schemaVersion = 1
        generatedUtc = [DateTime]::UtcNow.ToString("o")
        installRoot = $InstallRoot
        distribution = [ordered]@{
            npmDistTags = $NpmFacts.npmDistTags
            npmLatest = $NpmFacts.npmLatest
            npmPublishedVersions = @($NpmFacts.npmPublishedVersions)
            installedVersion = $(if ($InstalledRuntime.version) { $InstalledRuntime.version.ToString() } else { $null })
            installedCommandPath = $InstalledRuntime.commandPath
            upstreamSourceVersion = $UpstreamSourceVersion
            upstreamSourceCommit = $UpstreamSourceCommit
            selectedSource = $DistributionPlan.selectedSource
            selectedPackageSpec = $DistributionPlan.selectedPackageSpec
            provenanceNote = "npm publication, installed binary, and upstream source version are independent facts."
        }
        cliFlags = $InstalledRuntime.cliFlags
        requiredCapabilities = @($CapabilityMatrix.required)
        observedCapabilities = $CapabilityMatrix.observed
        modelSelection = [ordered]@{
            authority = "opencode"
            mechanisms = @("OPENCODE_CONFIG_CONTENT", "opencode run --model")
            gnhfCliModelFlag = [bool]$InstalledRuntime.cliFlags.model
        }
        launchers = [ordered]@{
            providerCmd = (Join-Path $InstallRoot "agent-switchboard-provider.cmd")
            providerPs1 = (Join-Path $InstallRoot "Start-ProviderRoutedGnhfSprint.ps1")
            processHelpers = (Join-Path $InstallRoot "Gnhf.Process.ps1")
            capabilityDocument = $capabilityPath
        }
        ready = [bool]$CapabilityMatrix.ready
        missingCapabilities = @($CapabilityMatrix.missing)
        failureClass = $FailureClass
        rollbackInstructions = $RollbackInstructions
        proofCeiling = "Installed capability document proves distribution discovery and launcher presence only. It does not prove provider quota, GNHF delivery, merge, or deployment."
    }
}
