[CmdletBinding()]
param(
    [string]$RootPath,
    [string[]]$CandidatePath,
    [string]$OutputRoot,
    [switch]$PassThru,
    [switch]$NoReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve operator-command validator directory. Supply -RootPath explicitly.'
    }
    $RootPath = Split-Path -Parent $PSScriptRoot
}
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

$contractRelative = 'tooling\profiles\windows\harness\technician-live-cert\operator-command-contract.json'
$contractPath = Join-Path $RootPath $contractRelative
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    throw "Operator-command contract is missing: $contractPath"
}

$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
if ($contract.contractId -ne 'agentswitchboard.operator-command-envelope.v1') {
    throw "Unexpected operator-command contract ID '$($contract.contractId)'."
}

$requiredRuleIds = @(
    'duplicate-powershell-prompt',
    'powershell-prompt-prefix',
    'cmd-prompt-prefix',
    'continuation-prompt',
    'powershell-error-location',
    'powershell-error-metadata',
    'powershell-error-header',
    'instruction-prose-in-command-block'
)
$availableRuleIds = @($contract.rules | ForEach-Object { [string]$_.id })
foreach ($requiredRuleId in $requiredRuleIds) {
    if ($requiredRuleId -notin $availableRuleIds) {
        throw "Operator-command contract is missing required rule '$requiredRuleId'."
    }
}

$fixtureRelative = [string]$contract.fixturePath
if ($fixtureRelative -ne 'tooling/profiles/windows/harness/technician-live-cert/fixtures/operator-command-contamination.fixture.json') {
    throw "Unexpected operator-command fixture path '$fixtureRelative'."
}
$fixturePath = Join-Path $RootPath $fixtureRelative
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
    throw "Operator-command contamination fixture is missing: $fixturePath"
}
$fixture = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\technician-live-cert\operator-command-envelope'
    }
    else {
        Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/technician-live-cert/operator-command-envelope'
    }
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

$violations = @()
$fixtureFailures = @()
$scannedSources = @()

function Get-SanitizedExcerpt {
    param([AllowEmptyString()][string]$Text)

    $sanitized = $Text
    for ($pass = 0; $pass -lt 4; $pass++) {
        $before = $sanitized
        foreach ($pattern in $contract.sanitization.stripPromptPatterns) {
            $sanitized = [regex]::Replace($sanitized, [string]$pattern, '')
        }
        if ($sanitized -eq $before) {
            break
        }
    }

    foreach ($redaction in $contract.sanitization.redactPatterns) {
        $sanitized = [regex]::Replace(
            $sanitized,
            [string]$redaction.pattern,
            [string]$redaction.replacement
        )
    }

    $sanitized = $sanitized.Trim()
    $maximum = [int]$contract.sanitization.maximumExcerptCharacters
    if ($sanitized.Length -gt $maximum) {
        return $sanitized.Substring(0, $maximum) + '…'
    }
    return $sanitized
}

function Get-RuleIds {
    param([AllowEmptyString()][string]$Text)

    $matches = @()
    foreach ($rule in $contract.rules) {
        if ([regex]::IsMatch($Text, [string]$rule.pattern)) {
            $matches += [string]$rule.id
        }
    }
    return $matches
}

function Get-MarkdownCommandLines {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$DisplayPath
    )

    $lines = @(Get-Content -LiteralPath $Path)
    $insideFence = $false
    $fenceMarker = ''
    $fenceLanguage = ''
    $records = @()
    $allowedLanguages = @($contract.fenceLanguages | ForEach-Object { ([string]$_).ToLowerInvariant() })

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]
        if (-not $insideFence) {
            $open = [regex]::Match($line, '^\s*(?<marker>`{3,}|~{3,})(?<lang>[A-Za-z0-9_+-]*)\s*$')
            if ($open.Success) {
                $insideFence = $true
                $fenceMarker = [string]$open.Groups['marker'].Value
                $fenceLanguage = ([string]$open.Groups['lang'].Value).ToLowerInvariant()
            }
            continue
        }

        $closePattern = '^\s*' + [regex]::Escape($fenceMarker) + '\s*$'
        if ([regex]::IsMatch($line, $closePattern)) {
            $insideFence = $false
            $fenceMarker = ''
            $fenceLanguage = ''
            continue
        }

        if ($allowedLanguages -contains $fenceLanguage) {
            $records += [pscustomobject]@{
                path = $DisplayPath
                line = $index + 1
                language = $fenceLanguage
                text = $line
            }
        }
    }

    if ($insideFence) {
        $script:violations += [pscustomobject]@{
            path = $DisplayPath
            line = $lines.Count
            language = $fenceLanguage
            ruleId = 'unterminated-command-fence'
            severity = 'error'
            message = 'A command fence was opened but not closed.'
            excerpt = ''
            sanitizedCommand = ''
        }
    }

    return $records
}

