[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Contract {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

function Copy-JsonDocument {
    param([Parameter(Mandatory)]$Document)
    return $Document | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
}

function Invoke-FixtureMutation {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)]$Mutation
    )

    $parts = @([string]$Mutation.path -split '\.')
    $parent = $Document
    if ($parts.Count -gt 1) {
        foreach ($part in $parts[0..($parts.Count - 2)]) {
            $parent = $parent.$part
        }
    }
    $leaf = $parts[-1]

    switch ([string]$Mutation.operation) {
        "remove" {
            $parent.PSObject.Properties.Remove($leaf)
        }
        "set" {
            $parent.$leaf = $Mutation.value
        }
        "append" {
            $parent.$leaf = [string]$parent.$leaf + [string]$Mutation.value
        }
        default {
            throw "Unknown fixture mutation operation: $($Mutation.operation)"
        }
    }
}

$modulePath = Join-Path $PSScriptRoot "GnhfPromptContracts.psm1"
$runtimePath = Join-Path $PSScriptRoot "Invoke-ChatGPTDesktopGnhfSprint.ps1"
$cursorRuntimePath = Join-Path $PSScriptRoot "Invoke-CursorGnhfSprint.ps1"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$rootCmdPath = Join-Path $repoRoot "Run-ChatGPTDesktopGnhfSprint.cmd"
$cursorRootCmdPath = Join-Path $repoRoot "Run-CursorGnhfSprint.cmd"
$schemaRoot = Join-Path $PSScriptRoot "schemas"
$fixtureRoot = Join-Path $PSScriptRoot "fixtures"

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$tokens, [ref]$parseErrors)
Assert-Contract ($parseErrors.Count -eq 0) "GnhfPromptContracts.psm1 must parse. $($parseErrors -join '; ')"

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($runtimePath, [ref]$tokens, [ref]$parseErrors)
Assert-Contract ($parseErrors.Count -eq 0) "Invoke-ChatGPTDesktopGnhfSprint.ps1 must parse. $($parseErrors -join '; ')"
$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($cursorRuntimePath, [ref]$tokens, [ref]$parseErrors)
Assert-Contract ($parseErrors.Count -eq 0) "Invoke-CursorGnhfSprint.ps1 must parse. $($parseErrors -join '; ')"
$runtimeText = Get-Content -LiteralPath $runtimePath -Raw
Assert-Contract ($runtimeText.Contains('$validationSummary.baseClean = $proof.baseClean')) "Runtime evidence must report the same final base-clean observation in both artifacts."
Assert-Contract ($runtimeText.Contains('$handoffProofLevel = if ($handoffIsRuntimeResult)')) "Operator handoff must use the versioned runtime result proof level."
Assert-Contract ($runtimeText.Contains('gnhf_removed_failed_worktree_branch_retained_for_review')) "Failed-worktree cleanup by GNHF must be recorded as an explicit preservation gap."
Assert-Contract ($runtimeText.Contains('provider error')) "A zero-token provider failure must classify as a route preflight blocker."
Assert-Contract ($runtimeText.Contains('Expected exactly one changed GNHF branch')) "Runtime success must independently require branch, artifact, nonce, commit, and worktree proof."
Assert-Contract ($runtimeText.Contains('ValidateSet("Desktop", "Cursor")')) "Canonical runtime must support Desktop and Cursor evidence families."
Assert-Contract ($runtimeText.Contains('executionIntent=compile_only rejects -Run')) "Canonical runtime must reject -Run for compile_only intents."
Assert-Contract ($runtimeText.Contains('Gnhf{0}')) "Canonical runtime must write evidence under GnhfDesktop or GnhfCursor."
Assert-Contract ($runtimeText.Contains('OPENCODE_CONFIG_CONTENT')) "Canonical runtime must supply OpenCode model config for opencode routes."
Assert-Contract ($runtimeText.Contains('Start-AutoRoutedGnhfSprint.ps1')) "Disposable proofs must prefer the auto-router launcher."
Assert-Contract ($runtimeText.Contains('ConvertFrom-Json -Depth 40')) "Canonical runtime must normalize result contracts through JSON before validation."
foreach ($evidenceName in @("regular-request.txt", "compiled-gnhf-prompt.txt", "prompt-validation.json", "terminal-transcript.txt", "launch-result.json", "worktree-proof.json", "validation-summary.json", "operator-handoff.txt")) {
    Assert-Contract ($runtimeText.Contains($evidenceName)) "Runtime must declare local evidence artifact $evidenceName."
}
$cursorRuntimeText = Get-Content -LiteralPath $cursorRuntimePath -Raw
Assert-Contract ($cursorRuntimeText.Contains('RuntimeFamily = "Cursor"')) "Cursor entrypoint must select the Cursor runtime family."
Assert-Contract ($cursorRuntimeText.Contains('Invoke-ChatGPTDesktopGnhfSprint.ps1')) "Cursor entrypoint must reuse the canonical runtime instead of inventing a second engine."
$rootCmdText = Get-Content -LiteralPath $rootCmdPath -Raw
Assert-Contract ($rootCmdText.Contains('pwsh.exe -NoLogo -NoProfile')) "Root desktop launcher must require PowerShell 7 without profile side effects."
Assert-Contract ($rootCmdText.Contains('set "RESULT=%ERRORLEVEL%"') -and $rootCmdText.Contains('exit /b %RESULT%')) "Root desktop launcher must preserve the PowerShell exit code."
Assert-Contract ($rootCmdText.Contains('latest-run.txt')) "Root desktop launcher failures must point to exact local evidence."
$cursorRootCmdText = Get-Content -LiteralPath $cursorRootCmdPath -Raw
Assert-Contract ($cursorRootCmdText.Contains('Invoke-CursorGnhfSprint.ps1')) "Root Cursor launcher must call Invoke-CursorGnhfSprint.ps1."
Assert-Contract ($cursorRootCmdText.Contains('GnhfCursor')) "Root Cursor launcher must point operators at GnhfCursor evidence."
Assert-Contract ($cursorRootCmdText.Contains('set "RESULT=%ERRORLEVEL%"') -and $cursorRootCmdText.Contains('exit /b %RESULT%')) "Root Cursor launcher must preserve the PowerShell exit code."

