[CmdletBinding(DefaultParameterSetName = "PromptFile")]
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory, ParameterSetName = "PromptFile")][string]$PromptPath,
    [Parameter(Mandatory, ParameterSetName = "PromptText")][string]$Prompt,
    [string]$Name = "deepseek-gnhf-sprint",
    [ValidateRange(1, 100)][int]$MaxIterations = 6,
    [ValidateRange(1, 1000000000)][int]$MaxTokens = 500000,
    [Parameter(Mandatory)][string]$StopWhen,
    [ValidatePattern('^deepseek/[^\s/]+$')][string]$DeepSeekModel = "deepseek/deepseek-v4-pro",
    [ValidateRange(5, 120)][int]$ProbeTimeoutSeconds = 20,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$PushBranch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pathHelpersPath = Join-Path $PSScriptRoot "GnhfFleet.Paths.ps1"
if (-not (Test-Path -LiteralPath $pathHelpersPath -PathType Leaf)) {
    throw "Path helper library not found: $pathHelpersPath"
}
. $pathHelpersPath

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $result = [ordered]@{
        ExitCode = $null
        TimedOut = $false
        Output = ""
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $WorkingDirectory

    if ($FilePath.EndsWith(".cmd", [StringComparison]::OrdinalIgnoreCase) -or
        $FilePath.EndsWith(".bat", [StringComparison]::OrdinalIgnoreCase)) {
        $psi.FileName = if ($env:ComSpec) { $env:ComSpec } else { "cmd.exe" }
        [void]$psi.ArgumentList.Add("/d")
        [void]$psi.ArgumentList.Add("/s")
        [void]$psi.ArgumentList.Add("/c")
        [void]$psi.ArgumentList.Add($FilePath)
    }
    else {
        $psi.FileName = $FilePath
    }

    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
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

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $result.Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
    finally {
        $process.Dispose()
    }

    return [pscustomobject]$result
}

function Get-ProbeExcerpt {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "<no output>"
    }
    $normalized = $Text.Trim()
    if ($normalized.Length -le 1200) {
        return $normalized
    }
    return $normalized.Substring($normalized.Length - 1200)
}

$RepoPath = Resolve-GnhfFleetDirectory -Path $RepoPath -Description "target repository"
$InstallRoot = Get-GnhfFleetAbsolutePath -Path $InstallRoot
$statePath = Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "state.json") -Description "fleet state"
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$openCodeRecord = $state.agents.PSObject.Properties["opencode"]
if (-not $openCodeRecord -or -not $openCodeRecord.Value.available) {
    $evidence = if ($openCodeRecord) { [string]$openCodeRecord.Value.evidence } else { "no OpenCode state record" }
    throw "DeepSeek routing requires the READY OpenCode adapter. Evidence: $evidence"
}

