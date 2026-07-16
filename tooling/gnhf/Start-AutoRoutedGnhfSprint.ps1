[CmdletBinding(DefaultParameterSetName = "PromptFile")]
param(
    [string]$RepoPath,
    [Parameter(ParameterSetName = "PromptFile")][string]$PromptPath,
    [Parameter(ParameterSetName = "PromptText")][string]$Prompt,
    [string]$Name = "auto-routed-gnhf",
    [ValidateRange(1, 100)][int]$MaxIterations = 4,
    [ValidateRange(1, 1000000000)][int]$MaxTokens = 250000,
    [string]$StopWhen = "The bounded sprint is committed in the isolated worktree, targeted validation passes, and no unrelated files changed.",
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$PolicyPath,
    [string]$CompatibilityProofPath,
    [bool]$AllowPaid = $true,
    [bool]$HeavyWorkload = $true,
    [switch]$AllowPeakPaid,
    [switch]$ListRoutes,
    [datetime]$AtUtc = [DateTime]::UtcNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-AbsolutePath {
    param([Parameter(Mandatory)][string]$Path)

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded.StartsWith("~")) {
        $expanded = Join-Path $HOME $expanded.Substring(1).TrimStart("\", "/")
    }
    return [IO.Path]::GetFullPath($expanded)
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $Default
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory)][string]$CommandPath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 20
    )

    $result = [ordered]@{
        ExitCode = $null
        TimedOut = $false
        Output = ""
    }

    try {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $CommandPath
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        foreach ($argument in $Arguments) {
            [void]$psi.ArgumentList.Add($argument)
        }

        $process = [Diagnostics.Process]::new()
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

        $result.Output = (($stdoutTask.GetAwaiter().GetResult(), $stderrTask.GetAwaiter().GetResult()) -join [Environment]::NewLine).Trim()
    }
    catch {
        $result.Output = $_.Exception.Message
    }

    return [pscustomobject]$result
}

function Test-UtcWindow {
    param(
        [Parameter(Mandatory)][datetime]$UtcTime,
        [Parameter(Mandatory)][string]$Start,
        [Parameter(Mandatory)][string]$End
    )

    $startTime = [TimeSpan]::ParseExact($Start, "hh\:mm", [Globalization.CultureInfo]::InvariantCulture)
    $endTime = [TimeSpan]::ParseExact($End, "hh\:mm", [Globalization.CultureInfo]::InvariantCulture)
    $now = $UtcTime.ToUniversalTime().TimeOfDay

    if ($startTime -lt $endTime) {
        return ($now -ge $startTime -and $now -lt $endTime)
    }
    return ($now -ge $startTime -or $now -lt $endTime)
}

function Get-CompatibilityProof {
    param(
        [Parameter(Mandatory)][string]$RouteId,
        [string]$ProofPath,
        [datetime]$NowUtc
    )

    if (-not $ProofPath -or -not (Test-Path -LiteralPath $ProofPath -PathType Leaf)) {
        return $false
    }

    try {
        $proof = Get-Content -LiteralPath $ProofPath -Raw | ConvertFrom-Json
        $property = $proof.routes.PSObject.Properties[$RouteId]
        if (-not $property -or $property.Value.status -ne "ready") {
            return $false
        }
        $expiresAt = Get-PropertyValue -InputObject $property.Value -Name "expiresAt"
        if ($expiresAt) {
            return ([datetime]$expiresAt).ToUniversalTime() -gt $NowUtc.ToUniversalTime()
        }
        return $true
    }
    catch {
        return $false
    }
}

if (-not $PolicyPath) {
    $installedPolicy = Join-Path $InstallRoot "model-route-policy.json"
    $repoPolicy = Join-Path $PSScriptRoot "model-route-policy.example.json"
    $PolicyPath = if (Test-Path -LiteralPath $installedPolicy -PathType Leaf) { $installedPolicy } else { $repoPolicy }
}
$PolicyPath = Get-AbsolutePath -Path $PolicyPath
if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
    throw "Model route policy not found: $PolicyPath"
}

if (-not $CompatibilityProofPath) {
    $CompatibilityProofPath = Join-Path $InstallRoot "route-compatibility.json"
}
$CompatibilityProofPath = Get-AbsolutePath -Path $CompatibilityProofPath

$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
if ($policy.schemaVersion -ne 1) {
    throw "Unsupported model route policy schemaVersion: $($policy.schemaVersion)"
}
if (-not $policy.costOrder -or -not $policy.routes) {
    throw "Model route policy must define costOrder and routes."
}

$costRank = @{}
for ($index = 0; $index -lt $policy.costOrder.Count; $index++) {
    $costRank[[string]$policy.costOrder[$index]] = $index
}

