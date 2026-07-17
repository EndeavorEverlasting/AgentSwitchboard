Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-GnhfPromptPlaceholder {
    param([AllowNull()][string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and
        $Value -match '(?i)(\bxyz_[A-Za-z0-9_]+\b|__[A-Za-z0-9_]+__|<[^>\r\n]+>)'
}

function Get-GnhfPromptSection {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string[]]$Names)
    $values = [Collections.Generic.List[string]]::new()
    $active = $false
    foreach ($line in @($Text -split '\r?\n')) {
        $trimmed = $line.Trim()
        $heading = $false
        foreach ($name in $Names) {
            $match = [regex]::Match($trimmed, ('(?i)^' + [regex]::Escape($name) + '\s*:\s*(.*)$'))
            if ($match.Success) {
                $active = $true
                $heading = $true
                if (-not [string]::IsNullOrWhiteSpace($match.Groups[1].Value)) {
                    [void]$values.Add($match.Groups[1].Value.Trim())
                }
                break
            }
        }
        if ($heading) { continue }
        if (-not $active) { continue }
        if ($trimmed -match '^[A-Za-z][A-Za-z0-9 _/\-]{1,48}\s*:\s*') { break }
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $value = ($trimmed -replace '^\s*(?:[-*]|\d+[.)])\s*', '').Trim()
        if ($value) { [void]$values.Add($value) }
    }
    return @($values | Select-Object -Unique)
}

function Get-GnhfCommandOption {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Name)
    $match = [regex]::Match($Text, ('(?im)^\s*--' + [regex]::Escape($Name) + '\s+(?:"([^"]+)"|([^\s`]+))'))
    if (-not $match.Success) { return $null }
    if ($match.Groups[1].Success) { return $match.Groups[1].Value }
    return $match.Groups[2].Value
}

function Get-GnhfCommandPromptMetadata {
    param([Parameter(Mandatory)][string]$Text)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if (@($errors).Count) {
        $messages = (($errors | ForEach-Object { $_.Message }) -join '; ')
        throw "The GNHF PowerShell command does not parse: $messages"
    }
    $commands = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            [string]::Equals($node.GetCommandName(), 'gnhf', [StringComparison]::OrdinalIgnoreCase)
    }, $true))
    if ($commands.Count -ne 1) { throw "Expected exactly one gnhf command; found $($commands.Count)." }
    $command = $commands[0]
    $objective = @($command.FindAll({
        param($node)
        ($node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
         $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
         [string]$node.Value -match '(?im)^\s*(Repo|Repository|Run from)\s*:'
    }, $true) | Select-Object -Last 1)
    if ($objective.Count -ne 1) { throw 'The gnhf command requires one quoted objective block beginning with Repo, Repository, or Run from.' }
    $offset = $objective[0].Extent.StartOffset - $command.Extent.StartOffset
    $optionText = $command.Extent.Text.Substring(0, $offset)
    $worktree = [regex]::IsMatch($optionText, '(?im)^\s*--worktree(?:\s*`)?\s*$')
    $current = [regex]::IsMatch($optionText, '(?im)^\s*--current-branch(?:\s*`)?\s*$')
    if ($worktree -eq $current) { throw 'The gnhf command requires exactly one of --worktree or --current-branch.' }
    if ([regex]::IsMatch($optionText, '(?im)^\s*--push(?:\s*`)?\s*$')) { throw 'Prompt ingestion does not authorize --push.' }
    $metadata = [ordered]@{
        sourceKind = 'gnhf-command'
        promptBody = [string]$objective[0].Value
        agent = Get-GnhfCommandOption $optionText 'agent'
        gitMode = if ($worktree) { 'worktree' } else { 'current-branch' }
        maxIterations = Get-GnhfCommandOption $optionText 'max-iterations'
        maxTokens = Get-GnhfCommandOption $optionText 'max-tokens'
        preventSleep = Get-GnhfCommandOption $optionText 'prevent-sleep'
        stopCondition = Get-GnhfCommandOption $optionText 'stop-when'
    }
    foreach ($name in @('agent','maxIterations','maxTokens','preventSleep','stopCondition')) {
        if ([string]::IsNullOrWhiteSpace([string]$metadata[$name])) { throw "The gnhf command is missing required option '$name'." }
    }
    if ([string]$metadata.preventSleep -cne 'on') { throw 'The gnhf command requires --prevent-sleep on.' }
    $metadata.maxIterations = [int]$metadata.maxIterations
    $metadata.maxTokens = [long]$metadata.maxTokens
    $metadata.preventSleep = $true
    return [pscustomobject]$metadata
}

