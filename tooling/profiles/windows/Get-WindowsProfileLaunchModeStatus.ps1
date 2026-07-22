[CmdletBinding()]
param(
    [string]$RootPath,
    [string]$OutputDirectory,
    [switch]$NoWrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [string](& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($RootPath)) {
        throw 'Unable to resolve the AgentSwitchboard repository root.'
    }
}
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

$components = @()
foreach ($relativePath in $required) {
    $exists = Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf
    $components += [pscustomobject]@{
        path = $relativePath
        exists = $exists
    }
}
$missing = @($components | Where-Object { -not $_.exists })

$branch = [string](& git -C $RootPath branch --show-current 2>$null)
$head = [string](& git -C $RootPath rev-parse HEAD 2>$null)
$implementationRelativePath = 'tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1'
$implementationPresent = Test-Path -LiteralPath (Join-Path $RootPath $implementationRelativePath) -PathType Leaf
$status = if ($missing.Count -eq 0) { 'contract-ready' } else { 'incomplete' }

$working = @(
    'Default open-or-activate and explicit new-instance modes are declared under one canonical AgentSwitchboard launcher.',
    'One request may create at most one top-level window, and repeated identity must converge.',
    'Explicit new-instance mode requires a named instance, a separate frontend process, and a unique tmux session.',
    'Synthetic fixtures cover activation, one intentional new instance, and an accidental duplicate burst.',
    'A dedicated composition graph connects requests, triggers, the skill, workflows, validation, artifacts, and handoff.',
    'Generated launch evidence is local-operational and untracked.'
)

$gaps = @(
    'The canonical Windows Profile launcher implementation is not proven by this report.',
    'The current workstation duplicate-window cause still requires correlated before and after runtime evidence.',
    'Window activation, distinct WezTerm process creation, unique tmux session creation, and visual acceptance remain runtime proof.',
    'SysAdminSuite consumer certification remains a separate child-repository sprint.'
)
if (-not $implementationPresent) {
    $gaps = @('The canonical Windows Profile launcher source path is not present on this branch.') + $gaps
}

$result = [ordered]@{
    schema = 'agentswitchboard.windows-profile-launch-mode-status.v1'
    status = $status
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    branch = $branch
    head = $head
    components = $components
    missing = @($missing | ForEach-Object { $_.path })
    implementationPath = $implementationRelativePath
    implementationPresent = $implementationPresent
    working = $working
    gaps = $gaps
    proofCeiling = 'Tracked launch-mode harness readiness only; no WezTerm, window, process, tmux, launcher, or workstation runtime proof.'
    nextCommand = 'pwsh -NoLogo -NoProfile -File scripts/Test-WindowsProfileLaunchModeHarness.ps1'
}

Write-Host 'WINDOWS PROFILE LAUNCH MODE HARNESS' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Branch: {0}" -f $branch)
Write-Host ("HEAD: {0}" -f $head)
Write-Host ("Components: {0}/{1} present" -f ($components.Count - $missing.Count), $components.Count)
Write-Host ("Canonical launcher source present: {0}" -f $implementationPresent)
Write-Host ''
Write-Host 'Working:'
$working | ForEach-Object { Write-Host ("- {0}" -f $_) }
Write-Host 'Missing or blocked:'
if ($missing.Count -eq 0) {
    Write-Host '- No missing harness components.'
}
else {
    $missing | ForEach-Object { Write-Host ("- Missing: {0}" -f $_.path) }
}
Write-Host 'Missing runtime proof:'
$gaps | ForEach-Object { Write-Host ("- {0}" -f $_) }
Write-Host ("Next: {0}" -f $result.nextCommand)

if (-not $NoWrite) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/WindowsProfileLaunchModes/status'
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $jsonPath = Join-Path $OutputDirectory 'windows-launch-mode-status.json'
    $mdPath = Join-Path $OutputDirectory 'windows-launch-mode-status.md'
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8

    $lines = @(
        '# Windows Profile Launch Mode Harness Status',
        '',
        ('- Status: `{0}`' -f $status),
        ('- Branch: `{0}`' -f $branch),
        ('- HEAD: `{0}`' -f $head),
        ('- Components: {0}/{1}' -f ($components.Count - $missing.Count), $components.Count),
        ('- Canonical launcher source present: `{0}`' -f $implementationPresent),
        '',
        '## Working'
    )
    $lines += @($working | ForEach-Object { '- ' + $_ })
    $lines += @('', '## Missing or blocked')
    if ($missing.Count -eq 0) {
        $lines += '- No missing harness components.'
    }
    else {
        $lines += @($missing | ForEach-Object { '- Missing: ' + $_.path })
    }
    $lines += @('', '## Missing runtime proof')
    $lines += @($gaps | ForEach-Object { '- ' + $_ })
    $lines += @(
        '',
        '## Proof ceiling',
        $result.proofCeiling,
        '',
        '## Next command',
        '```powershell',
        $result.nextCommand,
        '```'
    )
    $lines | Set-Content -LiteralPath $mdPath -Encoding utf8
    Write-Host ("JSON: {0}" -f $jsonPath)
    Write-Host ("Report: {0}" -f $mdPath)
}

if ($missing.Count -gt 0) { exit 1 }
exit 0
