[CmdletBinding()]
param(
    [ValidateSet('shell', 'agy', 'opencode', 'setup', 'hermes')]
    [string]$Mode = 'shell',

    [string]$RepoRoot,

    [string]$GitRef = 'main',

    [string]$Distribution = 'Ubuntu',

    [ValidateRange(30, 1800)]
    [int]$TimeoutSeconds = 300,

    [switch]$SurfaceOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT' -and -not $SurfaceOnly) {
    throw 'The technician AgentSwitchboard readiness engine must run on Windows.'
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve the readiness-engine directory. Supply -RepoRoot explicitly.'
    }
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path

$agentSwitchboardCmd = Join-Path $RepoRoot 'AgentSwitchboard.cmd'
$profileLauncher = Join-Path $RepoRoot 'tooling\profiles\windows\Invoke-AgentSwitchboardOpenOrActivate.ps1'
$profileManifest = Join-Path $RepoRoot 'tooling\profiles\windows\tmux-new-instance-shortcut.example.json'
$gnhfSetup = Join-Path $RepoRoot 'tooling\gnhf\Setup-AgentSwitchboard.ps1'
$startupReporter = Join-Path $RepoRoot 'tooling\gnhf\Get-AgentSwitchboardStartupReport.ps1'
$commandShimRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin'
$fleetRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\GnhfFleet'
$fleetStatePath = Join-Path $fleetRoot 'state.json'

foreach ($requiredPath in @($agentSwitchboardCmd, $profileLauncher, $profileManifest, $gnhfSetup, $startupReporter)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required AgentSwitchboard file is missing: $requiredPath"
    }
}

$startedAt = Get-Date
$runId = '{0}-{1}' -f $startedAt.ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\technician-ready\runs\$runId"
$null = New-Item -ItemType Directory -Path $runRoot -Force
$transcriptPath = Join-Path $runRoot 'technician-ready-transcript.txt'
$summaryPath = Join-Path $runRoot 'technician-ready-summary.json'
$startupEvidenceRoot = Join-Path $runRoot 'startup-readiness'
$launcherEvidenceRoot = Join-Path $runRoot 'launcher'
$probeOutputPath = Join-Path $runRoot 'fresh-shell-agent-switchboard.txt'

$steps = [System.Collections.Generic.List[object]]::new()
$summary = [ordered]@{
    schema = 'agentswitchboard.technician-ready-result.v1'
    runId = $runId
    startedAt = $startedAt.ToUniversalTime().ToString('o')
    completedAt = $null
    status = 'running'
    mode = $Mode
    repositoryRoot = $RepoRoot
    gitRef = $GitRef
    distribution = $Distribution
    evidenceRoot = $runRoot
    commandShimRoot = $commandShimRoot
    fleetRoot = $fleetRoot
    fleetStatePath = $fleetStatePath
    startupReadiness = $null
    commands = $null
    shortcuts = $null
    steps = $steps
    error = $null
    proofLevel = 'workstation-setup-command-and-local-fleet-readiness'
    proofCeiling = 'Proves local setup, fresh-shell command resolution, canonical GNHF fleet state, startup-readiness reporting, and launcher command acknowledgement. It does not prove provider authentication, quota, hosted model availability, hosted response, agent task quality, window focus, or operator acceptance.'
}

function Add-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [string]$Evidence = ''
    )

    [void]$steps.Add([pscustomobject]@{
        name = $Name
        status = $Status
        evidence = $Evidence
        recordedAt = (Get-Date).ToUniversalTime().ToString('o')
    })
}

function ConvertFrom-NativeText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ''
    }
    return ([string]$Value).Replace(([char]0).ToString(), [string]::Empty)
}

function Refresh-WindowsPath {
    $segments = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in @(
        $commandShimRoot,
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
        (Join-Path $env:LOCALAPPDATA 'agy\bin'),
        (Join-Path $env:LOCALAPPDATA 'hermes\bin'),
        (Join-Path $env:APPDATA 'npm')
    )) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        foreach ($entry in ($segment -split ';')) {
            $trimmed = $entry.Trim()
            if ($trimmed -and -not $segments.Contains($trimmed)) {
                [void]$segments.Add($trimmed)
            }
        }
    }
    $env:Path = $segments -join ';'
}

