[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$PromptPath,
    [ValidateSet("Auto", "Standard", "Free")][string]$Mode = "Auto",
    [string]$OutputPath,
    [string]$PolicyPath = (Join-Path $PSScriptRoot "thinker-route.policy.json"),
    [ValidateRange(1000, 120000)][int]$MaxObjectiveChars = 60000,
    [ValidateRange(1000, 50000)][int]$MaxPlanChars = 24000,
    [ValidateRange(5, 900)][int]$TimeoutSeconds = 300,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 is required. Open pwsh and rerun."
}

$routeHelpers = Join-Path $PSScriptRoot "Thinker.Route.ps1"
if (-not (Test-Path -LiteralPath $routeHelpers -PathType Leaf)) {
    throw "Thinker route helpers not found: $routeHelpers"
}
. $routeHelpers

$RepoPath = [IO.Path]::GetFullPath($RepoPath)
$PromptPath = [IO.Path]::GetFullPath($PromptPath)
if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    throw "Repository directory not found: $RepoPath"
}
if (-not (Test-Path -LiteralPath $PromptPath -PathType Leaf)) {
    throw "Thinker objective not found: $PromptPath"
}

$objective = Get-Content -LiteralPath $PromptPath -Raw
if ([string]::IsNullOrWhiteSpace($objective)) {
    throw "Thinker objective is empty: $PromptPath"
}
if ($objective.Length -gt $MaxObjectiveChars) {
    throw "Thinker objective is $($objective.Length) characters; cap is $MaxObjectiveChars. Compile a smaller bounded objective before spending model context."
}

$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$plansRoot = Join-Path $InstallRoot "plans"
$logsRoot = Join-Path $InstallRoot "logs\thinker-routes"
[void](New-Item -ItemType Directory -Path $plansRoot -Force)
[void](New-Item -ItemType Directory -Path $logsRoot -Force)
$stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
if (-not $OutputPath) {
    $safeRepo = ((Split-Path -Leaf $RepoPath) -replace '[^A-Za-z0-9._-]', '-')
    $OutputPath = Join-Path $plansRoot "$stamp-$safeRepo-SYSTEM_PLAN.md"
}
else {
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path -Parent $OutputPath
    if ($parent) { [void](New-Item -ItemType Directory -Path $parent -Force) }
}
$evidencePath = Join-Path $logsRoot "$stamp-thinker-route.json"

function Get-Sha256Text {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Invoke-ThinkerProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [AllowNull()][string]$StandardInput,
        [hashtable]$EnvironmentOverride,
        [Parameter(Mandatory)][int]$BoundSeconds
    )

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    foreach ($argument in $ArgumentList) { [void]$psi.ArgumentList.Add($argument) }
    if ($EnvironmentOverride) {
        foreach ($key in $EnvironmentOverride.Keys) { $psi.Environment[[string]$key] = [string]$EnvironmentOverride[$key] }
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        if ($null -ne $StandardInput) { $process.StandardInput.Write($StandardInput) }
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($BoundSeconds * 1000)
        if ($timedOut) {
            try { $process.Kill($true) } catch {}
            try { $process.WaitForExit(5000) | Out-Null } catch {}
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        return [pscustomobject]@{
            exitCode = if ($timedOut) { -1 } else { $process.ExitCode }
            timedOut = $timedOut
            stdout = $stdout.Trim()
            stderr = $stderr.Trim()
        }
    }
    finally { $process.Dispose() }
}

function Test-OpenCodeRouteModel {
    param([Parameter(Mandatory)]$Route)
    if ([string]$Route.runner -ne "opencode-run") { return $true }
    $command = Get-Command ([string]$Route.command) -ErrorAction SilentlyContinue
    if (-not $command) { return $false }
    $probe = Invoke-ThinkerProcess -FilePath $command.Source -ArgumentList @("models", [string]$Route.probeProvider) -WorkingDirectory $RepoPath -StandardInput $null -EnvironmentOverride $null -BoundSeconds ([Math]::Min(30, $TimeoutSeconds))
    if ($probe.timedOut -or $probe.exitCode -ne 0) { return $false }
    return $probe.stdout -match ('(?m)^\s*' + [regex]::Escape([string]$Route.model) + '\s*$')
}

