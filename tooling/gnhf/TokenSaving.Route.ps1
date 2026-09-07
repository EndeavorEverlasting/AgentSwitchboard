Set-StrictMode -Version Latest

function Resolve-AgentSwitchboardBuilderRoute {
    [CmdletBinding()]
    param(
        [ValidateSet("Auto", "agy", "opencode", "hermes")][string]$Requested = "Auto",
        [Parameter(Mandatory)]$State
    )

    $chain = if ($Requested -eq "Auto") { @("agy", "opencode", "hermes") } else { @($Requested.ToLowerInvariant()) }
    $skipped = [System.Collections.Generic.List[object]]::new()
    foreach ($id in $chain) {
        $property = $State.agents.PSObject.Properties[$id]
        if (-not $property) {
            [void]$skipped.Add([pscustomobject]@{ route = $id; reason = "no fleet state record" })
            continue
        }
        $record = $property.Value
        if ($record.available) {
            return [pscustomobject]@{
                schema = "agentswitchboard.builder-route-resolution.v1"
                status = "selected"
                requested = $Requested
                route = $id
                evidence = [string]$record.evidence
                skipped = @($skipped)
            }
        }
        [void]$skipped.Add([pscustomobject]@{ route = $id; reason = [string]$record.evidence })
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
