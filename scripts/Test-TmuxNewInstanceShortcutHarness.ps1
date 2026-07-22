[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check {
    param([bool]$Condition, [string]$Name, [string]$Message = '')
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $Message") }
}

function Read-Tracked {
    param([string]$RelativePath)
    $path = Join-Path $RootPath $RelativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    Check $exists "file/$RelativePath" 'required file is missing'
    if (-not $exists) { return $null }
    $null = & git -C $RootPath ls-files --error-unmatch -- $RelativePath 2>$null
    Check ($LASTEXITCODE -eq 0) "tracked/$RelativePath" 'required file is not tracked'
    return Get-Content -LiteralPath $path -Raw
}

function Invoke-ChildPwsh {
    param([string[]]$Arguments, [int]$TimeoutSeconds = 30)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    foreach ($argument in @('-NoLogo', '-NoProfile') + $Arguments) {
        [void]$psi.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill($true) } catch {}
        throw 'Child PowerShell validation timed out.'
    }
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        Stderr = $stderrTask.GetAwaiter().GetResult().Trim()
    }
}

function Quote-PowerShellLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

$requiredFiles = @(
    'Install-TmuxNewInstanceShortcut.cmd',
    'tooling/profiles/windows/Install-TmuxNewInstanceShortcut.ps1',
    'tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1',
    'tooling/profiles/windows/tmux-new-instance-shortcut.example.json',
    'tooling/profiles/windows/Get-TmuxNewInstanceShortcutStatus.ps1',
    'tooling/profiles/windows/hooks/Invoke-TmuxNewInstanceShortcutPreCommit.ps1',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/codebase-map.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/shortcut-profile.registry.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/artifact-registry.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/composition.graph.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/schemas/tmux-new-instance-shortcut.schema.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/workflows/install-shortcut.workflow.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/workflows/launch-new-instance.workflow.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/workflows/handle-failure.workflow.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/fixtures/valid-empty-session-inventory.fixture.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/fixtures/valid-existing-sessions.fixture.json',
    'tooling/profiles/windows/harness/tmux-new-instance-shortcut/fixtures/invalid-existing-explicit-instance.fixture.json',
    '.ai/skills/tmux-new-instance-shortcut/SKILL.md',
    'tests/test_tmux_new_instance_shortcut_harness.py',
    'docs/harness/tmux-new-instance-shortcut.md',
    '.github/workflows/tmux-new-instance-shortcut-harness.yml',
    '.ai/harness/manifest.json',
    'CODEBASE_MAP.md',
    'SKILLS.md',
    'TRIGGERS.md'
)

$text = @{}
foreach ($relativePath in $requiredFiles) { $text[$relativePath] = Read-Tracked $relativePath }

foreach ($relativePath in @($requiredFiles | Where-Object { $_ -like '*.json' })) {
    try { $null = $text[$relativePath] | ConvertFrom-Json; Check $true "json/$relativePath" }
    catch { Check $false "json/$relativePath" $_.Exception.Message }
}

foreach ($relativePath in @(
    'tooling/profiles/windows/Install-TmuxNewInstanceShortcut.ps1',
    'tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1',
    'tooling/profiles/windows/Get-TmuxNewInstanceShortcutStatus.ps1',
    'tooling/profiles/windows/hooks/Invoke-TmuxNewInstanceShortcutPreCommit.ps1'
)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RootPath $relativePath), [ref]$tokens, [ref]$parseErrors)
    Check (@($parseErrors).Count -eq 0) "powershell/$relativePath" (@($parseErrors) -join '; ')
}

