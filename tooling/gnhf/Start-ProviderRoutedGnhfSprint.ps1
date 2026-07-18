[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$PromptPath,
    [string]$Name = "provider-routed-gnhf",
    [ValidatePattern('^deepseek/[^\s/]+$')][string]$Model = "deepseek/deepseek-v4-pro",
    [ValidateRange(1, 15)][int]$MaxIterations = 8,
    [ValidateRange(50000, 1500000)][int]$MaxTokens = 800000,
    [ValidateRange(5, 180)][int]$ProbeTimeoutSeconds = 30,
    [Parameter(Mandatory)][string]$StopWhen,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 is required. Open pwsh and rerun."
}

$processHelpers = Join-Path $PSScriptRoot "Gnhf.Process.ps1"
if (-not (Test-Path -LiteralPath $processHelpers -PathType Leaf)) {
    $processHelpers = Join-Path $InstallRoot "Gnhf.Process.ps1"
}
if (-not (Test-Path -LiteralPath $processHelpers -PathType Leaf)) {
    throw "Windows-safe process helpers not found. Run Install-ProviderRoutedGnhf.ps1 first."
}
. $processHelpers

$RepoPath = [IO.Path]::GetFullPath($RepoPath)
if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    throw "Repository directory not found: $RepoPath"
}
if (-not (Test-Path -LiteralPath $PromptPath -PathType Leaf)) {
    throw "GNHF runtime objective not found: $PromptPath"
}

# Directory first: every Git, provider, and GNHF action occurs after this point.
Set-Location -LiteralPath $RepoPath

$inside = (& git rev-parse --is-inside-work-tree 2>&1 | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or $inside -ne "true") {
    throw "Target directory is not a Git worktree: $RepoPath"
}
$dirty = @(git status --porcelain=v1)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect repository status."
}
if (@($dirty | Where-Object { $_ }).Count -gt 0) {
    throw "GNHF requires a clean base checkout. Preserve existing work before launching.`n$($dirty -join [Environment]::NewLine)"
}
$branch = (git branch --show-current).Trim()
if (-not $branch) {
    throw "Detached HEAD is not allowed for an unattended sprint."
}
$baseSha = (git rev-parse HEAD).Trim()

$statePath = Join-Path $InstallRoot "state.json"
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "AgentSwitchboard fleet state not found: $statePath"
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