Import-Module $modulePath -Force

$schemaExpectations = [ordered]@{
    "regular-sprint-request.v1.schema.json" = "regular-sprint-request"
    "compiled-gnhf-prompt-result.v1.schema.json" = "compiled-gnhf-prompt-result"
    "desktop-gnhf-launch-request.v1.schema.json" = "desktop-gnhf-launch-request"
    "desktop-gnhf-runtime-result.v1.schema.json" = "desktop-gnhf-runtime-result"
}
foreach ($entry in $schemaExpectations.GetEnumerator()) {
    $schemaPath = Join-Path $schemaRoot $entry.Key
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -Depth 30
    Assert-Contract ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "$($entry.Key) must use JSON Schema 2020-12."
    Assert-Contract ($schema.properties.kind.const -eq $entry.Value) "$($entry.Key) must bind kind '$($entry.Value)'."
    Assert-Contract ($schema.properties.schemaVersion.const -eq 1) "$($entry.Key) must bind schemaVersion 1."
}

$validFixtures = [ordered]@{
    "desktop-gnhf-proof.request.md" = "regular-sprint-request"
    "valid.compile-only.request.json" = "regular-sprint-request"
    "desktop-gnhf-proof.compiled.txt" = "compiled-gnhf-prompt-result"
    "valid.desktop-launch-request.json" = "desktop-gnhf-launch-request"
    "valid.disposable-proof.runtime-result.json" = "desktop-gnhf-runtime-result"
    "blocked.dirty-target.runtime-result.json" = "desktop-gnhf-runtime-result"
    "blocked.detached-target.runtime-result.json" = "desktop-gnhf-runtime-result"
    "blocked.spawn-preflight.runtime-result.json" = "desktop-gnhf-runtime-result"
    "blocked.quota-exhausted.runtime-result.json" = "desktop-gnhf-runtime-result"
}
foreach ($entry in $validFixtures.GetEnumerator()) {
    $result = Test-GnhfPromptContractFile -Path (Join-Path $fixtureRoot $entry.Key) -ExpectedKind $entry.Value
    Assert-Contract $result.Valid "$($entry.Key) should be valid; errors: $($result.Errors -join ', ')"
    Assert-Contract ($result.Kind -eq $entry.Value) "$($entry.Key) should classify as $($entry.Value)."
    Assert-Contract (Test-Path -LiteralPath $result.SchemaPath -PathType Leaf) "$($entry.Key) should resolve a schema path."
}

