[CmdletBinding()]
param(
    [ValidateSet('shell', 'agy', 'opencode', 'setup', 'hermes')]
    [string]$Mode = 'shell',

    [Parameter(Mandatory)]
    [string]$RepoRoot,

    [string]$GitRef = 'main',

    [string]$Distribution = 'Ubuntu',

    [ValidateRange(30, 1800)]
    [int]$HermesTimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'The technician Windows Profile setup must run on Windows.'
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path
$launcherPath = Join-Path $RepoRoot 'tooling\profiles\windows\Invoke-AgentSwitchboardOpenOrActivate.ps1'
$manifestPath = Join-Path $RepoRoot 'tooling\profiles\windows\tmux-new-instance-shortcut.example.json'
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    throw "Canonical Windows Profile launcher is missing: $launcherPath"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Windows Profile manifest is missing: $manifestPath"
}

$startedAt = Get-Date
$runId = '{0}-{1}' -f $startedAt.ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\technician-quickstart\runs\$runId"
$null = New-Item -ItemType Directory -Path $runRoot -Force
$transcriptPath = Join-Path $runRoot 'technician-quickstart-transcript.txt'
$summaryPath = Join-Path $runRoot 'technician-quickstart-summary.json'
$launcherEvidenceRoot = Join-Path $runRoot 'launcher'
$commandShimRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin'

$steps = [System.Collections.Generic.List[object]]::new()
$summary = [ordered]@{
    schema = 'agentswitchboard.technician-quickstart-result.v2'
    runId = $runId
    startedAt = $startedAt.ToUniversalTime().ToString('o')
    completedAt = $null
    status = 'running'
    mode = $Mode
    repository = 'https://github.com/EndeavorEverlasting/AgentSwitchboard'
    repositoryRoot = $RepoRoot
    gitRef = $GitRef
    distribution = $Distribution
    evidenceRoot = $runRoot
    commandShimRoot = $commandShimRoot
    officialInstallSources = [ordered]@{
        wezterm = 'winget:wez.wezterm'
        agy = 'https://antigravity.google/cli/install.sh'
        opencode = 'https://opencode.ai/install'
        hermes = 'https://hermes-agent.nousresearch.com/install.ps1'
    }
    steps = $steps
    commands = $null
    error = $null
    proofLevel = 'workstation-setup-and-command-ack'
    proofCeiling = 'Installs and verifies prerequisites in the named WSL distribution, registers PowerShell-visible command shims, and requests the canonical Windows Profile. User-visible window behavior, authentication, provider response, and agent task quality remain separate runtime proof.'
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
        $updated = (@($resolved) + $entries) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
    }
    Refresh-WindowsPath
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 60,
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
        [void]$psi.ArgumentList.Add($argument)
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

    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try { $process.Kill($true) } catch {}
        try { $process.WaitForExit() } catch {}
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult().Replace([char]0, '')
    $stderr = $stderrTask.GetAwaiter().GetResult().Replace([char]0, '')
    return [pscustomobject]@{
        ExitCode = if ($timedOut) { $null } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
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
            Select-Object -First 5 |
            ForEach-Object { [void]$candidates.Add($_.FullName) }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Invoke-WslInteractive {
    param(
        [Parameter(Mandatory)][string]$WslPath,
        [Parameter(Mandatory)][string]$Script,
        [Parameter(Mandatory)][string]$Stage
    )

    Write-Host "`n=== $Stage ===" -ForegroundColor Cyan
    & $WslPath -d $Distribution -- bash -lc $Script
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Stage failed in WSL distribution '$Distribution' with exit code $exitCode. Review $transcriptPath for the complete child output."
    }
}

function Get-WslCommandPath {
    param(
        [Parameter(Mandatory)][string]$WslPath,
        [ValidateSet('tmux', 'agy', 'opencode')][string]$Tool
    )

    $result = Invoke-BoundedProcess -FilePath $WslPath -ArgumentList @(
        '-d', $Distribution, '--', 'bash', '-lc',
        'export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"; command -v "$1"',
        'agentswitchboard-command-path', $Tool
    ) -TimeoutSeconds 30
    if ($result.TimedOut -or $result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Stdout)) {
        throw "Unable to resolve '$Tool' inside WSL distribution '$Distribution'. stdout=$($result.Stdout) stderr=$($result.Stderr)"
    }
    $path = ($result.Stdout -split "`r?`n" | Select-Object -Last 1).Trim()
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
            ('"{0}" %*' -f $Target),
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
    $lines | Set-Content -LiteralPath $shimPath -Encoding ascii
    return $shimPath
}

