[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$OutputRoot = '.local/gnhf-orchestration-validation'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..	..	..')).Path
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$OutputRoot = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { Join-Path $RepoRoot $OutputRoot }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$errors = New-Object 'System.Collections.Generic.List[string]'
$passes = 0

function Add-Check([bool]$Condition, [string]$Name, [string]$Message = 'contract failed') {
    if ($Condition) {
        $script:passes++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    else {
        $script:errors.Add("${Name}: $Message")
        Write-Host "[FAIL] $Name - $Message" -ForegroundColor Red
    }
}

function RepoPath([string]$Relative) { Join-Path $RepoRoot ($Relative -replace '/', [IO.Path]::DirectorySeparatorChar) }
function ReadJson([string]$Relative) { Get-Content -LiteralPath (RepoPath $Relative) -Raw | ConvertFrom-Json }

$required = @(
    'tooling/gnhf/schemas/prompt-queue.schema.json',
    'tooling/gnhf/schemas/queue-plan.schema.json',
    'tooling/gnhf/schemas/lane-result.schema.json',
    'tooling/gnhf/schemas/child-operation-request.schema.json',
    'tooling/gnhf/schemas/child-operation-result.schema.json',
    'tooling/gnhf/schemas/trigger-snapshot.schema.json',
    'tooling/gnhf/Compile-GnhfPromptQueue.ps1',
    'tooling/gnhf/Invoke-GnhfChildOperation.ps1',
    'tooling/gnhf/tests/validate_orchestration_contracts.py',
    'tooling/gnhf/tests/fixtures/example-prompt-queue.json',
    'tooling/gnhf/tests/fixtures/example-child-operation-request.json',
    'tooling/gnhf/tests/fixtures/example-trigger-snapshot.json',
    'docs/recovery/mainline-orchestration-value-map.md'
)
foreach ($item in $required) { Add-Check (Test-Path -LiteralPath (RepoPath $item) -PathType Leaf) "required/$item" }

foreach ($item in @('tooling/gnhf/Compile-GnhfPromptQueue.ps1', 'tooling/gnhf/Invoke-GnhfChildOperation.ps1')) {
    $path = RepoPath $item
    $bytes = [IO.File]::ReadAllBytes($path)
    Add-Check ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) "bom/$item" "PowerShell file must carry a UTF-8 BOM"
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    Add-Check ($parseErrors.Count -eq 0) "parse/$item" (($parseErrors | ForEach-Object Message) -join '; ')
}

$schemaConsts = @{
    'tooling/gnhf/schemas/prompt-queue.schema.json' = 'agentswitchboard.gnhf.prompt-queue.v1'
    'tooling/gnhf/schemas/queue-plan.schema.json' = 'agentswitchboard.gnhf.queue-plan.v1'
    'tooling/gnhf/schemas/lane-result.schema.json' = 'agentswitchboard.gnhf.lane-result.v1'
    'tooling/gnhf/schemas/child-operation-request.schema.json' = 'agentswitchboard.gnhf.child-operation-request.v1'
    'tooling/gnhf/schemas/child-operation-result.schema.json' = 'agentswitchboard.gnhf.child-operation-result.v1'
    'tooling/gnhf/schemas/trigger-snapshot.schema.json' = 'agentswitchboard.gnhf.trigger-snapshot.v1'
}
foreach ($kv in $schemaConsts.GetEnumerator()) {
    $schema = ReadJson $kv.Key
    Add-Check ($schema.properties.schema.const -eq $kv.Value) "schema/const/$($kv.Key)" "expected $($kv.Value)"
}

$fixtureConsts = @{
    'tooling/gnhf/tests/fixtures/example-prompt-queue.json' = 'agentswitchboard.gnhf.prompt-queue.v1'
    'tooling/gnhf/tests/fixtures/example-child-operation-request.json' = 'agentswitchboard.gnhf.child-operation-request.v1'
    'tooling/gnhf/tests/fixtures/example-trigger-snapshot.json' = 'agentswitchboard.gnhf.trigger-snapshot.v1'
}
foreach ($kv in $fixtureConsts.GetEnumerator()) {
    $fixture = ReadJson $kv.Key
    Add-Check ($fixture.schema -eq $kv.Value) "fixture/const/$($kv.Key)" "expected $($kv.Value)"
}

$queue = ReadJson 'tooling/gnhf/tests/fixtures/example-prompt-queue.json'
$laneIds = @($queue.lanes | ForEach-Object { [string]$_.id })
Add-Check (($laneIds | Select-Object -Unique).Count -eq $laneIds.Count) 'fixture/queue/lane-ids-unique'
$deps = @($queue.lanes | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'dependsOn') { $_.dependsOn } })
foreach ($dep in $deps) { Add-Check ($laneIds -contains [string]$dep) "fixture/queue/dependency/$dep" }

$request = ReadJson 'tooling/gnhf/tests/fixtures/example-child-operation-request.json'
Add-Check ($request.authorityBoundary -in @('repository-intake', 'static-validation', 'child-validator', 'child-build', 'read-only-runtime', 'none')) 'fixture/request/authority-boundary'
Add-Check ($request.consumerId -in @('agent-switchboard', 'sysadminsuite', 'continuum', 'web-excel-repair-triage')) 'fixture/request/consumer-id'

$status = if ($errors.Count) { 'FAIL' } else { 'PASS' }
[ordered]@{
    schema = 'agentswitchboard.gnhf.orchestration-validation.v1'
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    status = $status
    passes = $passes
    errors = @($errors)
} | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $OutputRoot 'validation-result.json') -Encoding UTF8

Write-Host "Result: $passes passed / $($errors.Count) failed"
if ($errors.Count) { throw ($errors -join [Environment]::NewLine) }
