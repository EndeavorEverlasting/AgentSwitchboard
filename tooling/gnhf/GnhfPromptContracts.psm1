Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:SupportedKinds = @{
    "regular-sprint-request" = "regular-sprint-request.v1.schema.json"
    "compiled-gnhf-prompt-result" = "compiled-gnhf-prompt-result.v1.schema.json"
    "desktop-gnhf-launch-request" = "desktop-gnhf-launch-request.v1.schema.json"
    "desktop-gnhf-runtime-result" = "desktop-gnhf-runtime-result.v1.schema.json"
}

function Test-GnhfContractProperty {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    return $null -ne $InputObject -and $null -ne $InputObject.PSObject.Properties[$Name]
}

function Add-GnhfContractError {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Errors,
        [Parameter(Mandatory)][string]$Code
    )

    if (-not $Errors.Contains($Code)) {
        [void]$Errors.Add($Code)
    }
}

function Test-GnhfNonEmptyString {
    param([AllowNull()]$Value)
    return $Value -is [string] -and -not [string]::IsNullOrWhiteSpace($Value)
}

function Test-GnhfNonEmptyArray {
    param([AllowNull()]$Value)
    return $null -ne $Value -and @($Value).Count -gt 0
}

function Test-GnhfRequiredProperty {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Errors
    )

    if (-not (Test-GnhfContractProperty -InputObject $InputObject -Name $Name)) {
        Add-GnhfContractError -Errors $Errors -Code $Code
        return $false
    }
    return $true
}

function Test-GnhfRegularSprintRequest {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Errors
    )

    if (-not (Test-GnhfRequiredProperty $Document "objective" "regular.objective" $Errors) -or
        -not (Test-GnhfNonEmptyString $Document.objective) -or $Document.objective.Length -lt 20) {
        Add-GnhfContractError $Errors "regular.objective"
    }

    if (Test-GnhfRequiredProperty $Document "repository" "regular.repository" $Errors) {
        foreach ($name in @("name", "remote", "localPath", "branchContext")) {
            if (-not (Test-GnhfContractProperty $Document.repository $name) -or
                -not (Test-GnhfNonEmptyString $Document.repository.$name)) {
                Add-GnhfContractError $Errors "regular.repository.$name"
            }
        }
    }

    foreach ($name in @("ownedScope", "forbiddenScope", "expectedArtifacts", "safetyConstraints", "readFirst", "validators")) {
        if (-not (Test-GnhfContractProperty $Document $name) -or
            -not (Test-GnhfNonEmptyArray $Document.$name)) {
            Add-GnhfContractError $Errors "regular.$name"
        }
    }

    $proofLevels = @("contract-only", "local-workstation-observed", "committed-repository-work")
    if (-not (Test-GnhfContractProperty $Document "desiredProofLevel") -or
        $proofLevels -notcontains [string]$Document.desiredProofLevel) {
        Add-GnhfContractError $Errors "regular.desiredProofLevel"
    }

    $executionIntents = @(
        "compile_only",
        "local_execute",
        "environment_configure",
        "registered_workflow_execute"
    )
    if (-not (Test-GnhfContractProperty $Document "executionIntent") -or
        $executionIntents -notcontains [string]$Document.executionIntent) {
        Add-GnhfContractError $Errors "regular.executionIntent"
    }
}