function Get-PlainTextLines {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$DisplayPath
    )

    $records = @()
    $lines = @(Get-Content -LiteralPath $Path)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $records += [pscustomobject]@{
            path = $DisplayPath
            line = $index + 1
            language = 'plain'
            text = [string]$lines[$index]
        }
    }
    return $records
}

function Test-Records {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records)

    foreach ($record in $Records) {
        if ([string]::IsNullOrWhiteSpace([string]$record.text)) {
            continue
        }

        foreach ($rule in $contract.rules) {
            if (-not [regex]::IsMatch([string]$record.text, [string]$rule.pattern)) {
                continue
            }

            $redactedOriginal = Get-SanitizedExcerpt -Text ([string]$record.text)
            $sanitizedCommand = if ([string]$rule.id -in @(
                'duplicate-powershell-prompt',
                'powershell-prompt-prefix',
                'cmd-prompt-prefix'
            )) {
                $redactedOriginal
            }
            else {
                ''
            }

            $script:violations += [pscustomobject]@{
                path = [string]$record.path
                line = [int]$record.line
                language = [string]$record.language
                ruleId = [string]$rule.id
                severity = [string]$rule.severity
                message = [string]$rule.message
                excerpt = $redactedOriginal
                sanitizedCommand = $sanitizedCommand
            }
        }
    }
}

foreach ($case in $fixture.cases) {
    $actual = @(Get-RuleIds -Text ([string]$case.text) | Sort-Object -Unique)
    $expected = @($case.expectedRuleIds | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $missing = @($expected | Where-Object { $_ -notin $actual })
    $unexpected = @($actual | Where-Object { $_ -notin $expected })

    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0) {
        $fixtureFailures += [pscustomobject]@{
            caseId = [string]$case.id
            missingRuleIds = $missing
            unexpectedRuleIds = $unexpected
        }
    }
}

$sourcePaths = @()
foreach ($relativePath in $contract.scanPaths) {
    $sourcePaths += Join-Path $RootPath ([string]$relativePath)
}
foreach ($candidate in @($CandidatePath)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        $sourcePaths += [System.IO.Path]::GetFullPath($candidate)
    }
}

foreach ($sourcePath in $sourcePaths) {
    $isRepositorySource = $sourcePath.StartsWith(
        $RootPath,
        [System.StringComparison]::OrdinalIgnoreCase
    )
    $displayPath = if ($isRepositorySource) {
        $relative = $sourcePath.Substring($RootPath.Length) -replace '^[\\/]+', ''
        $relative -replace '\\', '/'
    }
    else {
        [regex]::Replace($sourcePath, '(?i)C:\\Users\\[^\\\r\n]+', 'C:\Users\<redacted>')
    }

    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        $violations += [pscustomobject]@{
            path = $displayPath
            line = 0
            language = ''
            ruleId = 'missing-operator-surface'
            severity = 'error'
            message = 'A registered operator-command surface is missing.'
            excerpt = ''
            sanitizedCommand = ''
        }
        continue
    }

    $extension = [System.IO.Path]::GetExtension($sourcePath).ToLowerInvariant()
    $records = if ($extension -in @('.md', '.markdown')) {
        @(Get-MarkdownCommandLines -Path $sourcePath -DisplayPath $displayPath)
    }
    else {
        @(Get-PlainTextLines -Path $sourcePath -DisplayPath $displayPath)
    }

    $scannedSources += [pscustomobject]@{
        path = $displayPath
        lineCount = @(Get-Content -LiteralPath $sourcePath).Count
        candidateLineCount = $records.Count
    }
    Test-Records -Records $records
}

