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
    'tooling/agents/harness/admission/codebase-map.json',
    'tooling/agents/harness/admission/agent-admission.registry.json',
    'tooling/agents/harness/admission/artifact-registry.json',
    'tooling/agents/harness/admission/workflows/task-intake.workflow.json',
    'tooling/agents/harness/admission/workflows/admission-evaluation.workflow.json',
    'tooling/agents/harness/admission/workflows/route-selection.workflow.json',
    'tooling/agents/harness/admission/workflows/failure-handoff.workflow.json',
    'tooling/agents/harness/admission/schemas/agent-admission-harness.schema.json',
    'tooling/agents/harness/admission/fixtures/runtime-proof-discipline.cases.json',
    '.ai/skills/agent-admission-routing/SKILL.md',
    'scripts/Test-AgentAdmissionHarness.ps1',
    'tests/test_agent_admission_harness.py',
    'tooling/agents/hooks/Invoke-AgentAdmissionHarnessPreCommit.ps1',
    'docs/harness/agent-admission-harness.md',
    '.github/workflows/agent-admission-harness.yml'
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
$missing = @($componentResults | Where-Object { -not $_.exists -or -not $_.tracked })

$working = @(
    'Unknown agents fail closed to static/build-safe work until stronger admission evidence exists.',
    'The runtime-proof-discipline suite distinguishes live pass, not attempted, launcher blocked, acknowledgement only, and stale evidence.',
    'Live-runtime routing requires a fresh exact agent/provider/model/endpoint admission pass.',
    'Generated admission, routing, proof-ledger, report, and handoff evidence is local-operational and untracked.',
    'The opt-in hook and cross-platform CI validate the harness without installing hooks or invoking providers.'
)

$broken = @()
if ($missing.Count -gt 0) { $broken += "$($missing.Count) required tracked component(s) are missing or untracked." }
if ($dirty) { $broken += 'The checkout is dirty; a write lane must preserve or isolate unrelated work.' }

$gaps = @(
    'AgentSwitchboard product runtime is not yet wired to enforce this admission gate before every delegated agent execution.',
    'No provider or model has been runtime-admitted by this repository-only harness build.',
    'Synthetic admission fixtures prove classification discipline only; they do not prove model quality on arbitrary tasks.',
    'Live-runtime success still belongs to the owning runtime harness and end-to-end evidence chain.'
)

$status = if ($missing.Count -eq 0) { 'contract-ready-runtime-enforcement-unwired' } else { 'incomplete' }
$nextCommand = 'pwsh -NoLogo -NoProfile -File scripts/Test-AgentAdmissionHarness.ps1'
$result = [ordered]@{
    schema = 'agentswitchboard.agent-admission-harness-status.v1'
    status = $status
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    root = $RootPath
    branch = [string]$branch
    head = [string]$head
    dirty = $dirty
    components = $componentResults
    working = $working
    broken = $broken
    missing = @($missing | ForEach-Object { $_.path })
    gaps = $gaps
    proofCeiling = 'Read-only repository contract status only; no provider call, admission execution, runtime enforcement, or live target proof.'
    nextCommand = $nextCommand
}

$readyCount = @($componentResults | Where-Object { $_.exists -and $_.tracked }).Count
Write-Host 'AGENT ADMISSION HARNESS' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $result.status)
Write-Host ("Branch: {0}" -f $result.branch)
Write-Host ("HEAD: {0}" -f $result.head)
Write-Host ("Components: {0}/{1} ready" -f $readyCount, $componentResults.Count)
Write-Host ''
Write-Host 'Working:'
$working | ForEach-Object { Write-Host "- $_" }
Write-Host 'Broken or blocked:'
if ($broken.Count -eq 0) { Write-Host '- None at repository-contract level.' } else { $broken | ForEach-Object { Write-Host "- $_" } }
Write-Host 'Missing runtime proof or wiring:'
$gaps | ForEach-Object { Write-Host "- $_" }
Write-Host "Next: $nextCommand"

if (-not $NoWrite) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/AgentAdmission/status'
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $jsonPath = Join-Path $OutputDirectory 'agent-admission-harness-status.json'
    $mdPath = Join-Path $OutputDirectory 'agent-admission-harness-status.md'
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8

    $markdown = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @(
        '# Agent Admission Harness Status',
        '',
        ("- Status: {0}" -f $result.status),
        ("- Branch: {0}" -f $result.branch),
        ("- HEAD: {0}" -f $result.head),
        ("- Ready components: {0}/{1}" -f $readyCount, $componentResults.Count),
        '',
        '## Working'
    )) { [void]$markdown.Add($line) }
    foreach ($line in $working) { [void]$markdown.Add("- $line") }
    [void]$markdown.Add('')
    [void]$markdown.Add('## Broken or blocked')
    if ($broken.Count -eq 0) { [void]$markdown.Add('- None at repository-contract level.') }
    else { foreach ($line in $broken) { [void]$markdown.Add("- $line") } }
    [void]$markdown.Add('')
    [void]$markdown.Add('## Missing runtime proof or wiring')
    foreach ($line in $gaps) { [void]$markdown.Add("- $line") }
    foreach ($line in @('', '## Proof ceiling', $result.proofCeiling, '', '## Next command', '```powershell', $nextCommand, '```')) {
        [void]$markdown.Add($line)
    }
    $markdown | Set-Content -LiteralPath $mdPath -Encoding utf8
    Write-Host "JSON: $jsonPath"
    Write-Host "Report: $mdPath"
}

if ($missing.Count -gt 0) { exit 1 }
exit 0