try {
    $manifest = $text['tooling/profiles/windows/tmux-new-instance-shortcut.example.json'] | ConvertFrom-Json
    Check ($manifest.runtimeMode -eq 'new-instance') 'manifest/mode'
    Check ($manifest.instanceId -eq 'auto') 'manifest/instance'
    Check ($manifest.sessionPrefix -eq 'dev') 'manifest/session-prefix'
    Check ($manifest.allocationPolicy -eq 'smallest-positive-integer') 'manifest/allocation'
    Check ($manifest.openOrActivateImplementation -eq 'implemented') 'manifest/open-block'
    Check ($manifest.generatedEvidenceTracked -eq $false) 'manifest/evidence'

    $registry = $text['tooling/profiles/windows/harness/tmux-new-instance-shortcut/shortcut-profile.registry.json'] | ConvertFrom-Json
    Check ($registry.status -eq 'tracked-unproven-runtime') 'registry/status'
    Check ($registry.shortcut.delegatesToCanonicalLauncher -eq $true) 'registry/delegation'
    Check ($registry.shortcut.foreignShortcutOverwriteAllowed -eq $false) 'registry/foreign-shortcut'
    Check ($registry.shortcut.installationLaunchesRuntime -eq $false) 'registry/install-runtime'
    Check ($registry.sessionAllocation.bareSessionReservedForDefaultMode -eq 'dev') 'registry/reserved-dev'
    Check ($registry.sessionAllocation.reuseExistingNamedInstanceAllowed -eq $false) 'registry/no-reuse'
    Check ($registry.sessionAllocation.mutexRequired -eq $true) 'registry/mutex'
    Check ($registry.wezterm.alwaysNewProcessRequired -eq $true) 'registry/wezterm-process'
    Check ($registry.tmux.sameSessionMultipleWindowsIsNewInstance -eq $false) 'registry/no-duplicate-view'

    $central = $text['.ai/harness/manifest.json'] | ConvertFrom-Json
    Check ($central.entrypoints.tmuxNewInstanceShortcutCommand -eq 'Install-TmuxNewInstanceShortcut.cmd') 'central/cmd'
    Check ($central.entrypoints.tmuxNewInstanceShortcutInstaller -eq 'tooling/profiles/windows/Install-TmuxNewInstanceShortcut.ps1') 'central/installer'
    Check ($central.entrypoints.windowsProfileCanonicalLauncher -eq 'tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1') 'central/launcher'
    Check ($central.tmuxNewInstanceShortcut.status -eq 'tracked-unproven-runtime') 'central/status'
    Check ($central.tmuxNewInstanceShortcut.defaultInstallerMode -eq 'Apply') 'central/apply-default'
    Check ($central.tmuxNewInstanceShortcut.generatedEvidenceTracked -eq $false) 'central/evidence'
}
catch { [void]$failures.Add("semantic/json: $($_.Exception.Message)") }

$cmd = $text['Install-TmuxNewInstanceShortcut.cmd']
foreach ($token in @('cd /d "%~dp0"', 'set "MODE=Apply"', 'Install-TmuxNewInstanceShortcut.ps1', 'pwsh.exe -NoLogo -NoProfile')) {
    Check ($cmd.Contains($token)) "cmd/$token"
}
Check (-not $cmd.ToLowerInvariant().Contains('wezterm.exe start')) 'cmd/no-wezterm'
Check (-not $cmd.ToLowerInvariant().Contains('tmux new-session')) 'cmd/no-tmux'

$installer = $text['tooling/profiles/windows/Install-TmuxNewInstanceShortcut.ps1']
foreach ($token in @('Invoke-AgentSwitchboardOpenOrActivate.ps1', 'New-Object -ComObject WScript.Shell', 'Existing foreign shortcut was preserved', '-Mode new-instance', '-InstanceId auto', 'runtimeExecuted = $false', 'launchesDuringInstall = $false')) {
    Check ($installer.Contains($token)) "installer/$token"
}
Check (-not $installer.Contains('Start-Process')) 'installer/no-runtime'
Check (-not $installer.Contains('tmux new-session')) 'installer/no-tmux'

