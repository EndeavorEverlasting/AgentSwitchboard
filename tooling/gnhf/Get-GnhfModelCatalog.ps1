[CmdletBinding()]
param(
    [string]$ProviderDirectoryPath = (Join-Path $PSScriptRoot "opencode-provider-directory.json"),
    [string]$OutputPath = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\model-catalog.json",
    [ValidateRange(10, 600)][int]$TimeoutSeconds = 180,
    [switch]$NoRefresh,
    [switch]$PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-PlainLine {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    ($Text -replace "`e\[[0-9;?]*[ -/]*[@-~]", "").Trim()
}

function Invoke-BoundedCommand {
    param(
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][int]$BoundSeconds
    )

    $resolved = Get-Command $CommandName -ErrorAction Stop
    $filePath = $resolved.Source
    $effectiveArguments = [System.Collections.Generic.List[string]]::new()
    if ([IO.Path]::GetExtension($filePath) -in @(".cmd", ".bat")) {
        $commandLine = '"' + $filePath.Replace('"', '""') + '" ' + (($Arguments | ForEach-Object { '"' + $_.Replace('"', '""') + '"' }) -join ' ')
        $filePath = $env:ComSpec
        foreach ($item in @("/d", "/s", "/c", $commandLine)) { [void]$effectiveArguments.Add($item) }
    }
    else {
        foreach ($item in $Arguments) { [void]$effectiveArguments.Add($item) }
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $filePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($item in $effectiveArguments) { [void]$startInfo.ArgumentList.Add($item) }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($BoundSeconds * 1000)
    if ($timedOut) {
        try { $process.Kill($true); $process.WaitForExit() } catch {}
    }

    [pscustomobject]@{
        exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
        timedOut = $timedOut
        stdout = $stdoutTask.GetAwaiter().GetResult()
        stderr = $stderrTask.GetAwaiter().GetResult()
    }
}

$ProviderDirectoryPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ProviderDirectoryPath))
$OutputPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($OutputPath))
if (-not (Test-Path -LiteralPath $ProviderDirectoryPath -PathType Leaf)) {
    throw "Provider directory not found: $ProviderDirectoryPath"
}
$directory = Get-Content -LiteralPath $ProviderDirectoryPath -Raw | ConvertFrom-Json -Depth 30
if ([string]$directory.schemaVersion -ne "agentswitchboard-opencode-provider-directory/v1") {
    throw "Unsupported provider directory schemaVersion: $($directory.schemaVersion)"
}

$modelArguments = [System.Collections.Generic.List[string]]::new()
[void]$modelArguments.Add("models")
if (-not $NoRefresh) { [void]$modelArguments.Add("--refresh") }

$plan = [ordered]@{
    schemaVersion = "agentswitchboard-gnhf-model-catalog-plan/v1"
    operation = if ($PlanOnly) { "plan" } else { "discover" }
    providerDirectoryPath = $ProviderDirectoryPath
    providerCount = @($directory.providers).Count
    authenticationCommand = "opencode auth list"
    modelCommand = "opencode $($modelArguments -join ' ')"
    outputPath = $OutputPath
    timeoutSeconds = $TimeoutSeconds
    writesCredentials = $false
    writesProviderConfig = $false
}
if ($PlanOnly) {
    $plan | ConvertTo-Json -Depth 8
    exit 0
}

$authResult = Invoke-BoundedCommand -CommandName "opencode" -Arguments @("auth", "list") -BoundSeconds $TimeoutSeconds
if ($authResult.timedOut) { throw "OpenCode authentication inventory timed out after $TimeoutSeconds seconds." }
if ($authResult.exitCode -ne 0) { throw "OpenCode authentication inventory failed with exit code $($authResult.exitCode)." }

$modelResult = Invoke-BoundedCommand -CommandName "opencode" -Arguments @($modelArguments) -BoundSeconds $TimeoutSeconds
if ($modelResult.timedOut) { throw "OpenCode model discovery timed out after $TimeoutSeconds seconds." }
if ($modelResult.exitCode -ne 0) { throw "OpenCode model discovery failed with exit code $($modelResult.exitCode)." }