$status = if ($violations.Count -eq 0 -and $fixtureFailures.Count -eq 0) {
    'PASS'
}
else {
    'FAIL'
}

$result = [ordered]@{
    schema = 'agentswitchboard.operator-command-envelope-report.v1'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    root = $RootPath
    status = $status
    contract = $contractRelative -replace '\\', '/'
    fixture = $fixtureRelative
    scannedSources = $scannedSources
    violationCount = $violations.Count
    fixtureFailureCount = $fixtureFailures.Count
    violations = $violations
    fixtureFailures = $fixtureFailures
    proofCeiling = [string]$contract.proofCeiling
    nextCommand = if ($status -eq 'PASS') {
        'pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertHarness.ps1'
    }
    else {
        'pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1'
    }
}

$jsonPath = Join-Path $OutputRoot ([string]$contract.generatedEvidence.json)
$markdownPath = Join-Path $OutputRoot ([string]$contract.generatedEvidence.markdown)

if (-not $NoReport) {
    if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $OutputRoot -Force
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $jsonPath,
        ($result | ConvertTo-Json -Depth 12),
        $encoding
    )

    $violationLines = if ($violations.Count -eq 0) {
        @('| none | - | - | - |')
    }
    else {
        @($violations | ForEach-Object {
            $safeCommand = ([string]$_.sanitizedCommand).Replace('|', '\|')
            '| {0} | {1} | {2} | `{3}` |' -f $_.ruleId, $_.path, $_.line, $safeCommand
        })
    }
    $fixtureLines = if ($fixtureFailures.Count -eq 0) {
        @('| all fixtures | passed |')
    }
    else {
        @($fixtureFailures | ForEach-Object {
            '| {0} | missing={1}; unexpected={2} |' -f $_.caseId, ($_.missingRuleIds -join ','), ($_.unexpectedRuleIds -join ',')
        })
    }

    $markdown = @"
# Operator Command Envelope Report

- Repository: ``EndeavorEverlasting/AgentSwitchboard``
- Generated: ``$($result.generatedAt)``
- Status: **$status**
- Registered sources scanned: **$($scannedSources.Count)**
- Violations: **$($violations.Count)**
- Fixture failures: **$($fixtureFailures.Count)**
- Proof ceiling: $($result.proofCeiling)

## Violations

| Rule | Path | Line | Sanitized executable input |
|---|---|---:|---|
$($violationLines -join "`n")

## Fixture contract

| Fixture | Result |
|---|---|
$($fixtureLines -join "`n")

## Exact next command

~~~powershell
$($result.nextCommand)
~~~
"@
    [System.IO.File]::WriteAllText($markdownPath, $markdown, $encoding)
}

if ($env:GITHUB_ACTIONS -eq 'true') {
    foreach ($violation in $violations) {
        $message = ([string]$violation.message).Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
        Write-Host "::error file=$($violation.path),line=$($violation.line),title=Operator command envelope violation::$message"
    }
    foreach ($fixtureFailure in $fixtureFailures) {
        Write-Host "::error title=Operator command fixture failure::Fixture $($fixtureFailure.caseId) failed command-envelope classification."
    }
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Operator Command Envelope Validation' -ForegroundColor White
Write-Host " Status: $status"
Write-Host " Sources: $($scannedSources.Count)"
Write-Host " Violations: $($violations.Count)"
Write-Host " Fixture failures: $($fixtureFailures.Count)"
if (-not $NoReport) {
    Write-Host " JSON: $jsonPath"
    Write-Host " Report: $markdownPath"
}
Write-Host '============================================================' -ForegroundColor Cyan

if ($PassThru) {
    return [pscustomobject]$result
}
if ($status -ne 'PASS') {
    exit 1
}
exit 0
