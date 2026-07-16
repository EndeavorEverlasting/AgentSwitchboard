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
        if ($CommandPath.EndsWith(".cmd", [StringComparison]::OrdinalIgnoreCase) -or $CommandPath.EndsWith(".bat", [StringComparison]::OrdinalIgnoreCase)) {
            $psi.FileName = "cmd.exe"
            [void]$psi.ArgumentList.Add("/c")
            [void]$psi.ArgumentList.Add($CommandPath)
        }
        else {
            $psi.FileName = $CommandPath
        }
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

function Invoke-GitLines {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = @(& git -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Get-FallbackSnapshot {
    param([Parameter(Mandatory)][string]$Repository)

    $branches = @{}
    foreach ($line in @(Invoke-GitLines -Repository $Repository -Arguments @("for-each-ref", "--format=%(refname:short)|%(objectname)", "refs/heads/gnhf"))) {
        if ($line -match '^([^|]+)\|([0-9a-f]+)$') {
            $branches[$Matches[1]] = $Matches[2]
        }
    }

    $worktrees = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $pendingPath = $null
    foreach ($line in @(Invoke-GitLines -Repository $Repository -Arguments @("worktree", "list", "--porcelain"))) {
        if ($line -match '^worktree\s+(.+)$') {
            $pendingPath = [IO.Path]::GetFullPath($Matches[1])
            [void]$worktrees.Add($pendingPath)
        }
    }

    return [pscustomobject]@{
        Head = (Invoke-GitLines -Repository $Repository -Arguments @("rev-parse", "HEAD") | Select-Object -First 1).Trim()
        Branches = $branches
        Worktrees = $worktrees
    }
}

function Test-NoMutationAfterFailure {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)]$Before
    )

    $dirty = @(Invoke-GitLines -Repository $Repository -Arguments @("status", "--porcelain=v1") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($dirty.Count -gt 0) {
        return [pscustomobject]@{ Safe = $false; Reason = "base repository is dirty" }
    }

    $currentHead = (Invoke-GitLines -Repository $Repository -Arguments @("rev-parse", "HEAD") | Select-Object -First 1).Trim()
    if ($currentHead -ne $Before.Head) {
        return [pscustomobject]@{ Safe = $false; Reason = "base HEAD changed" }
    }

    foreach ($line in @(Invoke-GitLines -Repository $Repository -Arguments @("for-each-ref", "--format=%(refname:short)|%(objectname)", "refs/heads/gnhf"))) {
        if ($line -notmatch '^([^|]+)\|([0-9a-f]+)$') {
            continue
        }
        $branchName = $Matches[1]
        $branchHead = $Matches[2]
        if ($Before.Branches.ContainsKey($branchName) -and $Before.Branches[$branchName] -eq $branchHead) {
            continue
        }
        $ahead = [int]((Invoke-GitLines -Repository $Repository -Arguments @("rev-list", "--count", "$($Before.Head)..$branchName") | Select-Object -First 1).Trim())
        if ($ahead -gt 0) {
            return [pscustomobject]@{ Safe = $false; Reason = "route created commits on $branchName" }
        }
    }

    $afterWorktrees = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in @(Invoke-GitLines -Repository $Repository -Arguments @("worktree", "list", "--porcelain"))) {
        if ($line -match '^worktree\s+(.+)$') {
            [void]$afterWorktrees.Add([IO.Path]::GetFullPath($Matches[1]))
        }
    }
    foreach ($path in $afterWorktrees) {
        if (-not $Before.Worktrees.Contains($path)) {
            return [pscustomobject]@{ Safe = $false; Reason = "route left a new worktree for review: $path" }
        }
    }

    return [pscustomobject]@{ Safe = $true; Reason = "no commits, dirty state, or preserved worktree" }
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

$InstallRoot = Get-AbsolutePath -Path $InstallRoot
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
if ($policy.schemaVersion -ne 2) {
    throw "Unsupported model route policy schemaVersion: $($policy.schemaVersion). Reinstall with -ResetPolicy after reviewing the generated backup."
}
if (-not $policy.costOrder -or -not $policy.routes -or -not $policy.fallbackPolicy) {
    throw "Model route policy must define costOrder, fallbackPolicy, and routes."
}

$costRank = @{}
for ($index = 0; $index -lt $policy.costOrder.Count; $index++) {
    $costRank[[string]$policy.costOrder[$index]] = $index
}

