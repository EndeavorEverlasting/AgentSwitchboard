[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputDirectory,
    [switch]$NoWrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$required = @(
    'tooling/pi/harness/codebase-map.json',
    'tooling/pi/harness/pi-adapter.registry.json',
    'tooling/pi/harness/artifact-registry.json',
    'tooling/pi/harness/workflows/task-intake.workflow.json',
    'tooling/pi/harness/workflows/opinion-fusion.workflow.json',
    'tooling/pi/harness/workflows/autovalidate.workflow.json',
    'tooling/pi/harness/schemas/pi-harness-contracts.schema.json',
    '.ai/skills/pi-fusion-orchestration/SKILL.md',
    'scripts/Test-PiHarnessCompleteness.ps1',
    'tests/test_pi_harness_contracts.py',
    'tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1',
    'docs/harness/pi-operational-harness.md'
)

$componentResults = foreach ($relativePath in $required) {
    $path = Join-Path $RootPath $relativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $tracked = $false
    if ($exists) {
        $null = & git -C $RootPath ls-files --error-unmatch -- $relativePath 2>$null
        $tracked = $LASTEXITCODE -eq 0
    }
    [ordered]@{ path = $relativePath; exists = $exists; tracked = $tracked }
}

$branch = (& git -C $RootPath branch --show-current 2>$null | Select-Object -First 1)
$head = (& git -C $RootPath rev-parse HEAD 2>$null | Select-Object -First 1)
$dirty = [bool](& git -C $RootPath status --short 2>$null)
$piCommand = Get-Command pi -ErrorAction SilentlyContinue

$missing = @($componentResults | Where-Object { -not $_.exists -or -not $_.tracked })
$working = @(
    'Repository-native Pi maps, workflows, artifact contracts, schemas, skill, validator, hook, CI, and operator guide are declared.'
    'Workflow selection, opinion fusion, and autovalidation are bounded and require one designated writer.'
    'Generated Pi evidence is local-only and raw prompts or transcripts are forbidden from tracked artifacts.'
)
$broken = @()
if ($missing.Count -gt 0) { $broken += "$($missing.Count) required tracked component(s) are missing or untracked." }
if ($dirty) { $broken += 'The checkout is dirty; a write lane must preserve or isolate unrelated work.' }
$gaps = @(
    'Pi installation and exact version are not proven by this report.'
    'Extension API compatibility is not proven until a pinned upstream version is validated.'
    'Provider/model availability, privacy, telemetry, network behavior, and model response remain runtime proof.'
    'Fusion quality and autovalidation effectiveness require a separate authorized runtime lane.'
)

$status = if ($missing.Count -eq 0) { 'contract-ready' } else { 'incomplete' }
$piState = if ($null -eq $piCommand) { 'missing' } else { 'present-unverified' }
$nextCommand = 'pwsh -NoLogo -NoProfile -File scripts/Test-PiHarnessCompleteness.ps1'

$result = [ordered]@{
    schema = 'agentswitchboard.pi-harness-status.v1'
    status = $status
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    root = $RootPath
    branch = [string]$branch
    head = [string]$head
    dirty = $dirty
    pi = [ordered]@{ state = $piState; path = if ($piCommand) { $piCommand.Source } else { $null } }
    components = $componentResults
    working = $working
    broken = $broken
    missing = @($missing | ForEach-Object { $_.path })
    gaps = $gaps
    proofCeiling = 'Read-only repository contract and command-presence status only; no Pi or provider runtime proof.'
    nextCommand = $nextCommand
}

Write-Host 'PI OPERATIONAL HARNESS' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $result.status)
Write-Host ("Branch: {0}" -f $result.branch)
Write-Host ("HEAD: {0}" -f $result.head)
Write-Host ("Pi: {0}" -f $result.pi.state)
Write-Host ("Components: {0}/{1} ready" -f (@($componentResults | Where-Object { $_.exists -and $_.tracked }).Count), $componentResults.Count)
Write-Host ''
Write-Host 'Working:'
$working | ForEach-Object { Write-Host "- $_" }
Write-Host 'Broken or blocked:'
if ($broken.Count -eq 0) { Write-Host '- None at repository-contract level.' } else { $broken | ForEach-Object { Write-Host "- $_" } }
Write-Host 'Missing runtime proof:'
$gaps | ForEach-Object { Write-Host "- $_" }
Write-Host "Next: $nextCommand"

if (-not $NoWrite) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/PiHarness/status'
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $jsonPath = Join-Path $OutputDirectory 'pi-harness-status.json'
    $mdPath = Join-Path $OutputDirectory 'pi-harness-status.md'
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    @(
        '# Pi Operational Harness Status',
        '',
        "- Status: `$($result.status)`",
        "- Branch: `$($result.branch)`",
        "- HEAD: `$($result.head)`",
        "- Pi: `$($result.pi.state)`",
        "- Ready components: $(@($componentResults | Where-Object { $_.exists -and $_.tracked }).Count)/$($componentResults.Count)",
        '',
        '## Working',
        ($working | ForEach-Object { "- $_" }),
        '',
        '## Broken or blocked',
        $(if ($broken.Count -eq 0) { '- None at repository-contract level.' } else { $broken | ForEach-Object { "- $_" } }),
        '',
        '## Missing runtime proof',
        ($gaps | ForEach-Object { "- $_" }),
        '',
        '## Proof ceiling',
        $result.proofCeiling,
        '',
        '## Next command',
        '```powershell',
        $nextCommand,
        '```'
    ) | Set-Content -LiteralPath $mdPath -Encoding utf8
    Write-Host "JSON: $jsonPath"
    Write-Host "Report: $mdPath"
}

if ($missing.Count -gt 0) { exit 1 }
exit 0