function Ensure-UserPathEntry {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = [IO.Path]::GetFullPath($Path)
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($current -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not ($entries | Where-Object { $_.TrimEnd('\') -ieq $resolved.TrimEnd('\') })) {
        [Environment]::SetEnvironmentVariable('Path', ((@($resolved) + $entries) -join ';'), 'User')
    }
    Refresh-WindowsPath
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$ProcessTimeoutSeconds = 60,
        [switch]$InjectNewLine
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $InjectNewLine.IsPresent
    $psi.CreateNoWindow = $true
    $psi.FileName = $FilePath
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if ($InjectNewLine) {
        $process.StandardInput.WriteLine()
        $process.StandardInput.Flush()
        $process.StandardInput.Close()
    }

    $timedOut = -not $process.WaitForExit($ProcessTimeoutSeconds * 1000)
    if ($timedOut) {
        try { $process.Kill($true) } catch {}
        try { $process.WaitForExit() } catch {}
    }

    return [pscustomobject]@{
        ExitCode = if ($timedOut) { $null } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = (ConvertFrom-NativeText -Value ($stdoutTask.GetAwaiter().GetResult())).Trim()
        Stderr = (ConvertFrom-NativeText -Value ($stderrTask.GetAwaiter().GetResult())).Trim()
    }
}

function Resolve-WezTermCli {
    Refresh-WindowsPath
    foreach ($commandName in @('wezterm.exe', 'wezterm')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @(
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\wezterm.exe' })
    )) {
        if ($candidate) { [void]$candidates.Add($candidate) }
    }

    $wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $wingetPackages -PathType Container) {
        Get-ChildItem -LiteralPath $wingetPackages -Filter 'wezterm.exe' -File -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            Select-Object -First 10 |
            ForEach-Object { [void]$candidates.Add($_.FullName) }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Get-WslCommandPath {
    param(
        [Parameter(Mandatory)][string]$WslPath,
        [ValidateSet('tmux', 'agy', 'opencode')][string]$Tool
    )

    $probe = Invoke-BoundedProcess -FilePath $WslPath -ArgumentList @(
        '-d', $Distribution, '--', 'bash', '-lc',
        'export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"; command -v "$1"',
        'agentswitchboard-command-path', $Tool
    ) -ProcessTimeoutSeconds 30

    if ($probe.TimedOut -or $probe.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($probe.Stdout)) {
        throw "Unable to resolve '$Tool' inside WSL distribution '$Distribution'. stdout=$($probe.Stdout) stderr=$($probe.Stderr)"
    }

    $path = ($probe.Stdout -split "`r?`n" | Select-Object -Last 1).Trim()
    if ($path -notmatch '^/[A-Za-z0-9._/+~-]+$') {
        throw "WSL returned an unsafe command path for '$Tool': $path"
    }
    return $path
}

function Write-CommandShim {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][ValidateSet('windows', 'wsl')][string]$Kind,
        [string]$WslPath
    )

    $null = New-Item -ItemType Directory -Path $commandShimRoot -Force
    $shimPath = Join-Path $commandShimRoot "$Name.cmd"
    $lines = if ($Kind -eq 'windows') {
        @(
            '@echo off',
            ('call "{0}" %*' -f $Target),
            'exit /b %ERRORLEVEL%'
        )
    }
    else {
        @(
            '@echo off',
            ('"{0}" -d "{1}" --exec "{2}" %*' -f $WslPath, $Distribution, $Target),
            'exit /b %ERRORLEVEL%'
        )
    }
    [System.IO.File]::WriteAllLines($shimPath, $lines, [System.Text.Encoding]::ASCII)
    return $shimPath
}

function New-AgentSwitchboardShortcut {
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    $desktopPath = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        throw 'The current Windows profile does not expose a Desktop folder for the AgentSwitchboard shortcut.'
    }

    $shortcutPath = Join-Path $desktopPath 'AgentSwitchboard.lnk'
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = 'AgentSwitchboard local agent readiness and bounded launch'
    $shortcut.Save()

    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
        throw "AgentSwitchboard shortcut was not created: $shortcutPath"
    }
    return $shortcutPath
}