function Invoke-SelectedThinker {
    param(
        [Parameter(Mandatory)]$Route,
        [Parameter(Mandatory)][string]$PromptText
    )

    $command = Get-Command ([string]$Route.command) -ErrorAction SilentlyContinue
    if (-not $command) {
        return [pscustomobject]@{ exitCode = 127; timedOut = $false; plan = ""; diagnostic = "command not found" }
    }

    switch ([string]$Route.runner) {
        "claude-print" {
            $result = Invoke-ThinkerProcess -FilePath $command.Source -ArgumentList @("-p", "--permission-mode", "plan", "--no-session-persistence", "--output-format", "text", $PromptText) -WorkingDirectory $RepoPath -StandardInput $null -EnvironmentOverride $null -BoundSeconds $TimeoutSeconds
            return [pscustomobject]@{ exitCode = $result.exitCode; timedOut = $result.timedOut; plan = $result.stdout; diagnostic = $result.stderr }
        }
        "codex-exec" {
            $tempOutput = Join-Path ([IO.Path]::GetTempPath()) ("agentswitchboard-codex-plan-{0}.md" -f [guid]::NewGuid().ToString("N"))
            try {
                $args = @("exec", "--cd", $RepoPath, "--sandbox", "read-only", "--ephemeral", "--output-last-message", $tempOutput, "-")
                $result = Invoke-ThinkerProcess -FilePath $command.Source -ArgumentList $args -WorkingDirectory $RepoPath -StandardInput $PromptText -EnvironmentOverride $null -BoundSeconds $TimeoutSeconds
                $plan = if (Test-Path -LiteralPath $tempOutput -PathType Leaf) { Get-Content -LiteralPath $tempOutput -Raw } else { "" }
                return [pscustomobject]@{ exitCode = $result.exitCode; timedOut = $result.timedOut; plan = $plan.Trim(); diagnostic = $result.stderr }
            }
            finally { if (Test-Path -LiteralPath $tempOutput) { Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue } }
        }
        "opencode-run" {
            $inline = [ordered]@{
                '$schema' = "https://opencode.ai/config.json"
                model = [string]$Route.model
                share = "disabled"
                permission = [ordered]@{
                    '*' = "deny"
                    read = "allow"
                    glob = "allow"
                    grep = "allow"
                    lsp = "allow"
                }
            } | ConvertTo-Json -Depth 8 -Compress
            $result = Invoke-ThinkerProcess -FilePath $command.Source -ArgumentList @("run", "--model", [string]$Route.model, $PromptText) -WorkingDirectory $RepoPath -StandardInput $null -EnvironmentOverride @{ OPENCODE_CONFIG_CONTENT = $inline } -BoundSeconds $TimeoutSeconds
            return [pscustomobject]@{ exitCode = $result.exitCode; timedOut = $result.timedOut; plan = $result.stdout; diagnostic = $result.stderr }
        }
        default {
            return [pscustomobject]@{ exitCode = 64; timedOut = $false; plan = ""; diagnostic = "unsupported runner '$($Route.runner)'" }
        }
    }
}

$wrappedPrompt = @"
ROLE: THINKER ONLY. Analyze the repository and objective. Do not implement, edit, commit, push, install, deploy, or ask the operator routine questions.
GOAL: Produce the smallest deterministic implementation plan that a separate builder can execute without receiving this conversation again.
TOKEN DISCIPLINE: Do not paste large source files, logs, or hidden reasoning. Report conclusions and exact evidence paths only. Keep the response under $MaxPlanChars characters.
REQUIRED OUTPUT:
# SYSTEM PLAN
## Objective
## Evidence floor
## Owned scope
## Forbidden scope
## Deterministic workflow
## Files/surfaces to change
## Validation gates
## Failure routing
## Builder handoff
The builder handoff must include only decision-relevant context, exact paths, commands/gates, and stop conditions.

SOURCE OBJECTIVE:
$objective
"@

# Claude/OpenCode currently receive their prompt as a process argument. Keep well below the
# Windows CreateProcess command-line ceiling; Codex is exempt because its prompt is streamed on stdin.
$maxArgvPromptChars = 28000

$policy = Import-AgentSwitchboardThinkerPolicy -PolicyPath $PolicyPath
$resolvedMode = Resolve-AgentSwitchboardThinkerMode -Mode $Mode -Policy $policy
$readiness = @{}
$attempts = [System.Collections.Generic.List[object]]::new()
$chain = @($policy.chains.PSObject.Properties[$resolvedMode].Value)
$finalRoute = $null
$finalPlan = $null

