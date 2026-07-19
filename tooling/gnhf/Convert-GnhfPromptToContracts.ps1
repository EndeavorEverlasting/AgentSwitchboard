[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PromptPath,
    [Parameter(Mandatory)][string]$TargetRepo,
    [string]$OutputDirectory,
    [string]$Agent = 'opencode',
    [ValidateRange(1, 100)][int]$MaxIterations = 4,
    [ValidateRange(1, 1000000000)][long]$MaxTokens = 250000,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 3600,
    [ValidateSet('compile_only', 'local_execute', 'registered_workflow_execute')][string]$ExecutionIntent = 'local_execute',
    [ValidateSet('contract-only', 'local-workstation-observed', 'committed-repository-work')][string]$DesiredProofLevel = 'committed-repository-work',
    [string[]]$ExpectedArtifactPath = @(),
    [string]$CommitMessage,
    [string]$StopCondition
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GnhfIngestionGit {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command git -ErrorAction Stop }
    $output = & $git.Source -C $TargetRepo @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in '$TargetRepo'. $($output | Out-String)"
    }
    return (($output | Out-String).Trim())
}

function Write-GnhfAtomicJson {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $temporary -Encoding utf8NoBOM
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

$PromptPath = (Resolve-Path -LiteralPath $PromptPath -ErrorAction Stop).Path
$TargetRepo = (Resolve-Path -LiteralPath $TargetRepo -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $TargetRepo -PathType Container)) { throw "Target repository is not a directory: $TargetRepo" }
if ((Invoke-GnhfIngestionGit -Arguments @('rev-parse', '--is-inside-work-tree')) -ne 'true') { throw "Target is not a Git worktree: $TargetRepo" }

$baseBranch = Invoke-GnhfIngestionGit -Arguments @('branch', '--show-current')
if ([string]::IsNullOrWhiteSpace($baseBranch)) { throw 'Prompt ingestion requires an attached target branch.' }
$remote = Invoke-GnhfIngestionGit -Arguments @('remote', 'get-url', 'origin')
if ($remote -match '^git@github\.com:(.+)$') { $remote = "https://github.com/$($Matches[1])" }
if ($remote.EndsWith('.git')) { $remote = $remote.Substring(0, $remote.Length - 4) }
if ($remote -notmatch '^https://github\.com/[^/]+/[^/]+$') { throw "Target origin is not a canonical GitHub repository URL: $remote" }

$repositoryName = Split-Path -Leaf $TargetRepo
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $runtimeBase = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\GnhfCursor\compiled-inputs' } else { Join-Path ([IO.Path]::GetTempPath()) 'AgentSwitchboard/GnhfCursor/compiled-inputs' }
    $OutputDirectory = Join-Path $runtimeBase ("{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), [guid]::NewGuid().ToString('N').Substring(0, 8))
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$ingestionModule = Join-Path $PSScriptRoot 'GnhfPromptIngestion.psm1'
$contractModule = Join-Path $PSScriptRoot 'GnhfPromptContracts.psm1'
foreach ($required in @($ingestionModule, $contractModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required prompt module is missing: $required" }
}
Import-Module $ingestionModule -Force
Import-Module $contractModule -Force

$promptText = Get-Content -LiteralPath $PromptPath -Raw
$parameters = @{
    PromptText = $promptText
    RepositoryName = $repositoryName
    RepositoryRemote = $remote
    RepositoryLocalPath = $TargetRepo
    BaseBranch = $baseBranch
    DefaultAgent = $Agent
    DefaultMaxIterations = $MaxIterations
    DefaultMaxTokens = $MaxTokens
    TimeoutSeconds = $TimeoutSeconds
    ExecutionIntent = $ExecutionIntent
    DesiredProofLevel = $DesiredProofLevel
    ExpectedArtifactPath = $ExpectedArtifactPath
}
if (-not [string]::IsNullOrWhiteSpace($CommitMessage)) { $parameters.CommitMessage = $CommitMessage }
if (-not [string]::IsNullOrWhiteSpace($StopCondition)) { $parameters.StopCondition = $StopCondition }

$conversion = ConvertTo-GnhfPromptContracts @parameters
$requestValidation = Test-GnhfPromptContract -Document $conversion.regularRequest -ExpectedKind 'regular-sprint-request'
$compiledValidation = Test-GnhfPromptContract -Document $conversion.compiledPrompt -ExpectedKind 'compiled-gnhf-prompt-result'
if (-not $requestValidation.Valid) { throw "Generated regular request is invalid: $($requestValidation.Errors -join '; ')" }
if (-not $compiledValidation.Valid) { throw "Generated compiled prompt is invalid: $($compiledValidation.Errors -join '; ')" }

$requestPath = Join-Path $OutputDirectory 'regular-request.json'
$compiledPath = Join-Path $OutputDirectory 'compiled-gnhf-prompt.json'
$resultPath = Join-Path $OutputDirectory 'ingestion-result.json'
Write-GnhfAtomicJson -Value $conversion.regularRequest -Path $requestPath
Write-GnhfAtomicJson -Value $conversion.compiledPrompt -Path $compiledPath
$result = [pscustomobject][ordered]@{
    schemaVersion = 1
    sourceKind = $conversion.sourceKind
    promptPath = $PromptPath
    targetRepo = $TargetRepo
    baseBranch = $baseBranch
    repositoryRemote = $remote
    requestPath = $requestPath
    compiledPromptPath = $compiledPath
    artifactPaths = @($conversion.artifactPaths)
    requestValid = $true
    compiledPromptValid = $true
    executionStarted = $false
    proofLevel = 'contract-validation'
    proofCeiling = 'Prompt parsing, normalization, contract generation, and validation only; no agent, provider, GNHF process, repository mutation, push, merge, or deployment was started.'
}
Write-GnhfAtomicJson -Value $result -Path $resultPath

Write-Host "GNHF prompt ingestion complete." -ForegroundColor Green
Write-Host "Source kind:     $($result.sourceKind)"
Write-Host "Regular request: $requestPath"
Write-Host "Compiled prompt: $compiledPath"
Write-Host "Result:          $resultPath"
Write-Output ([pscustomobject]@{
    RequestPath = $requestPath
    CompiledPromptPath = $compiledPath
    ResultPath = $resultPath
    SourceKind = $conversion.sourceKind
})