function Test-GnhfCompiledPromptResult {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Errors
    )

    if (-not (Test-GnhfRequiredProperty $Document "repository" "compiled.repository" $Errors)) {
        return
    }
    foreach ($name in @("name", "remote", "localPath")) {
        if (-not (Test-GnhfContractProperty $Document.repository $name) -or
            -not (Test-GnhfNonEmptyString $Document.repository.$name)) {
            Add-GnhfContractError $Errors "compiled.repository.$name"
        }
    }

    $prompt = if (Test-GnhfContractProperty $Document "prompt") { [string]$Document.prompt } else { "" }
    if ($prompt.Length -lt 100 -or $prompt -notmatch '(?i)^\s*EXECUTE\b') {
        Add-GnhfContractError $Errors "compiled.prompt.executable"
    }

    $mode = ""
    if (-not (Test-GnhfContractProperty $Document "gitExecution")) {
        Add-GnhfContractError $Errors "compiled.gitExecution"
    }
    else {
        if (Test-GnhfContractProperty $Document.gitExecution "mode") {
            $mode = [string]$Document.gitExecution.mode
        }
        if ($mode -notin @("worktree", "current-branch")) {
            Add-GnhfContractError $Errors "compiled.gitExecution.mode"
        }
        if (-not (Test-GnhfContractProperty $Document.gitExecution "baseBranch") -or
            -not (Test-GnhfNonEmptyString $Document.gitExecution.baseBranch)) {
            Add-GnhfContractError $Errors "compiled.gitExecution.baseBranch"
        }
        if (($mode -eq "worktree" -and $prompt -match '(?i)current[- ]branch\s+mode') -or
            ($mode -eq "current-branch" -and $prompt -match '(?i)--worktree\b')) {
            Add-GnhfContractError $Errors "compiled.gitExecution.conflict"
        }
    }

    if (-not (Test-GnhfContractProperty $Document "agentRoute") -or
        -not (Test-GnhfContractProperty $Document.agentRoute "agent") -or
        -not (Test-GnhfNonEmptyString $Document.agentRoute.agent)) {
        Add-GnhfContractError $Errors "compiled.agentRoute.agent"
    }

    if (-not (Test-GnhfContractProperty $Document "bounds")) {
        Add-GnhfContractError $Errors "compiled.bounds"
    }
    else {
        foreach ($name in @("maxIterations", "maxTokens", "timeoutSeconds")) {
            if (-not (Test-GnhfContractProperty $Document.bounds $name) -or
                [long]$Document.bounds.$name -lt 1) {
                Add-GnhfContractError $Errors "compiled.bounds.$name"
            }
        }
        if (-not (Test-GnhfContractProperty $Document.bounds "preventSleep") -or
            $Document.bounds.preventSleep -isnot [bool]) {
            Add-GnhfContractError $Errors "compiled.bounds.preventSleep"
        }
    }

    foreach ($name in @("ownedScope", "forbiddenScope", "expectedArtifacts", "readFirst", "validationOrder", "finalResponseContract")) {
        if (-not (Test-GnhfContractProperty $Document $name) -or
            -not (Test-GnhfNonEmptyArray $Document.$name)) {
            Add-GnhfContractError $Errors "compiled.$name"
        }
    }

    if (-not (Test-GnhfContractProperty $Document "commitContract")) {
        Add-GnhfContractError $Errors "compiled.commitContract"
    }
    else {
        if (-not (Test-GnhfContractProperty $Document.commitContract "required") -or
            $Document.commitContract.required -ne $true) {
            Add-GnhfContractError $Errors "compiled.commitContract.required"
        }
        if (-not (Test-GnhfContractProperty $Document.commitContract "message") -or
            -not (Test-GnhfNonEmptyString $Document.commitContract.message)) {
            Add-GnhfContractError $Errors "compiled.commitContract.message"
        }
        if (-not (Test-GnhfContractProperty $Document.commitContract "proof") -or
            -not (Test-GnhfNonEmptyString $Document.commitContract.proof) -or
            [string]$Document.commitContract.proof -notmatch '(?i)(HEAD|commit|ahead)') {
            Add-GnhfContractError $Errors "compiled.commitContract.proof"
        }
    }

    if (-not (Test-GnhfContractProperty $Document "pushContract")) {
        Add-GnhfContractError $Errors "compiled.pushContract"
    }
    else {
        if (-not (Test-GnhfContractProperty $Document.pushContract "mode") -or
            [string]$Document.pushContract.mode -notin @("none", "manual")) {
            Add-GnhfContractError $Errors "compiled.pushContract.mode"
        }
        if (-not (Test-GnhfContractProperty $Document.pushContract "merge") -or
            $Document.pushContract.merge -ne $false) {
            Add-GnhfContractError $Errors "compiled.pushContract.merge"
        }
        if (-not (Test-GnhfContractProperty $Document.pushContract "deploy") -or
            $Document.pushContract.deploy -ne $false) {
            Add-GnhfContractError $Errors "compiled.pushContract.deploy"
        }
    }

    if (-not (Test-GnhfContractProperty $Document "stopCondition") -or
        -not (Test-GnhfNonEmptyString $Document.stopCondition) -or
        [string]$Document.stopCondition -notmatch '(?i)(artifact|commit|validation|clean)') {
        Add-GnhfContractError $Errors "compiled.stopCondition"
    }
    foreach ($name in @("proofLevel", "proofCeiling", "nextCommand")) {
        if (-not (Test-GnhfContractProperty $Document $name) -or
            -not (Test-GnhfNonEmptyString $Document.$name)) {
            Add-GnhfContractError $Errors "compiled.$name"
        }
    }

    if ($prompt -match '(?i)(automatically\s+(?:push|merge|deploy)|git\s+push\b|--push\b|merge\s+the\s+(?:branch|pull request)|deploy\s+to\s+)') {
        Add-GnhfContractError $Errors "compiled.prompt.automaticMutation"
    }
    if ($prompt -notmatch '(?i)process exit (?:alone|only).{0,20}(?:failure|insufficient)') {
        Add-GnhfContractError $Errors "compiled.prompt.processExitCeiling"
    }
}