$agyBridgeRoot = Join-Path $InstallRoot "agy-pi-bridge"
$agyBridgeScript = Join-Path $agyBridgeRoot "Invoke-AgyPiBridge.ps1"
$agyPiShim = Join-Path $agyBridgeRoot "pi.cmd"
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

    $ansi = [regex]'\x1B\[[0-?]*[ -/]*[@-~]'
    $script:openCodeModels = @(
        $probe.Output -split "\r?\n" |
            ForEach-Object { $ansi.Replace($_, "").Trim() } |
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
    $fallbackOn = @(Get-PropertyValue -InputObject $route -Name "fallbackOn" -Default @() | ForEach-Object { [string]$_ })

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
    if ($ready -and $integration -eq "agy-pi-shim") {
        if (-not (Test-Path -LiteralPath $agyBridgeScript -PathType Leaf) -or -not (Test-Path -LiteralPath $agyPiShim -PathType Leaf)) {
            $ready = $false
            [void]$reasons.Add("AGY GNHF bridge is not installed")
        }
        else {
            $probe = Invoke-Probe -CommandPath $commandRecord.Source -Arguments @("--version")
            if ($probe.TimedOut -or $probe.ExitCode -ne 0) {
                $ready = $false
                [void]$reasons.Add("AGY version probe failed")
            }
        }
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
                foreach ($window in @(Get-PropertyValue -InputObject $pricing -Name "windowsUtc" -Default @())) {
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
        FallbackOn = $fallbackOn
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

$RepoPath = Get-AbsolutePath -Path $RepoPath
if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    throw "Target repository does not exist: $RepoPath"
}
$inside = (Invoke-GitLines -Repository $RepoPath -Arguments @("rev-parse", "--is-inside-work-tree") | Select-Object -First 1).Trim()
if ($inside -ne "true") {
    throw "Target path is not a Git working tree: $RepoPath"
}
$dirty = @(Invoke-GitLines -Repository $RepoPath -Arguments @("status", "--porcelain=v1") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($dirty.Count -gt 0) {
    throw "Target repository must be clean before routed GNHF work:`n$($dirty -join [Environment]::NewLine)"
}

$sprintLauncher = Join-Path $InstallRoot "Start-GnhfSprint.ps1"
if (-not (Test-Path -LiteralPath $sprintLauncher -PathType Leaf)) {
    $sprintLauncher = Join-Path $PSScriptRoot "Start-GnhfSprint.ps1"
}
if (-not (Test-Path -LiteralPath $sprintLauncher -PathType Leaf)) {
    throw "Start-GnhfSprint.ps1 was not found in the installed fleet or repository bundle."
}

$runtimePromptPath = $null
if ($Prompt) {
    $runtimePromptRoot = Join-Path $InstallRoot "runtime-prompts"
    New-Item -ItemType Directory -Path $runtimePromptRoot -Force | Out-Null
    $runtimePromptPath = Join-Path $runtimePromptRoot ("auto-route-{0}.md" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"))
    Set-Content -LiteralPath $runtimePromptPath -Value $Prompt -Encoding utf8NoBOM
    $PromptPath = $runtimePromptPath
}
else {
    $PromptPath = Get-AbsolutePath -Path $PromptPath
    if (-not (Test-Path -LiteralPath $PromptPath -PathType Leaf)) {
        throw "Prompt file not found: $PromptPath"
    }
}

$selectionRoot = Join-Path $InstallRoot "route-selections"
New-Item -ItemType Directory -Path $selectionRoot -Force | Out-Null
$candidates = @($routeResults | Where-Object Ready)
if ($candidates.Count -eq 0) {
    throw "No GNHF-compatible route is ready. Review the route plan or authentication state."
}

try {
    foreach ($selected in $candidates) {
        $attemptTimestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
        $selectionPath = Join-Path $selectionRoot ("$attemptTimestamp-$($selected.Id).json")
        $agyStatusPath = Join-Path $selectionRoot ("$attemptTimestamp-$($selected.Id)-status.json")

        [ordered]@{
            schemaVersion = 2
            selectedAt = (Get-Date).ToString("o")
            routeId = $selected.Id
            costClass = $selected.CostClass
            agentSpec = $selected.AgentSpec
            model = $selected.Model
            integration = $selected.Integration
            policyPath = $PolicyPath
            compatibilityProofPath = $CompatibilityProofPath
            allowPaid = $AllowPaid
            heavyWorkload = $HeavyWorkload
            allowPeakPaid = [bool]$AllowPeakPaid
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $selectionPath -Encoding utf8NoBOM

        Write-Host "`n=== Attempting route ===" -ForegroundColor Green
        Write-Host "Route:      $($selected.Id)"
        Write-Host "Cost class: $($selected.CostClass)"
        Write-Host "Agent:      $($selected.AgentSpec)"
        Write-Host "Model:      $($selected.Model)"
        Write-Host "Evidence:   $selectionPath"

        $before = Get-FallbackSnapshot -Repository $RepoPath
        $previousPath = $env:Path
        $previousOpenCodeConfig = $env:OPENCODE_CONFIG_CONTENT
        $previousAgyStatusPath = $env:AGENTSWITCHBOARD_AGY_STATUS_PATH
        $previousAgyModel = $env:AGENTSWITCHBOARD_AGY_MODEL
        $agentSpec = $selected.AgentSpec

        try {
            if ($selected.Integration -eq "agy-pi-shim") {
                $env:Path = "$agyBridgeRoot;$previousPath"
                $env:AGENTSWITCHBOARD_AGY_STATUS_PATH = $agyStatusPath
                Remove-Item Env:AGENTSWITCHBOARD_AGY_MODEL -ErrorAction SilentlyContinue
                $agentSpec = "pi"
            }
            elseif ($selected.Integration -eq "opencode-model") {
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

            $childArguments = @(
                "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
                "-File", $sprintLauncher,
                "-RepoPath", $RepoPath,
                "-Agent", $agentSpec,
                "-PromptPath", $PromptPath,
                "-Name", "$Name-$($selected.Id)",
                "-MaxIterations", [string]$MaxIterations,
                "-MaxTokens", [string]$MaxTokens,
                "-StopWhen", $StopWhen,
                "-InstallRoot", $InstallRoot
            )

            & pwsh @childArguments
            $routeExitCode = $LASTEXITCODE
        }
        finally {
            $env:Path = $previousPath
            if ($null -eq $previousOpenCodeConfig) {
                Remove-Item Env:OPENCODE_CONFIG_CONTENT -ErrorAction SilentlyContinue
            }
            else {
                $env:OPENCODE_CONFIG_CONTENT = $previousOpenCodeConfig
            }
            if ($null -eq $previousAgyStatusPath) {
                Remove-Item Env:AGENTSWITCHBOARD_AGY_STATUS_PATH -ErrorAction SilentlyContinue
            }
            else {
                $env:AGENTSWITCHBOARD_AGY_STATUS_PATH = $previousAgyStatusPath
            }
            if ($null -eq $previousAgyModel) {
                Remove-Item Env:AGENTSWITCHBOARD_AGY_MODEL -ErrorAction SilentlyContinue
            }
            else {
                $env:AGENTSWITCHBOARD_AGY_MODEL = $previousAgyModel
            }
        }

        if ($routeExitCode -eq 0) {
            Write-Host "`nRoute completed successfully: $($selected.Id)" -ForegroundColor Green
            return
        }

        $classification = "unclassified-failure"
        if ($selected.Integration -eq "agy-pi-shim" -and (Test-Path -LiteralPath $agyStatusPath -PathType Leaf)) {
            try {
                $status = Get-Content -LiteralPath $agyStatusPath -Raw | ConvertFrom-Json
                $classification = [string]$status.classification
            }
            catch {
                $classification = "bridge-status-invalid"
            }
        }

        Write-Warning "Route '$($selected.Id)' failed with exit code $routeExitCode and classification '$classification'."
        if ($selected.FallbackOn -notcontains $classification) {
            throw "The route failed for a reason that does not authorize fallback. Review its GNHF log and worktree before trying another model."
        }

        $mutationCheck = Test-NoMutationAfterFailure -Repository $RepoPath -Before $before
        if (-not $mutationCheck.Safe) {
            throw "Quota exhaustion was reported, but automatic fallback is blocked because $($mutationCheck.Reason). Review the repository before continuing."
        }

        Write-Host "AGY quota is exhausted and no mutation was observed. Moving to the next configured route." -ForegroundColor Yellow
    }

    throw "All ready routes were exhausted without a successful run."
}
finally {
    if ($runtimePromptPath -and (Test-Path -LiteralPath $runtimePromptPath -PathType Leaf)) {
        Remove-Item -LiteralPath $runtimePromptPath -Force
    }
}