$request = Get-Content -LiteralPath (Join-Path $fixtureRoot "desktop-gnhf-proof.request.md") -Raw | ConvertFrom-Json -Depth 30
$compiled = Get-Content -LiteralPath (Join-Path $fixtureRoot "desktop-gnhf-proof.compiled.txt") -Raw | ConvertFrom-Json -Depth 30
Assert-Contract ($request.repository.localPath -eq "__TARGET_REPO__") "The regular proof fixture must use the portable target placeholder."
Assert-Contract ($request.executionIntent -eq "local_execute") "The disposable proof request must authorize local_execute."
Assert-Contract ($compiled.repository.localPath -eq "__TARGET_REPO__") "The compiled proof fixture must use the portable target placeholder."
Assert-Contract ($compiled.prompt -match '\{\{TARGET_REPO\}\}') "The compiled prompt must contain {{TARGET_REPO}}."
Assert-Contract ($compiled.prompt -match '\{\{PROOF_NONCE\}\}') "The compiled prompt must contain {{PROOF_NONCE}}."

$compileOnly = Get-Content -LiteralPath (Join-Path $fixtureRoot "valid.compile-only.request.json") -Raw | ConvertFrom-Json -Depth 30
Assert-Contract ($compileOnly.executionIntent -eq "compile_only") "The compile-only fixture must declare executionIntent=compile_only."

$invalidRequest = Test-GnhfPromptContractFile `
    -Path (Join-Path $fixtureRoot "invalid.regular-request.missing-objective.json") `
    -ExpectedKind "regular-sprint-request"
Assert-Contract (-not $invalidRequest.Valid) "The missing-objective regular request must be rejected."
Assert-Contract ($invalidRequest.Errors -contains "regular.objective") "The missing-objective fixture must identify regular.objective."

$missingIntent = Test-GnhfPromptContractFile `
    -Path (Join-Path $fixtureRoot "invalid.regular-request.missing-execution-intent.json") `
    -ExpectedKind "regular-sprint-request"
Assert-Contract (-not $missingIntent.Valid) "The missing-executionIntent regular request must be rejected."
Assert-Contract ($missingIntent.Errors -contains "regular.executionIntent") "The missing-executionIntent fixture must identify regular.executionIntent."

$matrix = Get-Content -LiteralPath (Join-Path $fixtureRoot "invalid.compiled-prompt-cases.json") -Raw | ConvertFrom-Json -Depth 30
foreach ($case in $matrix.cases) {
    $mutated = Copy-JsonDocument $compiled
    Invoke-FixtureMutation -Document $mutated -Mutation $case
    $result = Test-GnhfPromptContract -Document $mutated -ExpectedKind "compiled-gnhf-prompt-result"
    Assert-Contract (-not $result.Valid) "Invalid compiled case '$($case.name)' must be rejected."
    Assert-Contract ($result.Errors -contains [string]$case.expectedError) "Invalid compiled case '$($case.name)' must identify $($case.expectedError); got $($result.Errors -join ', ')."
}

$exitOnly = Test-GnhfPromptContractFile `
    -Path (Join-Path $fixtureRoot "invalid.process-exit-only.runtime-result.json") `
    -ExpectedKind "desktop-gnhf-runtime-result"
Assert-Contract (-not $exitOnly.Valid) "Process exit without artifact and commit proof must be rejected as success."
Assert-Contract ($exitOnly.Errors -contains "runtime.processExitOnlySuccess") "Process-exit-only success must identify runtime.processExitOnlySuccess."

$allFixtureText = Get-ChildItem -LiteralPath $fixtureRoot -File |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw } |
    Out-String
Assert-Contract ($allFixtureText -notmatch '(?i)C:\\Users\\[^\\]+') "Fixtures must not contain a machine-local Windows user path."
Assert-Contract ($allFixtureText -notmatch '(?i)(gh[pousr]_[A-Za-z0-9]{12,}|AKIA[0-9A-Z]{12,}|BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY)') "Fixtures must not contain credential material."

Write-Host "PASS: AgentSwitchboard GNHF prompt contract schemas, classification, fixtures, and rejection cases"