$openCodeModels = $null
function Get-OpenCodeModels {
    if ($null -ne $script:openCodeModels) {
        return $script:openCodeModels
    }

    $command = Get-Command opencode -ErrorAction SilentlyContinue
    if (-not $command) {
        $script:openCodeModels = @()
        return $script:openCodeModels
    }

    $probe = Invoke-Probe -CommandPath $command.Source -Arguments @("models", "--refresh") -TimeoutSeconds 60
    if ($probe.TimedOut -or $probe.ExitCode -ne 0) {
        $script:openCodeModels = @()
        return $script:openCodeModels
    }

    $script:openCodeModels = @(
        $probe.Output -split "\r?\n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match "^[A-Za-z0-9._-]+/[A-Za-z0-9][A-Za-z0-9._:/-]*$" } |
            Sort-Object -Unique
    )
    return $script:openCodeModels
}

$routeResults = foreach ($route in $policy.routes) {
    $routeId = [string](Get-PropertyValue -InputObject $route -Name "id" -Default "")
    $enabled = [bool](Get-PropertyValue -InputObject $route -Name "enabled" -Default $false)
    $costClass = [string](Get-PropertyValue -InputObject $route -Name "costClass" -Default "")
    $priority = [int](Get-PropertyValue -InputObject $route -Name "priority" -Default 999)
    $commandName = [string](Get-PropertyValue -InputObject $route -Name "command" -Default "")
    $agentSpec = Get-PropertyValue -InputObject $route -Name "agentSpec"
    $integration = [string](Get-PropertyValue -InputObject $route -Name "integration" -Default "")
    $model = Get-PropertyValue -InputObject $route -Name "model"
    $compatibility = [string](Get-PropertyValue -InputObject $route -Name "gnhfCompatibility" -Default "blocked")
    $probeArgsValue = Get-PropertyValue -InputObject $route -Name "probeArgs" -Default @()
    $pricingPolicyId = Get-PropertyValue -InputObject $route -Name "pricingPolicy"

    $ready = $true
    $reasons = [Collections.Generic.List[string]]::new()

    if (-not $enabled) {
        $ready = $false
        [void]$reasons.Add("disabled")
    }

    if ($costClass -eq "paid" -and -not $AllowPaid) {
        $ready = $false
        [void]$reasons.Add("paid fallback disabled")
    }

    $commandRecord = $null
    if ($commandName) {
        $commandRecord = Get-Command $commandName -ErrorAction SilentlyContinue
        if (-not $commandRecord) {
            $ready = $false
            [void]$reasons.Add("command not found: $commandName")
        }
    }

    if ($ready -and $integration -eq "cli-only") {
        $ready = $false
        [void]$reasons.Add("no proven GNHF adapter")
    }

    if ($ready -and $integration -eq "opencode-model") {
        $models = @(Get-OpenCodeModels)
        if (-not $model -or $models -notcontains [string]$model) {
            $ready = $false
            [void]$reasons.Add("OpenCode model not reported: $model")
        }
    }

    if ($ready -and $compatibility -eq "capability-gated") {
        $probeArgs = @($probeArgsValue | ForEach-Object { [string]$_ })
        $probe = Invoke-Probe -CommandPath $commandRecord.Source -Arguments $probeArgs
        if ($probe.TimedOut -or $probe.ExitCode -ne 0) {
            $ready = $false
            [void]$reasons.Add("capability probe failed")
        }
    }
    elseif ($ready -and $compatibility -eq "runtime-proof-required") {
        if (-not (Get-CompatibilityProof -RouteId $routeId -ProofPath $CompatibilityProofPath -NowUtc $AtUtc)) {
            $ready = $false
            [void]$reasons.Add("green GNHF compatibility proof required")
        }
    }
    elseif ($ready -and $compatibility -eq "blocked") {
        $ready = $false
        [void]$reasons.Add("route is blocked for GNHF")
    }

    if ($ready -and $costClass -eq "paid" -and $pricingPolicyId) {
        $pricingProperty = $policy.pricingPolicies.PSObject.Properties[[string]$pricingPolicyId]
        if (-not $pricingProperty) {
            $ready = $false
            [void]$reasons.Add("pricing policy missing: $pricingPolicyId")
        }
        else {
            $pricing = $pricingProperty.Value
            $pricingMode = [string](Get-PropertyValue -InputObject $pricing -Name "mode" -Default "none")
            if ($pricingMode -eq "time-windows" -and $HeavyWorkload -and -not $AllowPeakPaid) {
                $windows = @(Get-PropertyValue -InputObject $pricing -Name "windowsUtc" -Default @())
                foreach ($window in $windows) {
                    $action = [string](Get-PropertyValue -InputObject $window -Name "action" -Default "")
                    $windowStart = [string](Get-PropertyValue -InputObject $window -Name "start" -Default "")
                    $windowEnd = [string](Get-PropertyValue -InputObject $window -Name "end" -Default "")
                    if ($action -eq "defer-heavy" -and $windowStart -and $windowEnd -and (Test-UtcWindow -UtcTime $AtUtc -Start $windowStart -End $windowEnd)) {
                        $ready = $false
                        [void]$reasons.Add("heavy paid work deferred by verified UTC pricing window $windowStart-$windowEnd")
                        break
                    }
                }
            }
            elseif ($pricingMode -notin @("flat", "none", "time-windows")) {
                $ready = $false
                [void]$reasons.Add("unsupported pricing mode: $pricingMode")
            }
        }
    }

    [pscustomobject]@{
        Id = $routeId
        Ready = $ready
        CostClass = $costClass
        Priority = $priority
        AgentSpec = if ($null -ne $agentSpec) { [string]$agentSpec } else { "" }
        Model = if ($model) { [string]$model } else { $null }
        Integration = $integration
        Reason = if ($reasons.Count -gt 0) { $reasons -join "; " } else { "ready" }
        Route = $route
    }
}