$authText = ConvertTo-PlainLine -Text $authResult.stdout
$modelLines = @(
    ($modelResult.stdout -split "`r?`n") |
        ForEach-Object { ConvertTo-PlainLine -Text $_ } |
        Where-Object { $_ -match '^[A-Za-z0-9._-]+/.+$' } |
        Sort-Object -Unique
)
if ($modelLines.Count -eq 0) {
    throw "OpenCode returned no provider/model identifiers. Configure at least one provider and rerun discovery."
}

$directoryByHint = @{}
foreach ($provider in @($directory.providers)) {
    foreach ($hint in @($provider.opencodeIdHints)) {
        $directoryByHint[[string]$hint.ToLowerInvariant()] = $provider
    }
}

$reportedProviderIds = [System.Collections.Generic.List[string]]::new()
foreach ($provider in @($directory.providers)) {
    $matched = $false
    foreach ($candidate in @($provider.displayName, $provider.id) + @($provider.opencodeIdHints)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and $authText -match [regex]::Escape([string]$candidate)) {
            $matched = $true
            break
        }
    }
    if ($matched) { [void]$reportedProviderIds.Add([string]$provider.id) }
}

$models = [System.Collections.Generic.List[object]]::new()
foreach ($fullId in $modelLines) {
    $slash = $fullId.IndexOf('/')
    $providerId = $fullId.Substring(0, $slash)
    $modelId = $fullId.Substring($slash + 1)
    $tags = [System.Collections.Generic.List[string]]::new()
    [void]$tags.Add("runtime-discovered")
    if ($providerId -in @("deepseek", "openai", "anthropic", "google", "google-vertex", "xai", "moonshotai", "minimax", "zai")) { [void]$tags.Add("direct-provider") }
    if ($providerId -in @("openrouter", "cloudflare-ai-gateway", "vercel-ai-gateway", "llm-gateway", "zenmux")) { [void]$tags.Add("gateway") }
    if ($providerId -in @("github-copilot", "gitlab-duo", "opencode", "opencode-go")) { [void]$tags.Add("subscription-or-managed") }
    if ($providerId -in @("ollama", "llama-cpp", "lmstudio", "atomic-chat")) { [void]$tags.Add("local-capable") }
    [void]$models.Add([pscustomobject][ordered]@{
        fullId = $fullId
        providerId = $providerId
        modelId = $modelId
        available = $true
        agentAdapters = @("opencode")
        routingTags = @($tags)
    })
}

$providers = [System.Collections.Generic.List[object]]::new()
foreach ($group in @($models | Group-Object providerId | Sort-Object Name)) {
    $runtimeId = [string]$group.Name
    $documentedProvider = $directoryByHint[$runtimeId.ToLowerInvariant()]
    $reported = $false
    if ($documentedProvider) { $reported = $reportedProviderIds -contains [string]$documentedProvider.id }
    [void]$providers.Add([pscustomobject][ordered]@{
        providerId = $runtimeId
        displayName = if ($documentedProvider) { [string]$documentedProvider.displayName } else { $null }
        documented = [bool]$documentedProvider
        modelCount = $group.Count
        authenticationStatus = if ($reported) { "reported" } elseif ($authText) { "not-reported" } else { "unknown" }
    })
}

$catalog = [ordered]@{
    schemaVersion = "agentswitchboard-gnhf-model-catalog/v1"
    capturedAt = (Get-Date).ToString("o")
    source = [ordered]@{
        command = "opencode models --refresh"
        refresh = -not [bool]$NoRefresh
        providerDirectoryHash = (Get-FileHash -LiteralPath $ProviderDirectoryPath -Algorithm SHA256).Hash
    }
    authentication = [ordered]@{
        command = "opencode auth list"
        reportedProviderIds = @($reportedProviderIds | Sort-Object -Unique)
    }
    providers = @($providers)
    models = @($models | Sort-Object fullId)
}

$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
$tempPath = "$OutputPath.$([guid]::NewGuid().ToString('N')).tmp"
$catalog | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tempPath -Encoding utf8NoBOM
Move-Item -LiteralPath $tempPath -Destination $OutputPath -Force

Write-Host "Model catalog written: $OutputPath" -ForegroundColor Green
Write-Host "Providers: $($providers.Count)"
Write-Host "Models:    $($models.Count)"
