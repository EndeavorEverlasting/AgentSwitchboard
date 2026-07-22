[CmdletBinding()]
param(
    [string]$RootPath,
    [switch]$NoWrite,
    [string]$OutputDirectory
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
    'Install-TmuxNewInstanceShortcut.cmd',
    'tooling/profiles/windows/Install-TmuxNewInstanceShortcut.ps1',
    'tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1',
    'tooling/profiles/windows/tmux-new-instance-shortcut.example.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/codebase-map.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/shortcut-profile.registry.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/artifact-registry.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/composition.graph.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/schemas/tmux-new-instance-shortcut.schema.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/workflows/install-shortcut.workflow.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/workflows/launch-new-instance.workflow.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/workflows/handle-failure.workflow.json',
    '.ai/skills/tmux-new-instance-shortcut/SKILL.md',
    'scripts/Test-TmuxNewInstanceShortcutHarness.ps1',
    'tests/test_tmux_new_instance_shortcut_harness.py',
    'tooling/profiles/windows/hooks/Invoke-TmuxNewInstanceShortcutPreCommit.ps1',
    'docs/harness/tmux-new-instance-shortcut.md',
    '.github/workflows/tmux-new-instance-shortcut-harness.yml'
)

$components = @()
foreach ($relativePath in $required) {
    $components += [pscustomobject]@{
        path = $relativePath
        exists = Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf
    }
}
$missing = @($components | Where-Object { -not $_.exists })
$branch = [string](& git -C $RootPath branch --show-current 2>$null)
$head = [string](& git -C $RootPath rev-parse HEAD 2>$null)
$status = if ($missing.Count -eq 0) { 'repository-ready' } else { 'incomplete' }

$working = @(
    'The root CMD defaults to Apply and delegates to one PowerShell installer.',
    'The installed shortcut delegates to the canonical AgentSwitchboard Windows Profile launcher.',
    'new-instance allocation reserves dev and selects dev-1, dev-2, and later unused positive suffixes.',
    'The launch command requires wezterm start --always-new-process, a unique workspace, and a unique window class.',
    'The installer preserves foreign shortcuts and does not launch runtime during installation.',
    'Generated plans, receipts, results, reports, and handoffs remain local-operational and untracked.'
)
$gaps = @(
    'Repository and CI checks do not prove the desktop shortcut is installed on the operator workstation.',
    'A live double-click must still prove one visible WezTerm window attached to the allocated tmux session.',
    'Repeat clicks, styling/layout, rollback, and operator acceptance remain end-to-end runtime proof.',
    'Window activation or focus change for open-or-activate remains runtime proof.'
)

$result = [ordered]@{
    schema = 'agentswitchboard.tmux-new-instance-shortcut-status.v1'
    status = $status
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    branch = $branch
    head = $head
    components = $components
    missing = @($missing | ForEach-Object { $_.path })
    working = $working
    gaps = $gaps
    proofCeiling = 'Repository structure and contract readiness only; no live shortcut, tmux, WSL, or WezTerm behavior.'
    nextCommand = 'pwsh -NoLogo -NoProfile -File scripts/Test-TmuxNewInstanceShortcutHarness.ps1'
}

Write-Host 'TMUX NEW-INSTANCE DESKTOP SHORTCUT HARNESS' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Branch: {0}" -f $branch)
Write-Host ("HEAD: {0}" -f $head)
Write-Host ("Components: {0}/{1} present" -f ($components.Count - $missing.Count), $components.Count)
Write-Host 'Working:'
$working | ForEach-Object { Write-Host ("- {0}" -f $_) }
Write-Host 'Missing runtime proof:'
$gaps | ForEach-Object { Write-Host ("- {0}" -f $_) }
Write-Host ("Next: {0}" -f $result.nextCommand)

if (-not $NoWrite) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/tmux-new-instance-shortcut/status'
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $jsonPath = Join-Path $OutputDirectory 'tmux-new-instance-shortcut-status.json'
    $mdPath = Join-Path $OutputDirectory 'tmux-new-instance-shortcut-status.md'
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    $lines = @(
        '# tmux New-Instance Desktop Shortcut Harness',
        '',
        ('- Status: `{0}`' -f $status),
        ('- Branch: `{0}`' -f $branch),
        ('- HEAD: `{0}`' -f $head),
        ('- Components: {0}/{1}' -f ($components.Count - $missing.Count), $components.Count),
        '',
        '## Working'
    )
    $lines += @($working | ForEach-Object { '- ' + $_ })
    $lines += @('', '## Missing runtime proof')
    $lines += @($gaps | ForEach-Object { '- ' + $_ })
    $lines += @('', '## Next command', '```powershell', $result.nextCommand, '```')
    $lines | Set-Content -LiteralPath $mdPath -Encoding utf8
}

if ($missing.Count -gt 0) { exit 1 }
exit 0
