[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()
$shaPattern = '^[0-9a-f]{40}$'
$runIdPattern = '^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$'
$integrationStates = @('not-ready', 'ready', 'integrating', 'integrated', 'blocked', 'superseded')
$validationStates = @('passed', 'failed', 'skipped')

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$FailureMessage = ''
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("$Name`: $FailureMessage")
    }
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if (-not $property) {
        return $null
    }
    return $property.Value
}

function Test-UniqueStrings {
    param([object[]]$Values)

    $normalized = @($Values | ForEach-Object { [string]$_ })
    return $normalized.Count -eq @($normalized | Select-Object -Unique).Count
}

function Test-WorkerRunRecord {
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)][string]$FixtureName
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('schemaVersion', 'runId', 'repository', 'worker', 'git', 'scope', 'dependencies', 'changes', 'validation', 'evidence', 'integration')) {
        if (-not $Record.PSObject.Properties[$name]) {
            [void]$errors.Add("missing top-level property '$name'")
        }
    }
    if ($errors.Count -gt 0) {
        return [pscustomobject]@{ Valid = $false; Errors = @($errors) }
    }

    if ([int]$Record.schemaVersion -ne 1) {
        [void]$errors.Add('schemaVersion must equal 1')
    }
    if ([string]$Record.runId -notmatch $runIdPattern) {
        [void]$errors.Add('runId does not match the canonical identifier pattern')
    }

    if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $Record.repository -Name 'name'))) {
        [void]$errors.Add('repository.name is required')
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $Record.repository -Name 'path'))) {
        [void]$errors.Add('repository.path is required')
    }

    foreach ($name in @('executor', 'lane')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $Record.worker -Name $name))) {
            [void]$errors.Add("worker.$name is required")
        }
    }
    if (-not $Record.worker.PSObject.Properties['provider']) {
        [void]$errors.Add('worker.provider must be present, even when unknown or local')
    }

    foreach ($name in @('branch', 'worktreePath')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $Record.git -Name $name))) {
            [void]$errors.Add("git.$name is required")
        }
    }
    foreach ($name in @('baseSha', 'headSha')) {
        if ([string](Get-PropertyValue -Object $Record.git -Name $name) -notmatch $shaPattern) {
            [void]$errors.Add("git.$name must be a full lowercase 40-character commit SHA")
        }
    }
    if (-not $Record.git.PSObject.Properties['dirty']) {
        [void]$errors.Add('git.dirty is required')
    }

    $owned = @($Record.scope.owned)
    $forbidden = @($Record.scope.forbidden)
    if ($owned.Count -eq 0 -or @($owned | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        [void]$errors.Add('scope.owned must contain at least one nonblank entry')
    }
    if (-not (Test-UniqueStrings -Values $owned)) {
        [void]$errors.Add('scope.owned contains duplicate entries')
    }
    if (-not (Test-UniqueStrings -Values $forbidden)) {
        [void]$errors.Add('scope.forbidden contains duplicate entries')
    }

    foreach ($name in @('parentRunIds', 'consumedCommits')) {
        if (-not $Record.dependencies.PSObject.Properties[$name]) {
            [void]$errors.Add("dependencies.$name is required")
        }
    }
    foreach ($sha in @($Record.dependencies.consumedCommits)) {
        if ([string]$sha -notmatch $shaPattern) {
            [void]$errors.Add("dependencies.consumedCommits contains an invalid SHA: $sha")
        }
    }
    if (-not (Test-UniqueStrings -Values @($Record.dependencies.parentRunIds))) {
        [void]$errors.Add('dependencies.parentRunIds contains duplicate entries')
    }
    if (-not (Test-UniqueStrings -Values @($Record.dependencies.consumedCommits))) {
        [void]$errors.Add('dependencies.consumedCommits contains duplicate entries')
    }

    foreach ($name in @('files', 'commits')) {
        if (-not $Record.changes.PSObject.Properties[$name]) {
            [void]$errors.Add("changes.$name is required")
        }
    }
    foreach ($sha in @($Record.changes.commits)) {
        if ([string]$sha -notmatch $shaPattern) {
            [void]$errors.Add("changes.commits contains an invalid SHA: $sha")
        }
    }
    if (-not (Test-UniqueStrings -Values @($Record.changes.files))) {
        [void]$errors.Add('changes.files contains duplicate entries')
    }
    if (-not (Test-UniqueStrings -Values @($Record.changes.commits))) {
        [void]$errors.Add('changes.commits contains duplicate entries')
    }

    foreach ($entry in @($Record.validation)) {
        if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $entry -Name 'command'))) {
            [void]$errors.Add('validation entry has no command')
        }
        if ($validationStates -notcontains [string](Get-PropertyValue -Object $entry -Name 'status')) {
            [void]$errors.Add('validation entry has an unsupported status')
        }
        if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $entry -Name 'evidence'))) {
            [void]$errors.Add('validation entry has no evidence')
        }
    }

    if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $Record.evidence -Name 'summaryPath'))) {
        [void]$errors.Add('evidence.summaryPath is required')
    }
    if (-not $Record.evidence.PSObject.Properties['logPaths']) {
        [void]$errors.Add('evidence.logPaths is required')
    }

    $integrationStatus = [string](Get-PropertyValue -Object $Record.integration -Name 'status')
    if ($integrationStates -notcontains $integrationStatus) {
        [void]$errors.Add("integration.status '$integrationStatus' is unsupported")
    }
    if (-not $Record.integration.PSObject.Properties['conflicts']) {
        [void]$errors.Add('integration.conflicts is required')
    }

    if ($integrationStatus -in @('ready', 'integrated')) {
        if ([bool]$Record.git.dirty) {
            [void]$errors.Add("integration.status '$integrationStatus' requires git.dirty=false")
        }
        if (@($Record.integration.conflicts).Count -gt 0) {
            [void]$errors.Add("integration.status '$integrationStatus' requires no conflicts")
        }
        if (@($Record.changes.commits) -notcontains [string]$Record.git.headSha) {
            [void]$errors.Add("integration.status '$integrationStatus' requires changes.commits to contain git.headSha")
        }
        if (@($Record.validation | Where-Object { $_.status -eq 'failed' }).Count -gt 0) {
            [void]$errors.Add("integration.status '$integrationStatus' cannot contain failed validation")
        }
        if (@($Record.validation | Where-Object { $_.status -eq 'passed' }).Count -eq 0) {
            [void]$errors.Add("integration.status '$integrationStatus' requires at least one passed validation")
        }
    }

    if ($integrationStatus -eq 'superseded' -and [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $Record.integration -Name 'supersededByRunId'))) {
        [void]$errors.Add("integration.status 'superseded' requires supersededByRunId")
    }

    return [pscustomobject]@{
        Valid = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}