$transcriptStarted = $false
try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
    $transcriptStarted = $true

    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' AgentSwitchboard Technician Ready' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host "Mode:       $Mode"
    Write-Host "Repository: $RepoRoot"
    Write-Host "Evidence:   $runRoot"

    $gitHead = (& git.exe -C $RepoRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitHead)) {
        throw 'Unable to resolve the repository HEAD.'
    }
    Add-Step -Name 'repository-head' -Status 'passed' -Evidence $gitHead

    if ($SurfaceOnly -or $env:TECHNICIAN_AGENTSWITCHBOARD_CI_SURFACE -eq '1') {
        Add-Step -Name 'surface-only' -Status 'passed' -Evidence 'Repository-owned entrypoints and dependencies resolved without workstation mutation.'
        $summary.status = 'surface-passed'
        return
    }

    $wezTermPath = Resolve-WezTermCli
    if (-not $wezTermPath) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $winget) {
            throw 'WezTerm is missing and WinGet is unavailable. Install WezTerm from its official Windows installer, then rerun the repository-owned technician CMD.'
        }
        & $winget.Source install --id wez.wezterm --exact --source winget --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet could not install WezTerm. Exit code: $LASTEXITCODE"
        }
        Refresh-WindowsPath
        $wezTermPath = Resolve-WezTermCli
    }
    if (-not $wezTermPath) {
        throw 'WezTerm installation completed without a resolvable wezterm.exe.'
    }
    $wezTermVersion = Invoke-BoundedProcess -FilePath $wezTermPath -ArgumentList @('--version') -ProcessTimeoutSeconds 30
    if ($wezTermVersion.TimedOut -or $wezTermVersion.ExitCode -ne 0) {
        throw "WezTerm version probe failed. stdout=$($wezTermVersion.Stdout) stderr=$($wezTermVersion.Stderr)"
    }
    Add-Step -Name 'wezterm' -Status 'passed' -Evidence "$wezTermPath :: $($wezTermVersion.Stdout)"

    $wslPath = Join-Path $env:SystemRoot 'System32\wsl.exe'
    if (-not (Test-Path -LiteralPath $wslPath -PathType Leaf)) {
        throw 'WSL is not installed. Run Repair-Technician-WSL-Ubuntu.cmd and rerun this repository-owned technician CMD.'
    }

    $rawDistributions = @(& $wslPath --list --quiet)
    if ($LASTEXITCODE -ne 0) {
        throw 'WSL exists but could not enumerate distributions. Run Repair-Technician-WSL-Ubuntu.cmd.'
    }
    $distributions = @($rawDistributions | ForEach-Object { (ConvertFrom-NativeText $_).Trim() } | Where-Object { $_ })
    if ($Distribution -notin $distributions) {
        throw "WSL distribution '$Distribution' is not initialized. Run Repair-Technician-WSL-Ubuntu.cmd."
    }
    Add-Step -Name 'wsl-distribution' -Status 'passed' -Evidence $Distribution

    $linuxSetup = @'
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

if ! command -v curl >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates
fi
if ! command -v tmux >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y tmux
fi
if ! command -v agy >/dev/null 2>&1; then
  curl -fsSL https://antigravity.google/cli/install.sh | bash
fi
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
if ! command -v opencode >/dev/null 2>&1; then
  curl -fsSL https://opencode.ai/install | bash
fi
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
if tmux list-sessions >/dev/null 2>&1; then
  tmux set-environment -g PATH "$PATH"
