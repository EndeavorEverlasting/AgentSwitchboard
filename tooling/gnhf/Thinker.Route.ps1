Set-StrictMode -Version Latest

function Import-AgentSwitchboardThinkerPolicy {
    [CmdletBinding()]
    param(
        [string]$PolicyPath = (Join-Path $PSScriptRoot "thinker-route.policy.json")
    )

    if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
        throw "Thinker route policy not found: $PolicyPath"
    }
    $policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
    if ($policy.schema -ne "agentswitchboard.thinker-route-policy.v1") {
        throw "Unsupported thinker route policy schema: $($policy.schema)"
    }
    return $policy
}

function Resolve-AgentSwitchboardThinkerMode {
    [CmdletBinding()]
    param(
        [ValidateSet("Auto", "Standard", "Free")][string]$Mode = "Auto",
        [Parameter(Mandatory)]$Policy
    )

    if ($Mode -eq "Free") { return "free" }
    if ($Mode -eq "Standard") { return "standard" }

    $freeMode = [Environment]::GetEnvironmentVariable("AGENT_SWITCHBOARD_FREE_MODE", "Process")
    if ($freeMode -match '^(?i:1|true|yes|on)$') {
        return "free"
    }
    return [string]$Policy.defaultMode
}

function Resolve-AgentSwitchboardThinkerRoute {
    [CmdletBinding()]
    param(
        [ValidateSet("Auto", "Standard", "Free")][string]$Mode = "Auto",
        [string]$PolicyPath = (Join-Path $PSScriptRoot "thinker-route.policy.json"),
        [hashtable]$ReadinessOverride
    )

    $policy = Import-AgentSwitchboardThinkerPolicy -PolicyPath $PolicyPath
    $resolvedMode = Resolve-AgentSwitchboardThinkerMode -Mode $Mode -Policy $policy
    $chainProperty = $policy.chains.PSObject.Properties[$resolvedMode]
    if (-not $chainProperty) {
        throw "Thinker policy does not define mode '$resolvedMode'."
    }

    $routesById = @{}
    foreach ($route in @($policy.routes)) {
        if ($routesById.ContainsKey([string]$route.id)) {
            throw "Duplicate thinker route id '$($route.id)'."
        }
        $routesById[[string]$route.id] = $route
    }

    $skipped = [System.Collections.Generic.List[object]]::new()
    foreach ($routeIdValue in @($chainProperty.Value)) {
        $routeId = [string]$routeIdValue
        if (-not $routesById.ContainsKey($routeId)) {
            throw "Thinker chain '$resolvedMode' references unknown route '$routeId'."
        }
        $route = $routesById[$routeId]

        $available = $false
        $evidence = $null
        if ($null -ne $ReadinessOverride -and $ReadinessOverride.ContainsKey($routeId)) {
            $available = [bool]$ReadinessOverride[$routeId]
            $evidence = "readiness override=$available"
        }
        else {
            $command = Get-Command ([string]$route.command) -ErrorAction SilentlyContinue
            $available = $null -ne $command
            $evidence = if ($available) { "command=$($command.Source)" } else { "command '$($route.command)' not found" }
        }

        if ($available) {
            return [pscustomobject]@{
                schema = "agentswitchboard.thinker-route-resolution.v1"
                status = "selected"
                mode = $resolvedMode
                route = $route
                readinessEvidence = $evidence
                skipped = @($skipped)
            }
        }

        [void]$skipped.Add([pscustomobject]@{
            routeId = $routeId
            reason = $evidence
        })
    }

    return [pscustomobject]@{
        schema = "agentswitchboard.thinker-route-resolution.v1"
        status = "blocked"
        mode = $resolvedMode
        route = $null
        readinessEvidence = "no eligible thinker route"
        skipped = @($skipped)
    }
}