$schemaPath = Join-Path $RootPath 'worker-run.schema.json'
$fixturesPath = Join-Path $RootPath 'fixtures'
Add-Result -Passed (Test-Path -LiteralPath $schemaPath -PathType Leaf) -Name 'required/schema' -FailureMessage "Missing $schemaPath"
Add-Result -Passed (Test-Path -LiteralPath $fixturesPath -PathType Container) -Name 'required/fixtures' -FailureMessage "Missing $fixturesPath"

if (Test-Path -LiteralPath $schemaPath -PathType Leaf) {
    try {
        $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        Add-Result -Passed ($schema.properties.schemaVersion.const -eq 1) -Name 'schema/version-const' -FailureMessage 'schemaVersion const is not 1'
        Add-Result -Passed ([string]$schema.properties.git.properties.baseSha.'$ref' -eq '#/$defs/sha') -Name 'schema/base-sha-ref' -FailureMessage 'baseSha does not use the canonical SHA definition'
        Add-Result -Passed ([string]$schema.properties.dependencies.properties.consumedCommits.items.'$ref' -eq '#/$defs/sha') -Name 'schema/consumed-commit-ref' -FailureMessage 'consumed commits do not use the canonical SHA definition'
        Add-Result -Passed ($schema.additionalProperties -eq $false) -Name 'schema/rejects-unknown-top-level-fields' -FailureMessage 'top-level additionalProperties must be false'
    }
    catch {
        Add-Result -Passed $false -Name 'schema/json-parse' -FailureMessage $_.Exception.Message
    }
}

if (Test-Path -LiteralPath $fixturesPath -PathType Container) {
    $fixtures = @(Get-ChildItem -LiteralPath $fixturesPath -Filter 'worker-run.*.json' -File | Sort-Object Name)
    Add-Result -Passed ($fixtures.Count -ge 3) -Name 'fixtures/minimum-coverage' -FailureMessage 'expected at least one valid and two invalid fixtures'

    foreach ($fixture in $fixtures) {
        try {
            $record = Get-Content -LiteralPath $fixture.FullName -Raw | ConvertFrom-Json
            $result = Test-WorkerRunRecord -Record $record -FixtureName $fixture.Name
            $expectedValid = $fixture.Name -eq 'worker-run.valid.json'
            Add-Result `
                -Passed ($result.Valid -eq $expectedValid) `
                -Name "fixture/$($fixture.Name)" `
                -FailureMessage ("expected valid={0}; actual valid={1}; errors={2}" -f $expectedValid, $result.Valid, ($result.Errors -join '; '))
        }
        catch {
            Add-Result -Passed $false -Name "fixture/$($fixture.Name)/json-parse" -FailureMessage $_.Exception.Message
        }
    }
}

Write-Host 'WORKER RUN CONTRACT VALIDATION' -ForegroundColor Cyan
foreach ($pass in $passes) {
    Write-Host "[PASS] $pass" -ForegroundColor Green
}
foreach ($failure in $failures) {
    Write-Host "[FAIL] $failure" -ForegroundColor Red
}
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) {
    exit 1
}
exit 0
