[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$Message = ''
    )
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $Message") }
}

$failureFixture = 'tooling/profiles/windows/harness/live-certification/fixtures/technician-quickstart-2026-07-22-fail.fixture.json'
$doctrinePath = 'docs/governance/live-cert-failure-doctrine.md'
$requiredFiles = @(
    'tooling/profiles/windows/harness/live-certification/schemas/windows-profile-live-certification.schema.json',
    'tooling/profiles/windows/harness/live-certification/fixtures/valid-open-or-activate-pass.fixture.json',
    'tooling/profiles/windows/harness/live-certification/fixtures/valid-new-instance-pass.fixture.json',
    $failureFixture,
    '.ai/skills/windows-profile-live-certification/SKILL.md',
    $doctrinePath
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $RootPath $relativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    Check $exists "file/$RelativePath" 'required file is missing'
    if ($exists) {
        $null = & git -C $RootPath ls-files --error-unmatch -- $RelativePath 2>$null
        Check ($LASTEXITCODE -eq 0) "tracked/$RelativePath" 'required file is not tracked'
    }
}

$jsonPaths = @($requiredFiles | Where-Object { $_ -like '*.json' })
foreach ($relativePath in $jsonPaths) {
    $path = Join-Path $RootPath $relativePath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $null = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            Check $true "json/$relativePath" ''
        }
        catch {
            Check $false "json/$relativePath" $_.Exception.Message
        }
    }
}

try {
    $schema = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/windows/harness/live-certification/schemas/windows-profile-live-certification.schema.json') -Raw | ConvertFrom-Json
    Check ($schema.'$defs'.PSObject.Properties.Name -contains 'runContext') 'schema/run-context' 'runContext definition missing'
    Check ($schema.'$defs'.PSObject.Properties.Name -contains 'snapshot') 'schema/snapshot' 'snapshot definition missing'
    Check ($schema.'$defs'.PSObject.Properties.Name -contains 'certificationResult') 'schema/certification-result' 'certificationResult definition missing'
    Check ($schema.'$defs'.certificationResult.required -contains 'status') 'schema/result-status' 'status field missing'
    Check ($schema.'$defs'.certificationResult.required -contains 'proofLevel') 'schema/result-proof-level' 'proofLevel field missing'
    Check ($schema.'$defs'.certificationResult.required -contains 'proofCeiling') 'schema/result-proof-ceiling' 'proofCeiling field missing'
}
catch { [void]$failures.Add("schema/semantic: $($_.Exception.Message)") }

$fixturePaths = @(
    'tooling/profiles/windows/harness/live-certification/fixtures/valid-open-or-activate-pass.fixture.json',
    'tooling/profiles/windows/harness/live-certification/fixtures/valid-new-instance-pass.fixture.json',
    $failureFixture
)
foreach ($relativePath in $fixturePaths) {
    $path = Join-Path $RootPath $relativePath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            Check ($fixture.schema -eq 'agentswitchboard.windows-profile-live-certification-fixture.v1') "fixture/$relativePath/schema" 'unexpected fixture schema'
            Check ($null -ne $fixture.expectedValid) "fixture/$relativePath/expectedValid" 'expectedValid missing'
            Check ($null -ne $fixture.expectedOutcome) "fixture/$relativePath/expectedOutcome" 'expectedOutcome missing'
            Check ($null -ne $fixture.mode) "fixture/$relativePath/mode" 'mode missing'
            if ($relativePath -eq $failureFixture) {
                Check ($fixture.expectedOutcome -eq 'failed') 'fixture/failure/outcome' 'sanitized live-cert report must remain a failure'
                Check ($fixture.observedAt -eq '2026-07-22') 'fixture/failure/date' 'observed date drifted'
                $stageJson = $fixture.stageEvidence | ConvertTo-Json -Depth 8
                foreach ($token in @('opencode-installation', 'hermes-browser-handoff', 'agy-installation', 'wezterm-command-resolution', 'tmux-command-resolution')) {
                    Check ($stageJson.Contains($token)) "fixture/failure/$token" 'required observed stage missing'
                }
                Check ($fixture.proofLevel -eq 'behavior-observed-failure') 'fixture/failure/proof-level' 'failure proof level is dishonest'
            }
        }
        catch { [void]$failures.Add("fixture/$relativePath exception: $($_.Exception.Message)") }
    }
}

$skillPath = Join-Path $RootPath '.ai/skills/windows-profile-live-certification/SKILL.md'
if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
    $skill = Get-Content -LiteralPath $skillPath -Raw
    foreach ($token in @(
        'id: windows-profile-live-certification',
        'version: 1.1.0',
        '## Trigger',
        '## Inputs',
        '## Procedure',
        '## Outputs',
        '## Deterministic validation',
        '## Forbidden scope',
        '## Stop and escalate',
        'Observed live failure outranks static and CI success',
        'exact operator shell',
        'repo-owned shim',
        'browser handoff',
        'optional agents separately'
    )) {
        Check ($skill.Contains($token)) "skill/$token" 'required skill contract missing'
    }
}

$doctrinePathFull = Join-Path $RootPath $doctrinePath
if (Test-Path -LiteralPath $doctrinePathFull -PathType Leaf) {
    $doctrine = Get-Content -LiteralPath $doctrinePathFull -Raw
    foreach ($token in @(
        'Observed live failure outranks static, synthetic, and CI success',
        'Optional agent installation or browser authentication may not block',
        'repo-owned shim',
        'Ctrl+C',
        '/debug',
        'OpenCode installation: observed pass',
        'AGY installation: observed fail'
    )) {
        Check ($doctrine.Contains($token)) "doctrine/$token" 'required live-cert doctrine missing'
    }
}
else {
    Check $false 'doctrine/file' "required doctrine file is missing: $doctrinePath"
}

Write-Host 'WINDOWS PROFILE LIVE CERTIFICATION HARNESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) { exit 1 }
exit 0