function Test-GnhfDesktopLaunchRequest {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Errors
    )

    foreach ($name in @("requestPath", "compiledPromptPath", "targetRepo")) {
        if (-not (Test-GnhfContractProperty $Document $name) -or
            -not (Test-GnhfNonEmptyString $Document.$name)) {
            Add-GnhfContractError $Errors "launch.$name"
        }
    }
    if (-not (Test-GnhfContractProperty $Document "executionMode") -or
        [string]$Document.executionMode -notin @("plan", "run", "disposable-proof")) {
        Add-GnhfContractError $Errors "launch.executionMode"
    }
    foreach ($name in @("requireCleanTarget", "visiblePromptEmission")) {
        if (-not (Test-GnhfContractProperty $Document $name) -or $Document.$name -ne $true) {
            Add-GnhfContractError $Errors "launch.$name"
        }
    }
    if (-not (Test-GnhfContractProperty $Document "timeoutSeconds") -or
        [long]$Document.timeoutSeconds -lt 1) {
        Add-GnhfContractError $Errors "launch.timeoutSeconds"
    }
}

function Test-GnhfDesktopRuntimeResult {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Errors
    )

    $status = if (Test-GnhfContractProperty $Document "status") { [string]$Document.status } else { "" }
    if ($status -notin @("succeeded", "blocked", "failed")) {
        Add-GnhfContractError $Errors "runtime.status"
    }
    foreach ($name in @("targetState", "spawn", "process", "commitProof", "artifacts", "validation", "proofLevel", "proofCeiling", "exactNextCommand")) {
        if (-not (Test-GnhfContractProperty $Document $name)) {
            Add-GnhfContractError $Errors "runtime.$name"
        }
    }

    if ($status -eq "blocked") {
        if (-not (Test-GnhfContractProperty $Document "blocker")) {
            Add-GnhfContractError $Errors "runtime.blocker"
        }
        else {
            $codes = @("DIRTY_TARGET", "DETACHED_HEAD", "SPAWN_PREFLIGHT_BLOCKED", "QUOTA_EXHAUSTED")
            if (-not (Test-GnhfContractProperty $Document.blocker "code") -or
                $codes -notcontains [string]$Document.blocker.code) {
                Add-GnhfContractError $Errors "runtime.blocker.code"
            }
        }
    }

    if ($status -eq "succeeded") {
        $spawned = (Test-GnhfContractProperty $Document.spawn "acknowledged") -and $Document.spawn.acknowledged -eq $true
        $exitZero = (Test-GnhfContractProperty $Document.process "exitCode") -and [int]$Document.process.exitCode -eq 0
        $committed = (Test-GnhfContractProperty $Document.commitProof "observed") -and $Document.commitProof.observed -eq $true
        $ahead = (Test-GnhfContractProperty $Document.commitProof "commitsAhead") -and [int]$Document.commitProof.commitsAhead -gt 0
        $artifactProof = (Test-GnhfNonEmptyArray $Document.artifacts) -and @($Document.artifacts | Where-Object observed).Count -gt 0
        $validationProof = (Test-GnhfNonEmptyArray $Document.validation) -and @($Document.validation | Where-Object result -eq "passed").Count -gt 0
        if (-not ($spawned -and $exitZero -and $committed -and $ahead -and $artifactProof -and $validationProof)) {
            Add-GnhfContractError $Errors "runtime.processExitOnlySuccess"
        }
    }
}

