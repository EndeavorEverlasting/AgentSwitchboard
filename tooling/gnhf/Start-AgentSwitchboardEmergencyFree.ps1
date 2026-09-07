[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$ObjectivePath,
    [Parameter(Mandatory)][ValidateLength(1, 4000)][string]$ValidationCommand,
    [ValidateRange(1, 2)][int]$MaxInitialIterations = 2,
    [ValidateRange(0, 1)][int]$MaxRepairCycles = 1,
    [ValidateRange(1000, 50000)][int]$MaxTokensPerBuilderRun = 50000,
    [ValidateRange(500, 3000)][int]$MaxFailureChars = 3000,
    [ValidateRange(5, 120)][int]$ModelProbeTimeoutSeconds = 30,
    [ValidateRange(5, 3600)][int]$ValidatorTimeoutSeconds = 900,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -lt 7) { throw "PowerShell 7 is required." }

$policyPath = Join-Path $PSScriptRoot "thinker-route.policy.json"
$processHelpers = Join-Path $PSScriptRoot "Gnhf.Process.ps1"
$loopLauncher = Join-Path $PSScriptRoot "Start-AgentSwitchboardTokenSavingLoop.ps1"
foreach ($path in @($policyPath, $processHelpers, $loopLauncher)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Emergency-free runtime dependency not found: $path"
    }
}
. $processHelpers

function Invoke-BoundedModelList {
    param(
        [Parameter(Mandatory)][string]$CommandPath,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $psi = New-GnhfProcessStartInfo -FilePath $CommandPath -ArgumentList @("models", $Provider) -WorkingDirectory $WorkingDirectory
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            try { $process.Kill($true) } catch {}
            try { $process.WaitForExit(5000) | Out-Null } catch {}
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($timedOut) { throw "OpenCode model discovery timed out for provider '$Provider'." }
        if ($process.ExitCode -ne 0) {
            throw "OpenCode model discovery failed for provider '$Provider': $($stderr.Trim())"
        }
        return $stdout
    }
    finally { $process.Dispose() }
}

$RepoPath = [IO.Path]::GetFullPath($RepoPath)
$ObjectivePath = [IO.Path]::GetFullPath($ObjectivePath)
if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) { throw "Repository not found: $RepoPath" }
if (-not (Test-Path -LiteralPath $ObjectivePath -PathType Leaf)) { throw "Objective file not found: $ObjectivePath" }

$openCode = Get-Command opencode -ErrorAction SilentlyContinue
if (-not $openCode) {
    throw "Emergency free mode requires OpenCode. Run AgentSwitchboard setup/repair first."
}

$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
if ($policy.schema -ne "agentswitchboard.thinker-route-policy.v1") {
    throw "Unsupported thinker policy schema: $($policy.schema)"
}
$routesById = @{}
foreach ($route in @($policy.routes)) { $routesById[[string]$route.id] = $route }

$providerOutputs = @{}
$selected = $null
$reasons = [System.Collections.Generic.List[string]]::new()
foreach ($routeIdValue in @($policy.chains.free)) {
    $routeId = [string]$routeIdValue
    if (-not $routesById.ContainsKey($routeId)) {
        [void]$reasons.Add("$routeId: policy route missing")
        continue
    }
    $route = $routesById[$routeId]
    if ($route.costClass -ne "free" -or $route.runner -ne "opencode-run") {
        [void]$reasons.Add("$routeId: route is not an OpenCode free route")
        continue
    }
    $provider = [string]$route.probeProvider
    try {
        if (-not $providerOutputs.ContainsKey($provider)) {
            $providerOutputs[$provider] = Invoke-BoundedModelList -CommandPath $openCode.Source -Provider $provider -WorkingDirectory $RepoPath -TimeoutSeconds $ModelProbeTimeoutSeconds
        }
        $modelPattern = '(?m)^\s*' + [regex]::Escape([string]$route.model) + '\s*$'
        if ($providerOutputs[$provider] -match $modelPattern) {
            $selected = $route
            break
        }
        [void]$reasons.Add("$routeId: exact model not listed")
    }
    catch {
        [void]$reasons.Add("$routeId: $($_.Exception.Message)")
    }
}

if (-not $selected) {
    throw "No verified free OpenCode model is currently available. $(@($reasons) -join '; ')"
}

$originalFreeMode = [Environment]::GetEnvironmentVariable("AGENT_SWITCHBOARD_FREE_MODE", "Process")
$originalOpenCodeConfig = [Environment]::GetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", "Process")
try {
    $inlineConfig = [ordered]@{
        '$schema' = "https://opencode.ai/config.json"
        model = [string]$selected.model
    }
    if (-not [string]::IsNullOrWhiteSpace($originalOpenCodeConfig)) {
        try {
            $existingConfig = $originalOpenCodeConfig | ConvertFrom-Json -AsHashtable
            if ($null -eq $existingConfig) { throw "inline config is empty" }
            $existingConfig["model"] = [string]$selected.model
            if (-not $existingConfig.ContainsKey('$schema')) {
                $existingConfig['$schema'] = "https://opencode.ai/config.json"
            }
            $inlineConfig = $existingConfig
        }
        catch {
            throw "Existing OPENCODE_CONFIG_CONTENT is not valid JSON and cannot be safely preserved: $($_.Exception.Message)"
        }
    }

    [Environment]::SetEnvironmentVariable("AGENT_SWITCHBOARD_FREE_MODE", "1", "Process")
    [Environment]::SetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", ($inlineConfig | ConvertTo-Json -Depth 20 -Compress), "Process")

    Write-Host "EMERGENCY FREE TOKEN GUARD" -ForegroundColor Cyan
    Write-Host "Thinker: free chain only"
    Write-Host "Builder: OpenCode"
    Write-Host "Model:   $($selected.model)"
    Write-Host "Caps:    initial=$MaxInitialIterations repair=$MaxRepairCycles tokens/run=$MaxTokensPerBuilderRun failureChars=$MaxFailureChars"

    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $loopLauncher `
        -RepoPath $RepoPath `
        -ObjectivePath $ObjectivePath `
        -ThinkerMode Free `
        -BuilderAgent opencode `
        -ValidationCommand $ValidationCommand `
        -MaxInitialIterations $MaxInitialIterations `
        -MaxRepairCycles $MaxRepairCycles `
        -MaxTokensPerBuilderRun $MaxTokensPerBuilderRun `
        -MaxFailureChars $MaxFailureChars `
        -ValidatorTimeoutSeconds $ValidatorTimeoutSeconds `
        -InstallRoot $InstallRoot
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    [Environment]::SetEnvironmentVariable("AGENT_SWITCHBOARD_FREE_MODE", $originalFreeMode, "Process")
    [Environment]::SetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", $originalOpenCodeConfig, "Process")
}

exit 0