$openCodePath = [string]$openCodeRecord.Value.commandPath
if (-not $openCodePath -or -not (Test-Path -LiteralPath $openCodePath -PathType Leaf)) {
    $openCodeCommand = Get-Command opencode -ErrorAction SilentlyContinue
    if (-not $openCodeCommand) {
        throw "The OpenCode command recorded by AgentSwitchboard is unavailable. Rerun setup before requesting DeepSeek."
    }
    $openCodePath = $openCodeCommand.Source
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agent-switchboard-deepseek-probe-{0}" -f [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)
try {
    $versionProbe = Invoke-BoundedProcess -FilePath $openCodePath -ArgumentList @("--version") -WorkingDirectory $tempRoot -TimeoutSeconds $ProbeTimeoutSeconds
    if ($versionProbe.TimedOut -or $versionProbe.ExitCode -ne 0) {
        throw "OpenCode version probe failed. $(Get-ProbeExcerpt -Text $versionProbe.Output)"
    }

    $versionMatch = [regex]::Match($versionProbe.Output, '(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if (-not $versionMatch.Success) {
        throw "OpenCode version output could not be parsed: $(Get-ProbeExcerpt -Text $versionProbe.Output)"
    }
    $openCodeVersion = [version]$versionMatch.Groups[1].Value
    $minimumVersion = [version]"1.14.24"
    if ($openCodeVersion -lt $minimumVersion) {
        throw "DeepSeek routing requires OpenCode $minimumVersion or newer. Detected $openCodeVersion."
    }

    $modelsProbe = Invoke-BoundedProcess -FilePath $openCodePath -ArgumentList @("models", "deepseek") -WorkingDirectory $tempRoot -TimeoutSeconds $ProbeTimeoutSeconds
    if ($modelsProbe.TimedOut -or $modelsProbe.ExitCode -ne 0) {
        throw "OpenCode could not enumerate the DeepSeek provider. Connect it interactively first, then rerun. $(Get-ProbeExcerpt -Text $modelsProbe.Output)"
    }
    $modelPattern = '(?m)^\s*' + [regex]::Escape($DeepSeekModel) + '\s*$'
    if ($modelsProbe.Output -notmatch $modelPattern) {
        throw "Requested DeepSeek model '$DeepSeekModel' is not available. Run 'opencode models deepseek' and pass an exact provider/model ID."
    }

    $readyMarker = "DEEPSEEK_GNHF_READY"
    $spawnPrompt = "Return exactly $readyMarker. Do not inspect files, call tools, or modify state."
    $spawnProbe = Invoke-BoundedProcess `
        -FilePath $openCodePath `
        -ArgumentList @("run", "--model", $DeepSeekModel, "--format", "json", $spawnPrompt) `
        -WorkingDirectory $tempRoot `
        -TimeoutSeconds $ProbeTimeoutSeconds
    if ($spawnProbe.TimedOut) {
        throw "DeepSeek spawnability probe timed out after $ProbeTimeoutSeconds seconds. No repository sprint was started."
    }
    if ($spawnProbe.ExitCode -ne 0 -or $spawnProbe.Output -notmatch [regex]::Escape($readyMarker)) {
        throw "DeepSeek spawnability probe did not return the success marker. Authenticate/configure DeepSeek in OpenCode interactively, then rerun. $(Get-ProbeExcerpt -Text $spawnProbe.Output)"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$originalInlineConfig = [Environment]::GetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", "Process")
$originalRoute = [Environment]::GetEnvironmentVariable("AGENT_SWITCHBOARD_PROVIDER_ROUTE", "Process")
$exitCode = 1
try {
    $inlineConfig = [ordered]@{
        '$schema' = "https://opencode.ai/config.json"
        model = $DeepSeekModel
    }
    if (-not [string]::IsNullOrWhiteSpace($originalInlineConfig)) {
        try {
            $existingConfig = $originalInlineConfig | ConvertFrom-Json -AsHashtable
            if ($null -eq $existingConfig) {
                throw "inline config is empty"
            }
            $existingConfig["model"] = $DeepSeekModel
            if (-not $existingConfig.ContainsKey('$schema')) {
                $existingConfig['$schema'] = "https://opencode.ai/config.json"
            }
            $inlineConfig = $existingConfig
        }
        catch {
            throw "Existing OPENCODE_CONFIG_CONTENT is not valid JSON and cannot be safely merged: $($_.Exception.Message)"
        }
    }

    $env:OPENCODE_CONFIG_CONTENT = $inlineConfig | ConvertTo-Json -Depth 20 -Compress
    $env:AGENT_SWITCHBOARD_PROVIDER_ROUTE = "deepseek:$DeepSeekModel"

    $sourceLauncher = Join-Path $PSScriptRoot "Start-GnhfSprint.ps1"
    $sprintLauncher = if (Test-Path -LiteralPath $sourceLauncher -PathType Leaf) {
        (Get-Item -LiteralPath $sourceLauncher -Force).FullName
    }
    else {
        Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "Start-GnhfSprint.ps1") -Description "bounded sprint launcher"
    }

    $launchParameters = @{
        RepoPath = $RepoPath
        Agent = "opencode"
        Name = $Name
        MaxIterations = $MaxIterations
        MaxTokens = $MaxTokens
        StopWhen = $StopWhen
        InstallRoot = $InstallRoot
    }
    if ($PSCmdlet.ParameterSetName -eq "PromptFile") {
        $launchParameters["PromptPath"] = $PromptPath
    }
    else {
        $launchParameters["Prompt"] = $Prompt
    }
    if ($PushBranch) {
        $launchParameters["PushBranch"] = $true
    }

    Write-Host "`n=== DEEPSEEK ROUTE READY ===" -ForegroundColor Cyan
    Write-Host "OpenCode: $openCodePath"
    Write-Host "Model:    $DeepSeekModel"
    Write-Host "Probe:    exact model returned $readyMarker within $ProbeTimeoutSeconds seconds"
    Write-Host "Adapter:  opencode (native GNHF adapter)"

    & $sprintLauncher @launchParameters
    $exitCode = $LASTEXITCODE
}
finally {
    [Environment]::SetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", $originalInlineConfig, "Process")
    [Environment]::SetEnvironmentVariable("AGENT_SWITCHBOARD_PROVIDER_ROUTE", $originalRoute, "Process")
}

exit $exitCode
