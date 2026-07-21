[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))),
    [string]$OutputDirectory,
    [switch]$NoWrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$required = @(
    'tooling/profiles/windows/harness/launch-modes/codebase-map.json',
    'tooling/profiles/windows/harness/launch-modes/launch-mode.registry.json',
    'tooling/profiles/windows/harness/launch-modes/artifact-registry.json',
    'tooling/profiles/windows/harness/launch-modes/composition.graph.json',
    'tooling/profiles/windows/harness/launch-modes/workflows/launch-request-intake.workflow.json',
    'tooling/profiles/windows/harness/launch-modes/workflows/open-or-activate-verification.workflow.json',
    'tooling/profiles/windows/harness/launch-modes/workflows/new-instance-verification.workflow.json',
    'tooling/profiles/windows/harness/launch-modes/workflows/duplicate-window-diagnosis.workflow.json',
    'tooling/profiles/windows/harness/launch-modes/schemas/windows-launch-mode-harness.schema.json',
    '.ai/skills/windows-profile-launch-mode-validation/SKILL.md',
    'scripts/Test-WindowsProfileLaunchModeHarness.ps1',
    'tests/test_windows_profile_launch_mode_harness.py',
    'tooling/profiles/windows/hooks/Invoke-WindowsProfileLaunchModePreCommit.ps1',
    'docs/harness/windows-profile-launch-mode-harness.md'
)

$components = foreach ($relativePath in $required) {
    $path = Join-Path $RootPath $relativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $tracked = $false
    if ($exists) {
        $null = & git -C $RootPath ls-files --error-unmatch -- $relativePath 2>$null
        $tracked = $LASTEXITCODE -eq 0
    }
    [pscustomobject]@{ path = $relativePath; exists = $exists; tracked = $tracked }
}

$missing = @($components | Where-Object { -not $_.exists -or -not $_.tracked })
$branch = [string]((& git -C $RootPath branch --show-current 2>$null | Select-Object -First 1))
$head = [string]((& git -C $RootPath rev-parse HEAD 2>$null | Select-Object -First 1))
$dirty = [bool](& git -C $RootPath status --short 2>$null)
$implementationPath = Join-Path $RootPath 'tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1'
$implementationPresent = Test-Path -LiteralPath $implementationPath -PathType Leaf

$working = @(
    'Default open-or-activate and explicit new-instance modes are declared under one canonical AgentSwitchboard launcher.',
    'One request may create at most one top-level window, and repeated identity must converge.',
    'Explicit new-instance mode requires a named instance, a separate frontend process, and a unique tmux session.',
    'Synthetic fixtures cover activation, one intentional new instance, and an accidental duplicate burst.',
    'A dedicated composition graph connects requests, triggers, the skill, workflows, validation, artifacts, and handoff.',
    'Generated launch evidence is local-operational and untracked.'
)

$broken = [System.Collections.Generic.List[string]]::new()
if ($missing.Count -gt 0) {
    [void]$broken.Add("$($missing.Count) required harness component(s) are missing or untracked.")
}
if ($dirty) {
    [void]$broken.Add('The checkout is dirty; preserve or isolate unrelated work before writing.')
}

$gaps = @(
    'The canonical Windows Profile launcher implementation is not proven by this status report.',
    'The current workstation duplicate-window cause is not proven until the exact operator command is observed with correlated before/after state.',
    'Window activation, distinct WezTerm process creation, unique tmux session creation, and visual acceptance remain runtime proof.',
    'SysAdminSuite consumer certification remains a separate child-repository sprint.'
)
if (-not $implementationPresent) {
    $gaps = @('The canonical Windows Profile launcher source path is not present on this branch.') + $gaps
}

$result = [ordered]@{
    schema = 'agentswitchboard.windows-profile-launch-mode-status.v1'
    status = if ($missing.Count -eq 0) { 'contract-ready' } else { 'incomplete' }
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    branch = $branch
    head = $head
    dirty = $dirty
    components = $components
    implementation = [ordered]@{
        path = 'tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1'
        present = $implementationPresent
        proven = $false
    }
    working = $working
    broken = @($broken)
    gaps = $gaps
    proofCeiling = 'Tracked launch-mode harness structure and offline contract readiness only; no WezTerm, window, process, tmux, launcher, or workstation runtime proof.'
    nextCommand = 'pwsh -NoLogo -NoProfile -File scripts/Test-WindowsProfileLaunchModeHarness.ps1'
}

Write-Host 'WINDOWS PROFILE LAUNCH MODE HARNESS' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $result.status)
Write-Host ("Branch: {0}" -f $result.branch)
Write-Host ("HEAD: {0}" -f $result.head)
Write-Host ("Components: {0}/{1} ready" -f (@($components | Where-Object { $_.exists -and $_.tracked }).Count), $components.Count)
Write-Host ("Canonical launcher source present: {0}" -f $implementationPresent)
Write-Host ''
Write-Host 'Working:'
$working | ForEach-Object { Write-Host "- $_" }
Write-Host 'Broken or blocked:'
if ($broken.Count -eq 0) { Write-Host '- None at repository-contract level.' }
else { $broken | ForEach-Object { Write-Host "- $_" } }
Write-Host 'Missing runtime proof:'
$gaps | ForEach-Object { Write-Host "- $_" }
Write-Host ("Next: {0}" -f $result.nextCommand)

if (-not $NoWrite) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/WindowsProfileLaunchModes/status'
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $jsonPath = Join-Path $OutputDirectory 'windows-launch-mode-status.json'
    $mdPath = Join-Path $OutputDirectory 'windows-launch-mode-status.md'
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    @(
        '# Windows Profile Launch Mode Harness Status',
        '',
        "- Status: `$($result.status)`",
        "- Branch: `$($result.branch)`",
        "- HEAD: `$($result.head)`",
        "- Components: $(@($components | Where-Object { $_.exists -and $_.tracked }).Count)/$($components.Count)",
        "- Canonical launcher source present: `$implementationPresent`",
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
        $result.nextCommand,
        '```'
    ) | Set-Content -LiteralPath $mdPath -Encoding utf8
    Write-Host "JSON: $jsonPath"
    Write-Host "Report: $mdPath"
}

if ($missing.Count -gt 0) { exit 1 }
exit 0