function Get-GnhfArtifactPaths {
    param([string[]]$Values, [string[]]$ExplicitPaths = @())
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($path in @($ExplicitPaths)) { if ($path) { [void]$paths.Add($path.Trim()) } }
    foreach ($value in @($Values)) {
        if (-not $value) { continue }
        foreach ($match in [regex]::Matches($value, '(?i)(?<![A-Za-z]:)(?<!https://)(?<!http://)(?:[A-Za-z0-9_.-]+[\\/])+[A-Za-z0-9_.-]+\.[A-Za-z0-9]{1,12}')) {
            [void]$paths.Add($match.Value)
        }
        if ($value.Trim() -match '^[A-Za-z0-9_.-]+\.[A-Za-z0-9]{1,12}$') { [void]$paths.Add($value.Trim()) }
    }
    $trimCharacters = [char[]]@([char]0x60, [char]0x22, [char]0x27, [char]0x2C, [char]0x3B)
    $result = [Collections.Generic.List[string]]::new()
    foreach ($path in @($paths | Select-Object -Unique)) {
        $candidate = ([string]$path).Trim($trimCharacters).Replace('\','/')
        if ([IO.Path]::IsPathRooted($candidate) -or $candidate.StartsWith('/') -or $candidate -match '(^|/)\.\.(/|$)' -or $candidate.Contains('*')) {
            throw "Expected artifact paths must be exact repository-relative files: $candidate"
        }
        if (Test-GnhfPromptPlaceholder $candidate) { throw "Expected artifact path contains a placeholder: $candidate" }
        [void]$result.Add($candidate)
    }
    return @($result | Select-Object -Unique)
}

function ConvertTo-GnhfPromptContracts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PromptText,
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][string]$RepositoryRemote,
        [Parameter(Mandatory)][string]$RepositoryLocalPath,
        [Parameter(Mandatory)][string]$BaseBranch,
        [string]$DefaultAgent = 'opencode',
        [ValidateRange(1,100)][int]$DefaultMaxIterations = 4,
        [ValidateRange(1,1000000000)][long]$DefaultMaxTokens = 250000,
        [ValidateRange(1,86400)][int]$TimeoutSeconds = 3600,
        [ValidateSet('compile_only','local_execute','registered_workflow_execute')][string]$ExecutionIntent = 'local_execute',
        [ValidateSet('contract-only','local-workstation-observed','committed-repository-work')][string]$DesiredProofLevel = 'committed-repository-work',
        [string[]]$ExpectedArtifactPath = @(),
        [string]$CommitMessage,
        [string]$StopCondition
    )
    if ([string]::IsNullOrWhiteSpace($PromptText)) { throw 'Prompt text is empty.' }
    if ($RepositoryRemote -notmatch '^https://github\.com/[^/]+/[^/]+(?:\.git)?$') { throw "Repository remote must be a canonical GitHub URL: $RepositoryRemote" }
    $text = $PromptText.Trim()
    $sourceKind = 'sectioned-prompt'
    $body = $text
    $regular = $null
    $command = $null
    if ($text.StartsWith('{')) {
        try { $regular = $text | ConvertFrom-Json -Depth 50 -ErrorAction Stop } catch { throw "JSON prompt input is malformed: $($_.Exception.Message)" }
        if ([string]$regular.kind -ne 'regular-sprint-request') { throw 'JSON ingestion accepts regular-sprint-request only.' }
        $sourceKind = 'regular-sprint-request'
        $body = [string]$regular.objective
    } elseif ($text -match '(?is)^\s*gnhf(?:\s|`)') {
        $command = Get-GnhfCommandPromptMetadata $text
        $sourceKind = $command.sourceKind
        $body = $command.promptBody
    }
    $sections = if ($regular) { $text } else { $body }
    $owned = if ($regular) { @($regular.ownedScope | ForEach-Object { [string]$_ }) } else { Get-GnhfPromptSection $sections @('Owned scope') }
    $forbidden = if ($regular) { @($regular.forbiddenScope | ForEach-Object { [string]$_ }) } else { Get-GnhfPromptSection $sections @('Forbidden scope') }
    $artifactDescriptions = if ($regular) { @($regular.expectedArtifacts | ForEach-Object { [string]$_ }) } else { Get-GnhfPromptSection $sections @('Expected artifacts','Required deliverable','Expected artifact') }
    $artifacts = Get-GnhfArtifactPaths (@($artifactDescriptions) + @($owned)) $ExpectedArtifactPath
    if (-not @($artifacts).Count) { throw 'No exact repository-relative artifact paths were found. Add concrete paths or pass -ExpectedArtifactPath.' }
    $owned = @($owned | Where-Object { $_ -and -not (Test-GnhfPromptPlaceholder $_) } | Select-Object -Unique)
    if (-not $owned.Count) { $owned = @($artifacts) }
    $forbidden = @($forbidden | Where-Object { $_ -and -not (Test-GnhfPromptPlaceholder $_) } | Select-Object -Unique)
    if (-not $forbidden.Count) { $forbidden = @('Credentials, authentication, merge, force-push, deployment, live or personal data mutation, runtime copies, and unrelated work') }
    $readFirst = if ($regular) { @($regular.readFirst | ForEach-Object { [string]$_ }) } else { Get-GnhfPromptSection $sections @('Read first','Inspect first') }
    $readFirst = @($readFirst | Where-Object { $_ -and -not (Test-GnhfPromptPlaceholder $_) } | Select-Object -Unique)
    if (-not $readFirst.Count) { $readFirst = @('AGENTS.md','README.md') }
    $validators = if ($regular) { @($regular.validators | ForEach-Object { [string]$_ }) } else { Get-GnhfPromptSection $sections @('Validation','Validation order') }
    $validators = @($validators | Where-Object { $_ -and -not (Test-GnhfPromptPlaceholder $_) } | Select-Object -Unique)
    if (-not $validators.Count) { $validators = @('git diff --check','git status --short') }
    $objectiveParts = if ($regular) { @([string]$regular.objective) } else { Get-GnhfPromptSection $sections @('Objective','Sprint','Mission') }
    $objective = (@($objectiveParts) -join ' ').Trim()
    if ($objective.Length -lt 20) { $objective = 'Complete the bounded repository sprint described by the supplied prompt and commit the exact required artifacts.' }
    $intent = if ($regular) { [string]$regular.executionIntent } else { $ExecutionIntent }
    $proofLevel = if ($regular) { [string]$regular.desiredProofLevel } else { $DesiredProofLevel }
    $agent = if ($command) { [string]$command.agent } else { $DefaultAgent }
    $gitMode = if ($command) { [string]$command.gitMode } else { 'worktree' }
    $maxIterations = if ($command) { [int]$command.maxIterations } else { $DefaultMaxIterations }
    $maxTokens = if ($command) { [long]$command.maxTokens } else { $DefaultMaxTokens }
    $stop = if ($command) { [string]$command.stopCondition } elseif ($StopCondition) { $StopCondition } else { (@(Get-GnhfPromptSection $sections @('Stop condition','Stop when')) -join ' ').Trim() }
    if ($stop.Length -lt 20 -or $stop -notmatch '(?i)(artifact|commit|validation|clean)') { $stop = 'The required artifacts are committed ahead of base, validation passes or exact blockers are recorded, and the worktree is clean.' }
    if (-not $CommitMessage) { $CommitMessage = (@(Get-GnhfPromptSection $sections @('Commit message')) -join ' ').Trim() }
    if (-not $CommitMessage) { $CommitMessage = 'feat(gnhf): complete bounded prompt sprint' }
    $normalized = $body.Trim() -replace '(?i)xyz_repo_or_path|__TARGET_REPO__|<TARGET_REPO>', '{{TARGET_REPO}}'
    if ($normalized -match '(?i)\bxyz_[A-Za-z0-9_]+\b') { throw 'The prompt still contains unresolved xyz_* placeholders.' }
    if (-not $normalized.Contains('{{TARGET_REPO}}')) { $normalized = "Repository: {{TARGET_REPO}}`n`n$normalized" }
    if ($normalized -notmatch '(?i)^\s*EXECUTE\b') { $normalized = "EXECUTE THIS BOUNDED GNHF SPRINT.`n`n$normalized" }
    $artifactLines = @($artifacts | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    $guardrail = @"

AgentSwitchboard orchestration contract:
- Use agent route $agent with $gitMode Git execution from base branch $BaseBranch.
- Maximum iterations: $maxIterations. Maximum tokens: $maxTokens. Prevent sleep: on. Timeout seconds: $TimeoutSeconds.
- Required exact tracked artifacts:
$artifactLines
- Commit with exact message: $CommitMessage
- Do not push, merge, deploy, authenticate, expose credentials, force-push, write the default branch, or mutate live or personal data.
- Process exit alone is failure; success requires the artifacts in HEAD, a commit ahead of base, passed validation, and a clean worktree.
- Final response must include CONTEXT, WORK COMMITTED, VALIDATION, GAPS, FINAL GIT STATE, and EXACT NEXT COMMAND.
"@
    $safety = [Collections.Generic.List[string]]::new()
    if ($regular) { foreach ($item in @($regular.safetyConstraints)) { if ($item) { [void]$safety.Add([string]$item) } } }
    foreach ($item in @('Keep the target clean and attached before launch','Do not push, merge, deploy, authenticate, expose credentials, force-push, or mutate live or personal data','Process exit without artifact and commit proof is failure')) { [void]$safety.Add($item) }
    $request = [pscustomobject][ordered]@{
        kind='regular-sprint-request'; schemaVersion=1; objective=$objective
        repository=[pscustomobject][ordered]@{ name=$RepositoryName; remote=$RepositoryRemote; localPath=$RepositoryLocalPath; branchContext="Use $gitMode execution from clean attached branch '$BaseBranch'." }
        ownedScope=@($owned); forbiddenScope=@($forbidden)
        expectedArtifacts=@($artifacts | ForEach-Object { "Committed $_ with validation and HEAD proof" })
        safetyConstraints=@($safety | Select-Object -Unique); desiredProofLevel=$proofLevel; executionIntent=$intent
        readFirst=@($readFirst); validators=@($validators)
    }
    $compiled = [pscustomobject][ordered]@{
        kind='compiled-gnhf-prompt-result'; schemaVersion=1
        repository=[pscustomobject][ordered]@{ name=$RepositoryName; remote=$RepositoryRemote; localPath=$RepositoryLocalPath }
        prompt=($normalized + $guardrail).Trim()
        gitExecution=[pscustomobject][ordered]@{ mode=$gitMode; baseBranch=$BaseBranch }
        agentRoute=[pscustomobject][ordered]@{ agent=$agent; routeId="ingested-$agent" }
        bounds=[pscustomobject][ordered]@{ maxIterations=$maxIterations; maxTokens=$maxTokens; preventSleep=$true; timeoutSeconds=$TimeoutSeconds }
        ownedScope=@($owned); forbiddenScope=@($forbidden)
        expectedArtifacts=@($artifacts | ForEach-Object { [pscustomobject][ordered]@{ path=$_; proof="File exists in HEAD and is committed ahead of $BaseBranch" } })
        readFirst=@($readFirst); validationOrder=@($validators)
        commitContract=[pscustomobject][ordered]@{ required=$true; message=$CommitMessage; proof="HEAD contains the artifact commit and is ahead of base branch $BaseBranch" }
        pushContract=[pscustomobject][ordered]@{ mode='none'; merge=$false; deploy=$false }
        stopCondition=$stop; proofLevel=$proofLevel
        proofCeiling='Deterministic prompt ingestion plus downstream runtime proof only; no provider quality, merge, deployment, or live-target claim is inferred from compilation.'
        finalResponseContract=@('CONTEXT','WORK COMMITTED','VALIDATION','GAPS','FINAL GIT STATE','EXACT NEXT COMMAND')
        nextCommand='git status --short'
    }
    return [pscustomobject][ordered]@{ sourceKind=$sourceKind; regularRequest=$request; compiledPrompt=$compiled; artifactPaths=@($artifacts) }
}

Export-ModuleMember -Function ConvertTo-GnhfPromptContracts, Get-GnhfCommandPromptMetadata, Get-GnhfPromptSection