$launcher = $text['tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1']
foreach ($token in @('--always-new-process', 'tmux new-session -d', 'tmux attach-session', 'Local\AgentSwitchboard.TmuxNewInstance', 'open-or-activate', 'visibleWindowObserved = $false', "proofLevel = 'command-ack'")) {
    Check ($launcher.Contains($token)) "launcher/$token"
}
Check (-not $launcher.Contains('tmux new-session -A')) 'launcher/no-new-A'
Check (-not $launcher.Contains('tmux new -A')) 'launcher/no-short-A'
Check (-not $launcher.Contains('C:\Users\')) 'launcher/no-user-path'
Check (-not $launcher.Contains('/home/cheex')) 'launcher/no-home-path'

$skill = $text['.ai/skills/tmux-new-instance-shortcut/SKILL.md']
foreach ($token in @('id: tmux-new-instance-shortcut', 'status: canonical', '## Trigger', '## Required inputs', '## Procedure', '## Expected outputs', '## Deterministic validation', '## Proof promotion', '## Forbidden scope', '## Stop and escalate')) {
    Check ($skill.Contains($token)) "skill/$token"
}
Check ($text['CODEBASE_MAP.md'].ToLowerInvariant().Contains('tmux new-instance desktop shortcut harness')) 'catalog/codebase-map'
Check ($text['SKILLS.md'].Contains('tmux-new-instance-shortcut')) 'catalog/skill'
Check ($text['TRIGGERS.md'].Contains('profile.tmux-new-instance-shortcut.install')) 'catalog/install-trigger'
Check ($text['TRIGGERS.md'].Contains('profile.tmux-new-instance-shortcut.double-click')) 'catalog/double-click-trigger'

if ($failures.Count -eq 0) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("asb-tmux-shortcut-contract-{0}" -f [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    try {
        $launcherPath = Join-Path $RootPath 'tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1'
        $manifestPath = Join-Path $RootPath 'tooling/profiles/windows/tmux-new-instance-shortcut.example.json'
        $firstOutput = Join-Path $tempRoot 'first'
        $first = Invoke-ChildPwsh @('-File', $launcherPath, '-Mode', 'new-instance', '-Operation', 'Plan', '-ManifestPath', $manifestPath, '-OutputDirectory', $firstOutput)
        Check ($first.ExitCode -eq 0) 'plan/first/exit' $first.Stderr
        $firstPlan = Get-Content -LiteralPath (Join-Path $firstOutput 'tmux-new-instance-launch-plan.json') -Raw | ConvertFrom-Json
        Check ($firstPlan.sessionName -eq 'dev-1') 'plan/first/session'
        Check (@($firstPlan.wezTermArguments) -contains '--always-new-process') 'plan/first/process'

        $nextOutput = Join-Path $tempRoot 'next'
        $command = '& {0} -Mode new-instance -Operation Plan -ManifestPath {1} -ExistingSessions @(''dev'',''dev-1'',''dev-3'') -OutputDirectory {2}' -f (Quote-PowerShellLiteral $launcherPath), (Quote-PowerShellLiteral $manifestPath), (Quote-PowerShellLiteral $nextOutput)
        $next = Invoke-ChildPwsh @('-Command', $command)
        Check ($next.ExitCode -eq 0) 'plan/next/exit' $next.Stderr
        $nextPlan = Get-Content -LiteralPath (Join-Path $nextOutput 'tmux-new-instance-launch-plan.json') -Raw | ConvertFrom-Json
        Check ($nextPlan.sessionName -eq 'dev-2') 'plan/next/session'
        Check ($nextPlan.workspace -eq 'agentswitchboard-tmux-dev-2') 'plan/next/workspace'

        $installerPath = Join-Path $RootPath 'tooling/profiles/windows/Install-TmuxNewInstanceShortcut.ps1'
        $installerOutput = Join-Path $tempRoot 'installer'
        $installRoot = Join-Path $tempRoot 'installed'
        $desktopRoot = Join-Path $tempRoot 'desktop'
        $installerPlan = Invoke-ChildPwsh @('-File', $installerPath, '-Mode', 'Plan', '-ManifestPath', $manifestPath, '-InstallRoot', $installRoot, '-DesktopDirectory', $desktopRoot, '-OutputDirectory', $installerOutput)
        Check ($installerPlan.ExitCode -eq 20) 'install-plan/exit' $installerPlan.Stderr
        $installPlan = Get-Content -LiteralPath (Join-Path $installerOutput 'tmux-new-instance-shortcut-install-plan.json') -Raw | ConvertFrom-Json
        Check ($installPlan.launchesDuringInstall -eq $false) 'install-plan/no-runtime'
        Check ($installPlan.shortcutArguments -like '*-Mode new-instance*') 'install-plan/mode'
        Check ($installPlan.shortcutArguments -like '*-InstanceId auto*') 'install-plan/identity'
        Check (-not (Test-Path -LiteralPath $installRoot)) 'install-plan/no-install-root'
        Check (-not (Test-Path -LiteralPath $desktopRoot)) 'install-plan/no-desktop'
    }
    catch { [void]$failures.Add("plan/contracts: $($_.Exception.Message)") }
    finally { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($failures.Count -eq 0) {
    & python (Join-Path $RootPath 'tests/test_tmux_new_instance_shortcut_harness.py')
    Check ($LASTEXITCODE -eq 0) 'python/contracts'
}

Write-Host 'TMUX NEW-INSTANCE SHORTCUT HARNESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
