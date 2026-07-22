[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$requiredFiles = @(
    'Open-AgentSwitchboard-Continue.cmd',
    'Open-AgentSwitchboard-New.cmd',
    'Install-AgentSwitchboard-Tmux-Launchers.cmd',
    'tooling/profiles/windows/Invoke-AgentSwitchboardTmuxLaunch.ps1',
    'tooling/profiles/windows/Install-AgentSwitchboardTmuxLaunchers.ps1',
    'tooling/profiles/windows/windows-tmux-launch.json',
    'tooling/profiles/windows/Test-AgentSwitchboardTmuxLaunchers.ps1',
    '.ai/harness/workflows/windows-tmux-launch.workflow.json',
    '.ai/harness/artifacts/windows-tmux-launch.artifact-registry.json',
    '.ai/skills/windows-tmux-launch/SKILL.md',
    'docs/workstation/windows-tmux-launch.md'
)

$passed = 0
$failed = 0

function Assert-Contract {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Name,
        [string]$Evidence = ''
    )

    if ($Condition) {
        $script:passed++
        Write-Host "[PASS] $Name"
    }
    else {
        $script:failed++
        Write-Host "[FAIL] $Name $Evidence" -ForegroundColor Red
    }
}

foreach ($relativePath in $requiredFiles) {
    Assert-Contract -Condition (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf) -Name "required-file/$relativePath"
}

foreach ($relativePath in @(
    'tooling/profiles/windows/Invoke-AgentSwitchboardTmuxLaunch.ps1',
    'tooling/profiles/windows/Install-AgentSwitchboardTmuxLaunchers.ps1',
    'tooling/profiles/windows/Test-AgentSwitchboardTmuxLaunchers.ps1'
)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relativePath), [ref]$tokens, [ref]$errors)
    Assert-Contract -Condition ($errors.Count -eq 0) -Name "powershell-parse/$relativePath" -Evidence (($errors | ForEach-Object Message) -join '; ')
}

$manifestPath = Join-Path $root 'tooling/profiles/windows/windows-tmux-launch.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Assert-Contract -Condition ($manifest.schema -eq 'agentswitchboard.windows-tmux-launch.v1') -Name 'manifest/schema'
Assert-Contract -Condition ($manifest.continueSession -eq 'dev') -Name 'manifest/continue-session'
Assert-Contract -Condition ($manifest.newSessionPrefix -eq 'dev') -Name 'manifest/new-prefix'
Assert-Contract -Condition ($manifest.desktopLaunchers.continue -ne $manifest.desktopLaunchers.new) -Name 'manifest/distinct-launcher-names'
Assert-Contract -Condition ([string]$manifest.contracts.continue -match 'Never allocate a numbered session') -Name 'manifest/continue-no-numbered-session'
Assert-Contract -Condition ([string]$manifest.contracts.new -match 'Never attach to dev or an existing dev-N session') -Name 'manifest/new-no-existing-attach'

$launcherPath = Join-Path $root 'tooling/profiles/windows/Invoke-AgentSwitchboardTmuxLaunch.ps1'
$launcherContent = Get-Content -LiteralPath $launcherPath -Raw
Assert-Contract -Condition (-not $launcherContent.Contains(".Replace([char]0, '')")) -Name 'runtime/no-char-empty-replace'
Assert-Contract -Condition ($launcherContent.Contains('.Replace([string][char]0, [string]::Empty)')) -Name 'runtime/string-null-removal'
$nulSample = "before$([char]0)after".Replace([string][char]0, [string]::Empty)
Assert-Contract -Condition ($nulSample -eq 'beforeafter') -Name 'runtime/null-removal-executes'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('AgentSwitchboardTmuxHarness-' + [guid]::NewGuid().ToString('N'))
try {
    $continueOutput = Join-Path $tempRoot 'continue'
    & $launcherPath -Mode continue -Operation Plan -ManifestPath $manifestPath -ExistingSessions @('dev', 'dev-1') -OutputDirectory $continueOutput | Out-Null
    $continuePlan = Get-Content -LiteralPath (Join-Path $continueOutput 'windows-tmux-launch-plan.json') -Raw | ConvertFrom-Json
    Assert-Contract -Condition ($continuePlan.sessionName -eq 'dev') -Name 'plan/continue-targets-dev'
    Assert-Contract -Condition (-not $continuePlan.requiresSessionCreation) -Name 'plan/continue-reuses-dev'
    Assert-Contract -Condition ($continuePlan.continueNeverAllocatesNumberedSession) -Name 'plan/continue-invariant'

    $newOutput = Join-Path $tempRoot 'new'
    & $launcherPath -Mode new -Operation Plan -ManifestPath $manifestPath -ExistingSessions @('dev', 'dev-1') -OutputDirectory $newOutput | Out-Null
    $newPlan = Get-Content -LiteralPath (Join-Path $newOutput 'windows-tmux-launch-plan.json') -Raw | ConvertFrom-Json
    Assert-Contract -Condition ($newPlan.sessionName -eq 'dev-2') -Name 'plan/new-allocates-first-unused'
    Assert-Contract -Condition ($newPlan.requiresSessionCreation) -Name 'plan/new-requires-creation'
    Assert-Contract -Condition ($newPlan.newNeverAttachesExistingSession) -Name 'plan/new-invariant'
    Assert-Contract -Condition (@($newPlan.wezTermArguments) -contains '--always-new-process') -Name 'plan/new-separate-wezterm-process'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$continueCmd = Get-Content -LiteralPath (Join-Path $root 'Open-AgentSwitchboard-Continue.cmd') -Raw
$newCmd = Get-Content -LiteralPath (Join-Path $root 'Open-AgentSwitchboard-New.cmd') -Raw
Assert-Contract -Condition ($continueCmd -match '-Mode continue' -and $continueCmd -notmatch '-Mode new') -Name 'cmd/continue-mode-only'
Assert-Contract -Condition ($newCmd -match '-Mode new' -and $newCmd -notmatch '-Mode continue') -Name 'cmd/new-mode-only'
Assert-Contract -Condition ($continueCmd -match '%~dp0') -Name 'cmd/continue-repo-relative'
Assert-Contract -Condition ($newCmd -match '%~dp0') -Name 'cmd/new-repo-relative'

Write-Host "`nResult: $passed passed / $failed failed"
if ($failed -gt 0) { exit 1 }