function Get-GnhfPromptDocumentKind {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Document)

    if (-not (Test-GnhfContractProperty $Document "kind") -or
        -not (Test-GnhfNonEmptyString $Document.kind)) {
        return "unknown"
    }
    return [string]$Document.kind
}

function Test-GnhfPromptContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Document,
        [ValidateSet("regular-sprint-request", "compiled-gnhf-prompt-result", "desktop-gnhf-launch-request", "desktop-gnhf-runtime-result")]
        [string]$ExpectedKind
    )

    $errors = [Collections.Generic.List[string]]::new()
    $kind = Get-GnhfPromptDocumentKind -Document $Document

    if ($kind -eq "unknown" -or -not $script:SupportedKinds.ContainsKey($kind)) {
        Add-GnhfContractError $errors "document.kind"
    }
    if ($ExpectedKind -and $kind -ne $ExpectedKind) {
        Add-GnhfContractError $errors "document.expectedKind"
    }
    if (-not (Test-GnhfContractProperty $Document "schemaVersion") -or
        [int]$Document.schemaVersion -ne 1) {
        Add-GnhfContractError $errors "document.schemaVersion"
    }

    $serialized = $Document | ConvertTo-Json -Depth 30 -Compress
    if ($serialized -match '(?i)(sk-[A-Za-z][A-Za-z0-9_-]{7,}|gh[pousr]_[A-Za-z0-9]{8,}|AKIA[0-9A-Z]{12,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)') {
        Add-GnhfContractError $errors "document.secretLikeContent"
    }
    if ($serialized -match '(?i)(previous (?:chat|conversation)|chat history|earlier messages?|as (?:discussed|stated) (?:above|earlier))') {
        Add-GnhfContractError $errors "document.hiddenChatHistory"
    }
    if ($serialized -match '(?i)C:\\\\Users\\\\[^\\\\]+\\\\(?:\.ssh|\.aws|\.azure|AppData\\\\Roaming\\\\gcloud)') {
        Add-GnhfContractError $errors "document.machineLocalCredentialPath"
    }

    switch ($kind) {
        "regular-sprint-request" { Test-GnhfRegularSprintRequest $Document $errors }
        "compiled-gnhf-prompt-result" { Test-GnhfCompiledPromptResult $Document $errors }
        "desktop-gnhf-launch-request" { Test-GnhfDesktopLaunchRequest $Document $errors }
        "desktop-gnhf-runtime-result" { Test-GnhfDesktopRuntimeResult $Document $errors }
    }

    $schemaPath = if ($script:SupportedKinds.ContainsKey($kind)) {
        Join-Path $PSScriptRoot "schemas/$($script:SupportedKinds[$kind])"
    }
    else {
        $null
    }

    return [pscustomobject]@{
        Valid = $errors.Count -eq 0
        Kind = $kind
        SchemaVersion = if (Test-GnhfContractProperty $Document "schemaVersion") { $Document.schemaVersion } else { $null }
        SchemaPath = $schemaPath
        Errors = @($errors)
    }
}

function Test-GnhfPromptContractFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet("regular-sprint-request", "compiled-gnhf-prompt-result", "desktop-gnhf-launch-request", "desktop-gnhf-runtime-result")]
        [string]$ExpectedKind
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    try {
        $document = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json -Depth 30 -ErrorAction Stop
    }
    catch {
        return [pscustomobject]@{
            Valid = $false
            Kind = "unknown"
            SchemaVersion = $null
            SchemaPath = $null
            Errors = @("document.invalidJson")
        }
    }
    return Test-GnhfPromptContract -Document $document -ExpectedKind $ExpectedKind
}

Export-ModuleMember -Function Get-GnhfPromptDocumentKind, Test-GnhfPromptContract, Test-GnhfPromptContractFile