function Resolve-HermesCommand {
    Refresh-WindowsPath
    $command = Get-Command hermes -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in @(
        (Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'),
        (Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.cmd'),
        (Join-Path $env:LOCALAPPDATA 'hermes\hermes.exe')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Invoke-HermesPortalSetup {
    param([Parameter(Mandatory)][string]$HermesPath)

    $stdoutPath = Join-Path $runRoot 'hermes-portal-stdout.txt'
    $stderrPath = Join-Path $runRoot 'hermes-portal-stderr.txt'
    $pwshPath = Join-Path $PSHOME 'pwsh.exe'
    $commandText = '& $args[0] setup --portal'
    $result = Invoke-BoundedProcess -FilePath $pwshPath -ArgumentList @(
        '-NoLogo', '-NoProfile', '-Command', $commandText, $HermesPath
    ) -TimeoutSeconds $HermesTimeoutSeconds -InjectNewLine
    $result.Stdout | Set-Content -LiteralPath $stdoutPath -Encoding utf8
    $result.Stderr | Set-Content -LiteralPath $stderrPath -Encoding utf8
    if ($result.TimedOut) {
        throw "Hermes portal setup timed out after the browser handoff. A newline was injected before the handoff. Review $stdoutPath and $stderrPath."
    }
    if ($result.ExitCode -ne 0) {
        throw "Hermes portal setup failed with exit code $($result.ExitCode). A newline was injected before the browser handoff. Review $stdoutPath and $stderrPath."
    }
    Add-Step -Name 'hermes-browser-handoff' -Status 'passed' -Evidence "Injected one newline into Hermes setup before the browser handoff; stdout=$stdoutPath stderr=$stderrPath"
}

$transcriptStarted = $false
try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
    $transcriptStarted = $true

    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' AgentSwitchboard Technician Setup' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host "Mode:         $Mode"
    Write-Host "Repository:   $RepoRoot"
    Write-Host "Distribution: $Distribution"
    Write-Host "Evidence:     $runRoot"

    $gitHead = (& git -C $RepoRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitHead)) {
        throw 'Unable to resolve the pulled repository commit.'
    }
    Add-Step -Name 'repository-head' -Status 'passed' -Evidence $gitHead

    $wezTermPath = Resolve-WezTermCli
    if (-not $wezTermPath) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $winget) {
            throw 'WezTerm is missing and WinGet is unavailable. Install WezTerm from the official WezTerm Windows installer, then rerun this CMD.'
        }
        Write-Host "`n=== Install WezTerm ===" -ForegroundColor Cyan
        & $winget.Source install --id wez.wezterm --exact --source winget --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet could not install WezTerm. Exit code: $LASTEXITCODE"
        }
        Refresh-WindowsPath
        $wezTermPath = Resolve-WezTermCli
    }
    if (-not $wezTermPath) {
        throw 'WezTerm installation completed without a resolvable wezterm.exe. The resolver checked PATH, WinGet links, standard install roots, and WinGet package roots.'
    }
    $wezTermVersion = Invoke-BoundedProcess -FilePath $wezTermPath -ArgumentList @('--version') -TimeoutSeconds 30
    if ($wezTermVersion.TimedOut -or $wezTermVersion.ExitCode -ne 0) {
        throw "WezTerm was found at '$wezTermPath' but its version probe failed. stdout=$($wezTermVersion.Stdout) stderr=$($wezTermVersion.Stderr)"
    }
    Add-Step -Name 'wezterm' -Status 'passed' -Evidence "$wezTermPath :: $($wezTermVersion.Stdout)"

    $wslPath = Join-Path $env:SystemRoot 'System32\wsl.exe'
    if (-not (Test-Path -LiteralPath $wslPath -PathType Leaf)) {
        throw "WSL is not installed. Run 'wsl --install -d Ubuntu' from an elevated terminal, reboot if requested, complete Ubuntu initialization, and rerun this CMD."
    }
    $distributions = @(& $wslPath --list --quiet | ForEach-Object { ([string]$_).Replace([char]0, '').Trim() } | Where-Object { $_ })
    if ($Distribution -notin $distributions) {
        throw "WSL distribution '$Distribution' is missing. Run 'wsl --install -d $Distribution', complete first-run initialization, and rerun this CMD."
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

printf '__TMUX_PATH__='; command -v tmux
printf '__TMUX_VERSION__='; tmux -V
printf '__AGY_PATH__='; command -v agy
printf '__AGY_VERSION__='; agy --version
printf '__OPENCODE_PATH__='; command -v opencode
printf '__OPENCODE_VERSION__='; opencode --version
'@

    Invoke-WslInteractive -WslPath $wslPath -Script $linuxSetup -Stage 'Install or verify tmux, AGY, and OpenCode inside Ubuntu'
    Add-Step -Name 'wsl-agent-tools' -Status 'passed' -Evidence 'tmux, agy, and opencode resolved by absolute path and passed version probes inside Ubuntu.'

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
    }
    Ensure-UserPathEntry -Path $commandShimRoot

    foreach ($commandName in @('wezterm', 'tmux', 'agy', 'opencode')) {
        $resolvedCommand = Get-Command $commandName -ErrorAction SilentlyContinue
        if (-not $resolvedCommand) {
            throw "The repository-owned '$commandName' PowerShell/CMD shim was written but is not resolvable in the refreshed Windows PATH."
        }
    }
    $summary.commands = [ordered]@{
        wezterm = [ordered]@{ windowsCommand = 'wezterm'; shim = $shimPaths.wezterm; target = $wezTermPath }
        tmux = [ordered]@{ windowsCommand = 'tmux'; shim = $shimPaths.tmux; target = $wslToolPaths.tmux; distribution = $Distribution }
        agy = [ordered]@{ windowsCommand = 'agy'; shim = $shimPaths.agy; target = $wslToolPaths.agy; distribution = $Distribution }
        opencode = [ordered]@{ windowsCommand = 'opencode'; shim = $shimPaths.opencode; target = $wslToolPaths.opencode; distribution = $Distribution }
    }
    Add-Step -Name 'powershell-command-resolution' -Status 'passed' -Evidence "Registered wezterm, tmux, agy, and opencode shims under $commandShimRoot and refreshed the current and user PATH."

    if ($Mode -eq 'hermes') {
        $hermesPath = Resolve-HermesCommand
        if (-not $hermesPath) {
            $installerPath = Join-Path $runRoot 'hermes-install.ps1'
            Invoke-WebRequest -Uri 'https://hermes-agent.nousresearch.com/install.ps1' -OutFile $installerPath -UseBasicParsing
            & (Join-Path $PSHOME 'pwsh.exe') -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installerPath
            if ($LASTEXITCODE -ne 0) {
                throw "Hermes installer exited with code $LASTEXITCODE."
            }
            Refresh-WindowsPath
            $hermesPath = Resolve-HermesCommand
        }
        if (-not $hermesPath) {
            throw 'Hermes installation completed without a resolvable hermes command.'
        }
        Ensure-UserPathEntry -Path (Split-Path -Parent $hermesPath)
        Add-Step -Name 'hermes-install' -Status 'passed' -Evidence $hermesPath
        Invoke-HermesPortalSetup -HermesPath $hermesPath
        $summary.status = 'success'
        return
    }
    Add-Step -Name 'hermes' -Status 'skipped' -Evidence 'Hermes is isolated from the core WezTerm/tmux/AGY/OpenCode path. Run explicit hermes mode to install and authenticate it.'

    if ($Mode -eq 'setup') {
        $summary.status = 'success'
        Add-Step -Name 'launch' -Status 'skipped' -Evidence 'Setup-only mode requested.'
        return
    }

    Write-Host "`n=== Open canonical Windows Profile ===" -ForegroundColor Cyan
    $pwshPath = Join-Path $PSHOME 'pwsh.exe'
    & $pwshPath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $launcherPath `
        -Mode open-or-activate `
        -Operation Launch `
        -ManifestPath $manifestPath `
        -OutputDirectory $launcherEvidenceRoot `
        -WezTermExe $wezTermPath
    if ($LASTEXITCODE -ne 0) {
        throw "The canonical Windows Profile launcher failed with exit code $LASTEXITCODE. Review $launcherEvidenceRoot and $transcriptPath."
    }
    Add-Step -Name 'windows-profile-launch' -Status 'passed' -Evidence 'Canonical open-or-activate command was acknowledged using the resolved WezTerm executable path.'

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

        Invoke-WslInteractive -WslPath $wslPath -Script $toolWindowScript -Stage "Open or select the $Mode tmux window"
        Add-Step -Name 'agent-window' -Status 'passed' -Evidence "Requested tmux window '$Mode' in session 'dev' using absolute WSL command path '$toolPath'. Authentication and provider response remain interactive runtime gates."
    }

    $summary.status = 'success'
}
catch {
    $summary.status = 'failed'
    $summary.error = $_.Exception.ToString()
    Add-Step -Name 'technician-quickstart' -Status 'failed' -Evidence $_.Exception.Message
    Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
    $summary.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }

    Write-Host "`nStatus:     $($summary.status)" -ForegroundColor $(if ($summary.status -eq 'success') { 'Green' } else { 'Red' })
    Write-Host "Transcript: $transcriptPath"
    Write-Host "Summary:    $summaryPath"
}

if ($summary.status -ne 'success') {
    exit 1
}
exit 0