foreach ($routeIdValue in $chain) {
    $routeId = [string]$routeIdValue
    $resolution = Resolve-AgentSwitchboardThinkerRoute -Mode $(if ($resolvedMode -eq "free") { "Free" } else { "Standard" }) -PolicyPath $PolicyPath -ReadinessOverride $readiness
    if ($resolution.status -ne "selected") { break }
    $route = $resolution.route
    if ([string]$route.id -ne $routeId) {
        # Earlier routes may already be marked unavailable. Always act on the resolver's next eligible route.
        $routeId = [string]$route.id
    }

    if ([string]$route.runner -ne "codex-exec" -and $wrappedPrompt.Length -gt $maxArgvPromptChars) {
        $readiness[$routeId] = $false
        [void]$attempts.Add([ordered]@{
            route = $routeId
            status = "preflight-blocked"
            reason = "prompt exceeds safe Windows argv cap for this runner"
            promptChars = $wrappedPrompt.Length
            maxArgvPromptChars = $maxArgvPromptChars
        })
        continue
    }

    try {
        $modelReady = Test-OpenCodeRouteModel -Route $route
    }
    catch {
        $readiness[$routeId] = $false
        $diagnostic = $_.Exception.Message
        if ($diagnostic.Length -gt 1200) { $diagnostic = $diagnostic.Substring($diagnostic.Length - 1200) }
        [void]$attempts.Add([ordered]@{ route = $routeId; status = "preflight-blocked"; reason = "model preflight threw"; diagnostic = $diagnostic })
        continue
    }
    if (-not $modelReady) {
        $readiness[$routeId] = $false
        [void]$attempts.Add([ordered]@{ route = $routeId; status = "preflight-blocked"; reason = "exact model not listed by OpenCode" })
        continue
    }

    try {
        $attempt = Invoke-SelectedThinker -Route $route -PromptText $wrappedPrompt
    }
    catch {
        $readiness[$routeId] = $false
        $diagnostic = $_.Exception.Message
        if ($diagnostic.Length -gt 1200) { $diagnostic = $diagnostic.Substring($diagnostic.Length - 1200) }
        [void]$attempts.Add([ordered]@{ route = $routeId; status = "failed"; exitCode = $null; timedOut = $false; diagnostic = $diagnostic })
        continue
    }
    if ($attempt.exitCode -ne 0 -or $attempt.timedOut -or [string]::IsNullOrWhiteSpace($attempt.plan)) {
        $readiness[$routeId] = $false
        $diagnostic = [string]$attempt.diagnostic
        if ($diagnostic.Length -gt 1200) { $diagnostic = $diagnostic.Substring($diagnostic.Length - 1200) }
        [void]$attempts.Add([ordered]@{ route = $routeId; status = "failed"; exitCode = $attempt.exitCode; timedOut = $attempt.timedOut; diagnostic = $diagnostic })
        continue
    }
    if ($attempt.plan.Length -gt $MaxPlanChars) {
        $readiness[$routeId] = $false
        [void]$attempts.Add([ordered]@{ route = $routeId; status = "rejected"; reason = "plan exceeded MaxPlanChars"; actualChars = $attempt.plan.Length })
        continue
    }

    $finalRoute = $route
    $finalPlan = $attempt.plan.Trim()
    [void]$attempts.Add([ordered]@{ route = $routeId; status = "selected"; exitCode = $attempt.exitCode; planChars = $finalPlan.Length })
    break
}

$evidence = [ordered]@{
    schema = "agentswitchboard.thinker-run.v1"
    mode = $resolvedMode
    repository = $RepoPath
    objectivePath = $PromptPath
    objectiveChars = $objective.Length
    objectiveSha256 = Get-Sha256Text -Text $objective
    maxArgvPromptChars = $maxArgvPromptChars
    selectedRoute = if ($finalRoute) { [string]$finalRoute.id } else { $null }
    provider = if ($finalRoute) { [string]$finalRoute.provider } else { $null }
    model = if ($finalRoute) { $finalRoute.model } else { $null }
    attempts = @($attempts)
    outputPath = if ($finalPlan) { $OutputPath } else { $null }
    planChars = if ($finalPlan) { $finalPlan.Length } else { 0 }
    planSha256 = if ($finalPlan) { Get-Sha256Text -Text $finalPlan } else { $null }
    completedAt = (Get-Date).ToString("o")
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding utf8NoBOM

if (-not $finalPlan) {
    throw "No thinker route produced a bounded plan. Evidence: $evidencePath"
}
Set-Content -LiteralPath $OutputPath -Value $finalPlan -Encoding utf8NoBOM
Write-Host "THINKER ROUTE COMPLETE" -ForegroundColor Green
Write-Host "Mode:     $resolvedMode"
Write-Host "Thinker:  $($finalRoute.id)"
Write-Host "Plan:     $OutputPath"
Write-Host "Evidence: $evidencePath"
