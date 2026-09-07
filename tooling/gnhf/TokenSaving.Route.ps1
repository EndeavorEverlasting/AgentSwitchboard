Set-StrictMode -Version Latest

function Get-AgentSwitchboardOptionalProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if (-not $property) { return $Default }
    return $property.Value
}

function Resolve-AgentSwitchboardBuilderRoute {
    [CmdletBinding()]
    param(
        [ValidateSet("Auto", "agy", "opencode", "hermes")][string]$Requested = "Auto",
        [Parameter(Mandatory)]$State
    )

    $chain = if ($Requested -eq "Auto") { @("agy", "opencode", "hermes") } else { @($Requested.ToLowerInvariant()) }
    $skipped = [System.Collections.Generic.List[object]]::new()
    $agents = Get-AgentSwitchboardOptionalProperty -InputObject $State -Name "agents"
    foreach ($id in $chain) {
        if ($null -eq $agents) {
            [void]$skipped.Add([pscustomobject]@{ route = $id; reason = "fleet state is missing agents" })
            continue
        }

        $property = $agents.PSObject.Properties[$id]
        if (-not $property) {
            [void]$skipped.Add([pscustomobject]@{ route = $id; reason = "no fleet state record" })
            continue
        }
        $record = $property.Value
        $availableValue = Get-AgentSwitchboardOptionalProperty -InputObject $record -Name "available"
        $hasAvailable = $null -ne $availableValue
        $evidenceValue = Get-AgentSwitchboardOptionalProperty -InputObject $record -Name "evidence" -Default "fleet state record has no evidence"
        $evidence = if ([string]::IsNullOrWhiteSpace([string]$evidenceValue)) { "fleet state record has no evidence" } else { [string]$evidenceValue }

        if (-not $hasAvailable) {
            [void]$skipped.Add([pscustomobject]@{ route = $id; reason = "fleet state record is missing available" })
            continue
        }
        if ([bool]$availableValue) {
            return [pscustomobject]@{
                schema = "agentswitchboard.builder-route-resolution.v1"
                status = "selected"
                requested = $Requested
                route = $id
                evidence = $evidence
                skipped = @($skipped)
            }
        }
        [void]$skipped.Add([pscustomobject]@{ route = $id; reason = $evidence })
    }

    return [pscustomobject]@{
        schema = "agentswitchboard.builder-route-resolution.v1"
        status = "blocked"
        requested = $Requested
        route = $null
        evidence = "no eligible builder route"
        skipped = @($skipped)
    }
}

function Get-AgentSwitchboardBuilderExecutionIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet("agy", "opencode", "hermes")][string]$Route,
        [Parameter(Mandatory)]$State,
        [ValidateSet("initial-builder", "repair-builder")][string]$Role = "initial-builder"
    )

    $agents = Get-AgentSwitchboardOptionalProperty -InputObject $State -Name "agents"
    $record = if ($agents) {
        $property = $agents.PSObject.Properties[$Route]
        if ($property) { $property.Value } else { $null }
    }
    else { $null }

    $agentSpec = [string](Get-AgentSwitchboardOptionalProperty -InputObject $record -Name "agentSpec" -Default "UNKNOWN_RUNTIME_NOT_EXPOSED")
    $commandPath = [string](Get-AgentSwitchboardOptionalProperty -InputObject $record -Name "commandPath" -Default "UNKNOWN_RUNTIME_NOT_EXPOSED")
    $integration = [string](Get-AgentSwitchboardOptionalProperty -InputObject $record -Name "integration" -Default "UNKNOWN_RUNTIME_NOT_EXPOSED")

    $model = "UNKNOWN_RUNTIME_NOT_EXPOSED"
    $providerClass = "UNKNOWN_RUNTIME_NOT_EXPOSED"
    $modelSource = "not-exposed"
    if ($Route -eq "opencode") {
        $inlineConfig = [Environment]::GetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", "Process")
        if (-not [string]::IsNullOrWhiteSpace($inlineConfig)) {
            try {
                $config = $inlineConfig | ConvertFrom-Json
                $modelValue = Get-AgentSwitchboardOptionalProperty -InputObject $config -Name "model"
                if (-not [string]::IsNullOrWhiteSpace([string]$modelValue)) {
                    $model = [string]$modelValue
                    $modelSource = "OPENCODE_CONFIG_CONTENT"
                    if ($model.Contains("/")) {
                        $providerClass = $model.Split("/", 2)[0]
                    }
                }
            }
            catch {
                $modelSource = "OPENCODE_CONFIG_CONTENT_INVALID_JSON"
            }
        }
    }

    $endpointClass = if ($agentSpec.StartsWith("acp:", [StringComparison]::OrdinalIgnoreCase)) {
        "acp"
    }
    elseif ($agentSpec -ne "UNKNOWN_RUNTIME_NOT_EXPOSED") {
        "native-cli"
    }
    elseif ($integration -ne "UNKNOWN_RUNTIME_NOT_EXPOSED") {
        $integration
    }
    else {
        "UNKNOWN_RUNTIME_NOT_EXPOSED"
    }

    return [pscustomobject]@{
        schema = "agentswitchboard.builder-execution-identity.v1"
        role = $Role
        route = $Route
        providerClass = $providerClass
        model = $model
        modelSource = $modelSource
        endpointClass = $endpointClass
        agentSpec = $agentSpec
        commandPath = $commandPath
        integration = $integration
    }
}

function Get-AgentSwitchboardGitWorktreePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoPath)

    $output = & git -C $RepoPath worktree list --porcelain 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git worktree list failed: $($output -join [Environment]::NewLine)"
    }
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($output)) {
        $text = [string]$line
        if ($text.StartsWith("worktree ")) {
            $path = $text.Substring(9).Trim()
            if ($path) { [void]$paths.Add([IO.Path]::GetFullPath($path)) }
        }
    }
    return @($paths)
}

function Get-AgentSwitchboardSha256Text {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function New-AgentSwitchboardFailureEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ValidationNumber,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][bool]$TimedOut,
        [Parameter(Mandatory)][string]$Output,
        [Parameter(Mandatory)][string]$WorktreePath,
        [Parameter(Mandatory)][string]$HeadSha,
        [ValidateRange(500, 20000)][int]$MaxFailureChars = 6000
    )

    $excerpt = if ($Output.Length -le $MaxFailureChars) { $Output } else { $Output.Substring($Output.Length - $MaxFailureChars) }
    return [pscustomobject]@{
        schema = "agentswitchboard.validation-failure-envelope.v1"
        validationNumber = $ValidationNumber
        exitCode = $ExitCode
        timedOut = $TimedOut
        outputSha256 = Get-AgentSwitchboardSha256Text -Text $Output
        outputChars = $Output.Length
        excerptChars = $excerpt.Length
        worktreePath = $WorktreePath
        headSha = $HeadSha
        excerpt = $excerpt
    }
}