$routeResults = @(
    $routeResults |
        Sort-Object `
            @{ Expression = { if ($costRank.ContainsKey($_.CostClass)) { $costRank[$_.CostClass] } else { 999 } } },
            Priority,
            Id
)

Write-Host "`n=== Agent/model route plan ===" -ForegroundColor Cyan
$routeResults |
    Select-Object Id, Ready, CostClass, Priority, AgentSpec, Model, Reason |
    Format-Table -AutoSize

if ($ListRoutes) {
    return
}

if (-not $RepoPath) {
    throw "-RepoPath is required unless -ListRoutes is used."
}
if (-not $Prompt -and -not $PromptPath) {
    throw "Supply -Prompt or -PromptPath."
}
if ($Prompt -and $PromptPath) {
    throw "Use either -Prompt or -PromptPath, not both."
}

$selected = $routeResults | Where-Object Ready | Select-Object -First 1
if (-not $selected) {
    throw "No GNHF-compatible route is ready. Review the route plan, authenticate the appropriate agent, or record a green compatibility proof."
}

$sprintLauncher = Join-Path $InstallRoot "Start-GnhfSprint.ps1"
if (-not (Test-Path -LiteralPath $sprintLauncher -PathType Leaf)) {
    $sprintLauncher = Join-Path $PSScriptRoot "Start-GnhfSprint.ps1"
}
if (-not (Test-Path -LiteralPath $sprintLauncher -PathType Leaf)) {
    throw "Start-GnhfSprint.ps1 was not found in the installed fleet or repository bundle."
}

$selectionRoot = Join-Path $InstallRoot "route-selections"
New-Item -ItemType Directory -Path $selectionRoot -Force | Out-Null
$selectionPath = Join-Path $selectionRoot ("{0}-{1}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"), $selected.Id)
[ordered]@{
    schemaVersion = 1
    selectedAt = (Get-Date).ToString("o")
    routeId = $selected.Id
    costClass = $selected.CostClass
    agentSpec = $selected.AgentSpec
    model = $selected.Model
    policyPath = $PolicyPath
    compatibilityProofPath = $CompatibilityProofPath
    allowPaid = $AllowPaid
    heavyWorkload = $HeavyWorkload
    allowPeakPaid = [bool]$AllowPeakPaid
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $selectionPath -Encoding utf8NoBOM

Write-Host "`n=== Selected route ===" -ForegroundColor Green
Write-Host "Route:      $($selected.Id)"
Write-Host "Cost class: $($selected.CostClass)"
Write-Host "Agent:      $($selected.AgentSpec)"
Write-Host "Model:      $($selected.Model)"
Write-Host "Evidence:   $selectionPath"

$previousOpenCodeConfig = $env:OPENCODE_CONFIG_CONTENT
try {
    if ($selected.Integration -eq "opencode-model") {
        $runtimeConfig = [ordered]@{
            '$schema' = "https://opencode.ai/config.json"
            model = $selected.Model
            share = "disabled"
        }
        if ($selected.Model.StartsWith("deepseek/", [StringComparison]::OrdinalIgnoreCase)) {
            $runtimeConfig.provider = [ordered]@{
                deepseek = [ordered]@{
                    options = [ordered]@{
                        timeout = 600000
                        chunkTimeout = 60000
                    }
                }
            }
        }
        $env:OPENCODE_CONFIG_CONTENT = $runtimeConfig | ConvertTo-Json -Depth 10 -Compress
    }

    $arguments = @{
        RepoPath = $RepoPath
        Agent = $selected.AgentSpec
        Name = $Name
        MaxIterations = $MaxIterations
        MaxTokens = $MaxTokens
        StopWhen = $StopWhen
        InstallRoot = $InstallRoot
    }
    if ($Prompt) {
        $arguments.Prompt = $Prompt
    }
    else {
        $arguments.PromptPath = $PromptPath
    }

    & $sprintLauncher @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "The selected GNHF route '$($selected.Id)' failed with exit code $LASTEXITCODE. Automatic post-mutation fallback is intentionally disabled; inspect the preserved worktree and logs before retrying another route."
    }
}
finally {
    if ($null -eq $previousOpenCodeConfig) {
        Remove-Item Env:OPENCODE_CONFIG_CONTENT -ErrorAction SilentlyContinue
    }
    else {
        $env:OPENCODE_CONFIG_CONTENT = $previousOpenCodeConfig
    }
}