fi
command -v tmux
tmux -V
command -v agy
agy --version
command -v opencode
opencode --version
'@

    & $wslPath -d $Distribution -- bash -lc $linuxSetup
    if ($LASTEXITCODE -ne 0) {
        throw "WSL tool setup failed in '$Distribution' with exit code $LASTEXITCODE."
    }
    Add-Step -Name 'wsl-agent-tools' -Status 'passed' -Evidence 'tmux, AGY, and OpenCode passed command and version probes inside Ubuntu.'

    $wslToolPaths = [ordered]@{
        tmux = Get-WslCommandPath -WslPath $wslPath -Tool tmux
        agy = Get-WslCommandPath -WslPath $wslPath -Tool agy
        opencode = Get-WslCommandPath -WslPath $wslPath -Tool opencode
    }

    $shimPaths = [ordered]@{
        wezterm = Write-CommandShim -Name 'wezterm' -Target $wezTermPath -Kind windows
        tmux = Write-CommandShim -Name 'tmux' -Target $wslToolPaths.tmux -Kind wsl -WslPath $wslPath
        agy = Write-CommandShim -Name 'agy' -Target $wslToolPaths.agy -Kind wsl -WslPath $wslPath
        opencode = Write-CommandShim -Name 'opencode' -Target $wslToolPaths.opencode -Kind wsl -WslPath $wslPath
        AgentSwitchboard = Write-CommandShim -Name 'AgentSwitchboard' -Target $agentSwitchboardCmd -Kind windows
    }
    Ensure-UserPathEntry -Path $commandShimRoot
    Add-Step -Name 'command-shims' -Status 'passed' -Evidence "Registered five repository-owned command shims under $commandShimRoot."

    $pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $gnhfArguments = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $gnhfSetup,
        '-DefaultRepoPath', $RepoRoot,
        '-InstallOpenCodeAndCopilot'
    )
    if ($Mode -ne 'hermes') {
        $gnhfArguments += '-SkipHermesInstall'
    }
    $gnhfResult = Invoke-BoundedProcess -FilePath $pwshPath -ArgumentList $gnhfArguments -ProcessTimeoutSeconds $TimeoutSeconds
    $gnhfResult.Stdout | Set-Content -LiteralPath (Join-Path $runRoot 'gnhf-setup-stdout.txt') -Encoding utf8
    $gnhfResult.Stderr | Set-Content -LiteralPath (Join-Path $runRoot 'gnhf-setup-stderr.txt') -Encoding utf8
    if ($gnhfResult.TimedOut -or $gnhfResult.ExitCode -ne 0) {
        throw "Canonical GNHF fleet setup failed. exit=$($gnhfResult.ExitCode) timeout=$($gnhfResult.TimedOut) stderr=$($gnhfResult.Stderr)"
    }
    if (-not (Test-Path -LiteralPath $fleetStatePath -PathType Leaf)) {
        throw "Canonical GNHF fleet setup did not produce state: $fleetStatePath"
    }
    $fleetState = Get-Content -LiteralPath $fleetStatePath -Raw | ConvertFrom-Json
    if ($fleetState.schemaVersion -ne 1 -or $null -eq $fleetState.agents) {
        throw "Canonical GNHF fleet state is malformed: $fleetStatePath"
    }
    Add-Step -Name 'gnhf-fleet-state' -Status 'passed' -Evidence $fleetStatePath

    $null = New-Item -ItemType Directory -Path $startupEvidenceRoot -Force
    & $startupReporter -InstallRoot $fleetRoot -OutputRoot $startupEvidenceRoot | Out-Null
    $startupJson = Get-ChildItem -LiteralPath $startupEvidenceRoot -Filter 'agent-startup-readiness-*.json' -File |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $startupJson) {
        throw 'Startup-readiness reporter did not produce JSON evidence.'
    }
    $startup = Get-Content -LiteralPath $startupJson.FullName -Raw | ConvertFrom-Json
    if (-not $startup.stateObserved) {
        throw 'AgentSwitchboard startup readiness did not observe canonical fleet state.'
    }
    if ($startup.overallStatus -in @('not-configured', 'blocked')) {
        throw "AgentSwitchboard remains unusable after setup. Overall readiness: $($startup.overallStatus)"
    }
    $usableAgents = @($startup.agents | Where-Object { $_.status -in @('adapter-ready', 'verification-required') })
    if ($usableAgents.Count -lt 1) {
        throw 'AgentSwitchboard startup readiness found no locally usable agent route.'
    }
    $summary.startupReadiness = [ordered]@{
        overallStatus = $startup.overallStatus
        stateObserved = [bool]$startup.stateObserved
        usableAgentCount = $usableAgents.Count
        evidence = $startupJson.FullName
    }
    Add-Step -Name 'startup-readiness' -Status 'passed' -Evidence "$($startup.overallStatus) :: $($startupJson.FullName)"

    $shortcutPath = New-AgentSwitchboardShortcut -TargetPath $shimPaths.AgentSwitchboard -WorkingDirectory $RepoRoot
    $summary.shortcuts = [ordered]@{ AgentSwitchboard = $shortcutPath }
    Add-Step -Name 'operator-shortcut' -Status 'passed' -Evidence $shortcutPath

    $probeCommand = "`"$($shimPaths.AgentSwitchboard)`" -ListAgents"
    $freshProbe = Invoke-BoundedProcess -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/d', '/c', $probeCommand) -ProcessTimeoutSeconds 120
    @($freshProbe.Stdout, $freshProbe.Stderr) | Set-Content -LiteralPath $probeOutputPath -Encoding utf8
    if ($freshProbe.TimedOut -or $freshProbe.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($freshProbe.Stdout)) {
        throw "Fresh-shell AgentSwitchboard -ListAgents probe failed. exit=$($freshProbe.ExitCode) timeout=$($freshProbe.TimedOut) evidence=$probeOutputPath"
    }
    Add-Step -Name 'fresh-shell-agentswitchboard' -Status 'passed' -Evidence "$($shimPaths.AgentSwitchboard) :: $probeOutputPath"

    $summary.commands = [ordered]@{
        AgentSwitchboard = [ordered]@{ command = 'AgentSwitchboard'; shim = $shimPaths.AgentSwitchboard; target = $agentSwitchboardCmd }
        wezterm = [ordered]@{ command = 'wezterm'; shim = $shimPaths.wezterm; target = $wezTermPath }
        tmux = [ordered]@{ command = 'tmux'; shim = $shimPaths.tmux; target = $wslToolPaths.tmux; distribution = $Distribution }
        agy = [ordered]@{ command = 'agy'; shim = $shimPaths.agy; target = $wslToolPaths.agy; distribution = $Distribution }
        opencode = [ordered]@{ command = 'opencode'; shim = $shimPaths.opencode; target = $wslToolPaths.opencode; distribution = $Distribution }
    }

    if ($Mode -eq 'setup' -or $Mode -eq 'hermes') {
        Add-Step -Name 'launch' -Status 'skipped' -Evidence "Mode '$Mode' requested setup/readiness without opening the Windows profile."
        $summary.status = 'success'
        return
    }

    & $pwshPath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $profileLauncher `
        -Mode open-or-activate `
        -Operation Launch `
        -ManifestPath $profileManifest `
        -OutputDirectory $launcherEvidenceRoot `
        -WezTermExe $wezTermPath
    if ($LASTEXITCODE -ne 0) {
        throw "Canonical Windows Profile launcher failed. Evidence: $launcherEvidenceRoot"
    }
    Add-Step -Name 'windows-profile-launch' -Status 'passed' -Evidence $launcherEvidenceRoot

    if ($Mode -in @('agy', 'opencode')) {
        $toolPath = [string]$wslToolPaths[$Mode]
        $toolWindowScript = @'
set -euo pipefail
session='dev'
window='__TOOL__'
tool='__TOOL_PATH__'
if ! tmux has-session -t "$session" 2>/dev/null; then
  echo "Expected tmux session '$session' was not found." >&2
  exit 50
fi
if tmux list-windows -t "$session" -F '#W' | grep -Fxq "$window"; then
  tmux select-window -t "$session:$window"
else
  tmux new-window -d -t "$session" -n "$window" "exec '$tool'"
  tmux select-window -t "$session:$window"
fi
'@.Replace('__TOOL__', $Mode).Replace('__TOOL_PATH__', $toolPath)

        & $wslPath -d $Distribution -- bash -lc $toolWindowScript
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to open or select tmux window '$Mode'."
        }
        Add-Step -Name 'agent-window' -Status 'passed' -Evidence "$Mode :: $toolPath"
    }

    $summary.status = 'success'
}
catch {
    $summary.status = 'failed'
    $summary.error = $_.Exception.ToString()
    Add-Step -Name 'technician-ready' -Status 'failed' -Evidence $_.Exception.Message
    Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
    $summary.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $summary | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }

    Write-Host ''
    Write-Host "Status:     $($summary.status)" -ForegroundColor $(if ($summary.status -in @('success', 'surface-passed')) { 'Green' } else { 'Red' })
    Write-Host "Transcript: $transcriptPath"
    Write-Host "Summary:    $summaryPath"
}

if ($summary.status -notin @('success', 'surface-passed')) {
    exit 1
}
exit 0
