[CmdletBinding(DefaultParameterSetName = "Plan")]
param(
    [string]$RequestPath,
    [string]$CompiledPromptPath,
    [string]$PromptPath,
    [string]$TargetRepo,
    [string]$IngestionOutputDirectory,
    [string]$Agent = 'opencode',
    [ValidateRange(1, 100)][int]$MaxIterations = 4,
    [ValidateRange(1, 1000000000)][long]$MaxTokens = 250000,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 3600,
    [ValidateSet('compile_only', 'local_execute', 'registered_workflow_execute')][string]$ExecutionIntent = 'local_execute',
    [ValidateSet('contract-only', 'local-workstation-observed', 'committed-repository-work')][string]$DesiredProofLevel = 'committed-repository-work',
    [string[]]$ExpectedArtifactPath = @(),
    [string]$CommitMessage,
    [string]$StopCondition,
    [Parameter(ParameterSetName = "Plan")][switch]$PlanOnly,
    [Parameter(Mandatory, ParameterSetName = "Run")][switch]$Run,
    [switch]$CreateDisposableProofRepo,
    [switch]$LocalHarnessProof
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$hasPrompt = -not [string]::IsNullOrWhiteSpace($PromptPath)
$hasRequest = -not [string]::IsNullOrWhiteSpace($RequestPath)
$hasCompiled = -not [string]::IsNullOrWhiteSpace($CompiledPromptPath)
if ($hasPrompt -and ($hasRequest -or $hasCompiled)) {
    throw "Use either -PromptPath or the existing -RequestPath/-CompiledPromptPath pair, not both."
}
if (-not $hasPrompt -and -not ($hasRequest -and $hasCompiled)) {
    throw "Provide -PromptPath, or provide both -RequestPath and -CompiledPromptPath."
}
if ($hasRequest -xor $hasCompiled) {
    throw "-RequestPath and -CompiledPromptPath must be supplied together."
}
if ($hasPrompt) {
    if ([string]::IsNullOrWhiteSpace($TargetRepo)) { throw "-TargetRepo is required with -PromptPath." }
    if ($CreateDisposableProofRepo) { throw "-PromptPath does not combine with -CreateDisposableProofRepo in v1; use the existing contract fixtures for disposable proof." }

    $converter = Join-Path $PSScriptRoot "Convert-GnhfPromptToContracts.ps1"
    if (-not (Test-Path -LiteralPath $converter -PathType Leaf)) {
        throw "GNHF prompt ingestion entrypoint is missing: $converter"
    }
    $conversionParameters = @{
        PromptPath = $PromptPath
        TargetRepo = $TargetRepo
        Agent = $Agent
        MaxIterations = $MaxIterations
        MaxTokens = $MaxTokens
        TimeoutSeconds = $TimeoutSeconds
        ExecutionIntent = $ExecutionIntent
        DesiredProofLevel = $DesiredProofLevel
        ExpectedArtifactPath = $ExpectedArtifactPath
    }
    if (-not [string]::IsNullOrWhiteSpace($IngestionOutputDirectory)) { $conversionParameters.OutputDirectory = $IngestionOutputDirectory }
    if (-not [string]::IsNullOrWhiteSpace($CommitMessage)) { $conversionParameters.CommitMessage = $CommitMessage }
    if (-not [string]::IsNullOrWhiteSpace($StopCondition)) { $conversionParameters.StopCondition = $StopCondition }

    $conversionOutput = @(& $converter @conversionParameters)
    $conversion = @($conversionOutput | Where-Object {
        $null -ne $_ -and $_.PSObject.Properties.Name -contains 'RequestPath' -and $_.PSObject.Properties.Name -contains 'CompiledPromptPath'
    } | Select-Object -Last 1)
    if ($conversion.Count -ne 1) { throw "Prompt ingestion did not return one request/compiled-path result." }
    $RequestPath = [string]$conversion[0].RequestPath
    $CompiledPromptPath = [string]$conversion[0].CompiledPromptPath
    Write-Host "Cursor populated AgentSwitchboard contracts from: $PromptPath" -ForegroundColor Cyan
}

$canonicalEntrypoint = Join-Path $PSScriptRoot "Invoke-ChatGPTDesktopGnhfSprint.ps1"
if (-not (Test-Path -LiteralPath $canonicalEntrypoint -PathType Leaf)) {
    throw "Canonical GNHF desktop/Cursor runtime is missing: $canonicalEntrypoint"
}

$forward = @{
    RequestPath = $RequestPath
    CompiledPromptPath = $CompiledPromptPath
    RuntimeFamily = "Cursor"
}
if (-not [string]::IsNullOrWhiteSpace($TargetRepo)) {
    $forward.TargetRepo = $TargetRepo
}
if ($PlanOnly) {
    $forward.PlanOnly = $true
}
if ($Run) {
    $forward.Run = $true
}
if ($CreateDisposableProofRepo) {
    $forward.CreateDisposableProofRepo = $true
}
if ($LocalHarnessProof) {
    $forward.LocalHarnessProof = $true
}

& $canonicalEntrypoint @forward
exit $LASTEXITCODE