$logsRoot = Join-Path $InstallRoot "logs\provider-routes"
[void](New-Item -ItemType Directory -Path $logsRoot -Force)
$safeName = (($Name -replace '[^A-Za-z0-9._-]', '-').Trim('-'))
if (-not $safeName) { $safeName = "provider-routed-gnhf" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$evidencePath = Join-Path $logsRoot "$stamp-$safeName.json"
$transcriptPath = Join-Path $logsRoot "$stamp-$safeName.txt"

$evidence = [ordered]@{
    schemaVersion = 2
    route = "deepseek-through-opencode-through-gnhf"
    status = "preflight"
    repository = $RepoPath
    baseBranch = $branch
    baseSha = $baseSha
    model = $Model
    maxIterations = $MaxIterations
    maxTokens = $MaxTokens
    probeTimeoutSeconds = $ProbeTimeoutSeconds
    gnhfVersion = $null
    gnhfModelFlag = $false
    openCodeVersion = $null
    openCodeDispatch = $null
    providerMarker = $null
    sprintInvoked = $false
    sprintExitCode = $null
    deliveredBranches = @()
    errorClass = $null
    error = $null
    startedAt = (Get-Date).ToString("o")
    completedAt = $null
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding utf8NoBOM

function Save-Evidence {
    $evidence.completedAt = (Get-Date).ToString("o")
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding utf8NoBOM
}

function Get-CommandPathFromState {
    param([Parameter(Mandatory)][string]$Name)
    $property = $state.agents.PSObject.Properties[$Name]
    if (-not $property -or -not $property.Value.available) {
        $reason = if ($property) { [string]$property.Value.evidence } else { "no state record" }
        throw "Agent '$Name' is not ready in AgentSwitchboard state. Evidence: $reason"
    }
    $path = [string]$property.Value.commandPath
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Recorded $Name command is unavailable: $path. Rerun AgentSwitchboard setup; do not probe a different installation."
    }
    return (Get-Item -LiteralPath $path -Force).FullName
}

$transcriptStarted = $false
$previousInlineConfig = [Environment]::GetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", "Process")
try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
    $transcriptStarted = $true

    $gnhfPath = [string]$state.gnhf.commandPath
    if (-not $gnhfPath -or -not (Test-Path -LiteralPath $gnhfPath -PathType Leaf)) {
        throw "Recorded GNHF command is unavailable: $gnhfPath. Run the provider-route installer."
    }

    $gnhfVersionProbe = Invoke-GnhfBoundedCommand -FilePath $gnhfPath -ArgumentList @("--version") -WorkingDirectory $RepoPath -TimeoutSeconds 15
    if ($gnhfVersionProbe.timedOut -or $gnhfVersionProbe.exitCode -ne 0) {
        throw "GNHF version probe failed: $($gnhfVersionProbe.output)"
    }
    $versionMatch = [regex]::Match($gnhfVersionProbe.output, '(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if (-not $versionMatch.Success) {
        throw "Unable to parse GNHF version: $($gnhfVersionProbe.output)"
    }
    $gnhfVersion = [version]$versionMatch.Groups[1].Value
    $evidence.gnhfVersion = $gnhfVersion.ToString()
    if ($gnhfVersion -lt [version]"0.1.42") {
        throw "GNHF 0.1.42 or newer is required for recovered OpenCode JSON output on the provider route. Detected $gnhfVersion. Run Install-ProviderRoutedGnhf.ps1 -Apply."
    }

    $gnhfHelpProbe = Invoke-GnhfBoundedCommand -FilePath $gnhfPath -ArgumentList @("--help") -WorkingDirectory $RepoPath -TimeoutSeconds 15
    $evidence.gnhfModelFlag = ($gnhfHelpProbe.exitCode -eq 0 -and $gnhfHelpProbe.output -match '(?m)^\s*(-m,\s*)?--model\b')
    # Exact model selection is enforced by the OpenCode preflight below and OPENCODE_CONFIG_CONTENT.
    # Pass --model to GNHF only when that CLI option exists; current upstream 0.1.42 does not expose it.

    $openCodePath = Get-CommandPathFromState -Name "opencode"
    $versionProbe = Invoke-GnhfBoundedCommand -FilePath $openCodePath -ArgumentList @("--version") -WorkingDirectory $RepoPath -TimeoutSeconds $ProbeTimeoutSeconds
    $evidence.openCodeDispatch = $versionProbe.dispatch
    if ($versionProbe.timedOut -or $versionProbe.exitCode -ne 0) {
        throw "OpenCode version probe failed: $($versionProbe.output)"
    }
    $openCodeVersionMatch = [regex]::Match($versionProbe.output, '(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if (-not $openCodeVersionMatch.Success) {
        throw "Unable to parse OpenCode version: $($versionProbe.output)"
    }
    $openCodeVersion = [version]$openCodeVersionMatch.Groups[1].Value
    $evidence.openCodeVersion = $openCodeVersion.ToString()
    if ($openCodeVersion -lt [version]"1.14.24") {
        throw "OpenCode 1.14.24 or newer is required. Detected $openCodeVersion."
    }

    $modelsProbe = Invoke-GnhfBoundedCommand -FilePath $openCodePath -ArgumentList @("models", "deepseek") -WorkingDirectory $RepoPath -TimeoutSeconds $ProbeTimeoutSeconds
    if ($modelsProbe.timedOut -or $modelsProbe.exitCode -ne 0) {
        throw "OpenCode could not enumerate DeepSeek models: $($modelsProbe.output)"
    }
    if ($modelsProbe.output -notmatch ('(?m)^\s*' + [regex]::Escape($Model) + '\s*$')) {
        throw "Requested model '$Model' is not listed by OpenCode."
    }

    $marker = "AGENT_SWITCHBOARD_MODEL_READY"
    $markerPrompt = "Return exactly $marker. Do not inspect files, call tools, or modify state."
    $providerProbe = Invoke-GnhfBoundedCommand -FilePath $openCodePath -ArgumentList @("run", "--model", $Model, "--format", "json", $markerPrompt) -WorkingDirectory $RepoPath -TimeoutSeconds $ProbeTimeoutSeconds
    if ($providerProbe.timedOut) {
        throw "DeepSeek provider probe timed out after $ProbeTimeoutSeconds seconds; GNHF was not started."
    }
    if ($providerProbe.exitCode -ne 0 -or $providerProbe.output -notmatch [regex]::Escape($marker)) {
        throw "DeepSeek provider probe failed; GNHF was not started. $($providerProbe.output)"
    }
    $evidence.providerMarker = $marker
    $evidence.status = "provider-ready"
    Save-Evidence

    $inline = [ordered]@{ '$schema' = "https://opencode.ai/config.json"; model = $Model; share = "disabled" }
    $env:OPENCODE_CONFIG_CONTENT = $inline | ConvertTo-Json -Depth 8 -Compress

    $beforeRefs = @{}
    git for-each-ref --format='%(refname:short) %(objectname)' refs/heads/gnhf/ | ForEach-Object {
        if ($_ -match '^(\S+)\s+(\S+)$') { $beforeRefs[$matches[1]] = $matches[2] }
    }

    $objective = Get-Content -LiteralPath $PromptPath -Raw
    if ([string]::IsNullOrWhiteSpace($objective)) {
        throw "GNHF runtime objective is empty: $PromptPath"
    }

    $gnhfArguments = @(
        "--agent", "opencode"
    )
    if ($evidence.gnhfModelFlag) {
        $gnhfArguments += @("--model", $Model)
    }
    $gnhfArguments += @(
        "--worktree",
        "--max-iterations", [string]$MaxIterations,
        "--max-tokens", [string]$MaxTokens,
        "--prevent-sleep", "on",
        "--stop-when", $StopWhen
    )

    Write-Host "`n=== PROVIDER-ROUTED GNHF ===" -ForegroundColor Cyan
    Write-Host "Repo:       $RepoPath"
    Write-Host "Base:       $branch @ $baseSha"
    Write-Host "Agent:      opencode"
    Write-Host "Model:      $Model"
    Write-Host "Iterations: $MaxIterations"
    Write-Host "Token cap:  $MaxTokens"
    Write-Host "Evidence:   $evidencePath"

    $evidence.sprintInvoked = $true
    Save-Evidence
    $objective | & $gnhfPath @gnhfArguments
    $evidence.sprintExitCode = $LASTEXITCODE

    $delivered = [System.Collections.Generic.List[object]]::new()
    git for-each-ref --format='%(refname:short) %(objectname)' refs/heads/gnhf/ | ForEach-Object {
        if ($_ -match '^(\S+)\s+(\S+)$') {
            $name = $matches[1]
            $sha = $matches[2]
            $previous = if ($beforeRefs.ContainsKey($name)) { $beforeRefs[$name] } else { $null }
            if ($sha -ne $previous) {
                git merge-base --is-ancestor $baseSha $sha 2>$null
                if ($LASTEXITCODE -eq 0 -and $sha -ne $baseSha) {
                    [void]$delivered.Add([ordered]@{ branch = $name; sha = $sha })
                }
            }
        }
    }
    $evidence.deliveredBranches = @($delivered)

    if ($evidence.sprintExitCode -ne 0) {
        throw "GNHF exited with code $($evidence.sprintExitCode). Preserve its worktree and logs."
    }
    if ($delivered.Count -eq 0) {
        $evidence.sprintExitCode = 79
        throw "GNHF returned success without a new commit ahead of $baseSha. Process exit zero is not delivery proof."
    }

    $evidence.status = "delivered"
    Save-Evidence
    Write-Host "`nProvider-routed GNHF produced committed work. Review before push or merge." -ForegroundColor Green
}
catch {
    $evidence.status = "blocked"
    $evidence.errorClass = $_.Exception.GetType().FullName
    $evidence.error = $_.Exception.Message
    Save-Evidence
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    Write-Host "Provider-route evidence: $evidencePath" -ForegroundColor Cyan
    exit $(if ($evidence.sprintExitCode) { [int]$evidence.sprintExitCode } else { 1 })
}
finally {
    [Environment]::SetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", $previousInlineConfig, "Process")
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
