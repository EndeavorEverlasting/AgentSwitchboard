[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-IngestionContract {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

$modulePath = Join-Path $PSScriptRoot 'GnhfPromptIngestion.psm1'
$contractPath = Join-Path $PSScriptRoot 'GnhfPromptContracts.psm1'
$converterPath = Join-Path $PSScriptRoot 'Convert-GnhfPromptToContracts.ps1'
$cursorPath = Join-Path $PSScriptRoot 'Invoke-CursorGnhfSprint.ps1'
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
foreach ($path in @($modulePath, $contractPath, $converterPath, $cursorPath)) {
    Assert-IngestionContract (Test-Path -LiteralPath $path -PathType Leaf) "Required ingestion file is missing: $path"
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Assert-IngestionContract ($errors.Count -eq 0) "$path must parse. $($errors.Message -join '; ')"
}

Import-Module $modulePath -Force
Import-Module $contractPath -Force

$repository = [ordered]@{
    RepositoryName = 'prompt-ingestion-fixture'
    RepositoryRemote = 'https://github.com/EndeavorEverlasting/AgentSwitchboard'
    RepositoryLocalPath = '__TARGET_REPO__'
    BaseBranch = 'main'
    TimeoutSeconds = 900
    ExecutionIntent = 'local_execute'
    DesiredProofLevel = 'committed-repository-work'
}

$commandText = Get-Content -LiteralPath (Join-Path $fixtureRoot 'valid.canonical-gnhf-command.txt') -Raw
$commandResult = ConvertTo-GnhfPromptContracts -PromptText $commandText @repository
Assert-IngestionContract ($commandResult.sourceKind -eq 'gnhf-command') 'Canonical command must classify as gnhf-command.'
Assert-IngestionContract ($commandResult.compiledPrompt.agentRoute.agent -eq 'opencode') 'Canonical command must populate the exact agent.'
Assert-IngestionContract ($commandResult.compiledPrompt.bounds.maxIterations -eq 4) 'Canonical command must populate maxIterations.'
Assert-IngestionContract ($commandResult.compiledPrompt.bounds.maxTokens -eq 120000) 'Canonical command must populate maxTokens.'
Assert-IngestionContract ($commandResult.compiledPrompt.gitExecution.mode -eq 'worktree') 'Canonical command must populate worktree mode.'
Assert-IngestionContract ($commandResult.artifactPaths -contains 'proof/gnhf-ingestion-command.txt') 'Canonical command must recover the expected artifact path.'

$regularJsonText = Get-Content -LiteralPath (Join-Path $fixtureRoot 'desktop-gnhf-proof.request.md') -Raw
$regularResult = ConvertTo-GnhfPromptContracts -PromptText $regularJsonText @repository -DefaultAgent 'opencode' -DefaultMaxIterations 2 -DefaultMaxTokens 20000
Assert-IngestionContract ($regularResult.sourceKind -eq 'regular-sprint-request') 'Regular request JSON must classify as regular-sprint-request.'
Assert-IngestionContract ($regularResult.regularRequest.executionIntent -eq 'local_execute') 'Regular request JSON must preserve executionIntent.'
Assert-IngestionContract ($regularResult.compiledPrompt.proofLevel -eq 'local-workstation-observed') 'Regular request JSON must preserve desiredProofLevel.'
Assert-IngestionContract ($regularResult.artifactPaths -contains 'proof/gnhf-desktop-proof.txt') 'Regular request JSON must recover its exact artifact path.'

$sectionedText = Get-Content -LiteralPath (Join-Path $fixtureRoot 'valid.sectioned-repo-sprint.txt') -Raw
$sectionedResult = ConvertTo-GnhfPromptContracts -PromptText $sectionedText @repository -DefaultAgent 'goose' -DefaultMaxIterations 3 -DefaultMaxTokens 90000
Assert-IngestionContract ($sectionedResult.sourceKind -eq 'sectioned-prompt') 'Sectioned prompt must classify as sectioned-prompt.'
Assert-IngestionContract ($sectionedResult.compiledPrompt.agentRoute.agent -eq 'goose') 'Sectioned prompt must use the requested default agent.'
Assert-IngestionContract ($sectionedResult.compiledPrompt.bounds.maxIterations -eq 3) 'Sectioned prompt must use default maxIterations.'
Assert-IngestionContract ($sectionedResult.artifactPaths -contains 'proof/gnhf-ingestion-sectioned.txt') 'Sectioned prompt must recover the expected artifact path.'

foreach ($document in @($commandResult.regularRequest, $commandResult.compiledPrompt, $regularResult.regularRequest, $regularResult.compiledPrompt, $sectionedResult.regularRequest, $sectionedResult.compiledPrompt)) {
    $expectedKind = [string]$document.kind
    $validation = Test-GnhfPromptContract -Document $document -ExpectedKind $expectedKind
    Assert-IngestionContract $validation.Valid "Generated $expectedKind must validate. $($validation.Errors -join '; ')"
}

$missingArtifactRejected = $false
try {
    [void](ConvertTo-GnhfPromptContracts -PromptText 'EXECUTE a bounded sprint with no exact file contract.' @repository)
}
catch {
    $missingArtifactRejected = $_.Exception.Message -match 'No exact repository-relative artifact paths'
}
Assert-IngestionContract $missingArtifactRejected 'Prompt ingestion must fail closed when no exact artifact path exists.'

$unresolvedPlaceholderRejected = $false
$placeholderPrompt = @'
EXECUTE THE REPO SPRINT.
Owned scope:
- proof/result.txt
Expected artifacts:
- proof/result.txt
Objective:
Implement xyz_owned_scope and commit it.
'@
try {
    [void](ConvertTo-GnhfPromptContracts -PromptText $placeholderPrompt @repository)
}
catch {
    $unresolvedPlaceholderRejected = $_.Exception.Message -match 'unresolved xyz_'
}
Assert-IngestionContract $unresolvedPlaceholderRejected 'Prompt ingestion must reject unresolved xyz_* placeholders.'

$cursorText = Get-Content -LiteralPath $cursorPath -Raw
Assert-IngestionContract ($cursorText.Contains('-PromptPath') -and $cursorText.Contains('Convert-GnhfPromptToContracts.ps1')) 'Cursor entrypoint must expose prompt ingestion.'
Assert-IngestionContract ($cursorText.Contains('Use either -PromptPath') -and $cursorText.Contains('RequestPath and -CompiledPromptPath')) 'Cursor entrypoint must reject ambiguous input modes.'
Assert-IngestionContract ($cursorText.Contains('Prompt ingestion did not return one request/compiled-path result')) 'Cursor entrypoint must require one deterministic conversion result.'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agentswitchboard-gnhf-ingestion-{0}" -f [guid]::NewGuid().ToString('N'))
try {
    $repo = Join-Path $tempRoot 'repo'
    $output = Join-Path $tempRoot 'output'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command git -ErrorAction Stop }
    & $git.Source init -b main $repo | Out-Null
    & $git.Source -C $repo config user.name 'AgentSwitchboard Contract Test'
    & $git.Source -C $repo config user.email 'agentswitchboard-contract@invalid.local'
    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value '# fixture' -Encoding utf8NoBOM
    & $git.Source -C $repo add README.md
    & $git.Source -C $repo commit -m 'test: initialize ingestion fixture' | Out-Null
    & $git.Source -C $repo remote add origin 'https://github.com/EndeavorEverlasting/AgentSwitchboard'

    $conversionOutput = @(& $converterPath -PromptPath (Join-Path $fixtureRoot 'valid.sectioned-repo-sprint.txt') -TargetRepo $repo -OutputDirectory $output -Agent opencode -MaxIterations 2 -MaxTokens 50000 -TimeoutSeconds 600)
    $conversion = @($conversionOutput | Where-Object { $_.PSObject.Properties.Name -contains 'RequestPath' } | Select-Object -Last 1)
    Assert-IngestionContract ($conversion.Count -eq 1) 'Converter must return one path result.'
    Assert-IngestionContract (Test-Path -LiteralPath $conversion[0].RequestPath -PathType Leaf) 'Converter must write regular-request.json.'
    Assert-IngestionContract (Test-Path -LiteralPath $conversion[0].CompiledPromptPath -PathType Leaf) 'Converter must write compiled-gnhf-prompt.json.'
    Assert-IngestionContract (Test-Path -LiteralPath $conversion[0].ResultPath -PathType Leaf) 'Converter must write ingestion-result.json.'
    Assert-IngestionContract ([string]::IsNullOrWhiteSpace((& $git.Source -C $repo status --short | Out-String).Trim())) 'Converter must not mutate the target repository.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

$fixtureText = @('valid.canonical-gnhf-command.txt', 'valid.sectioned-repo-sprint.txt') | ForEach-Object { Get-Content -LiteralPath (Join-Path $fixtureRoot $_) -Raw } | Out-String
Assert-IngestionContract ($fixtureText -notmatch '(?i)C:\\Users\\[^\\]+') 'Ingestion fixtures must not contain machine-local user paths.'
Assert-IngestionContract ($fixtureText -notmatch '(?i)(gh[pousr]_[A-Za-z0-9]{12,}|AKIA[0-9A-Z]{12,}|BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY)') 'Ingestion fixtures must not contain credential material.'

Write-Host 'PASS: AgentSwitchboard parses canonical and sectioned GNHF prompts into validated contracts without starting providers or mutating the target repository.'
