[CmdletBinding()]
param(
    [string]$RepoRoot,

    [string]$Distribution = 'Ubuntu',

    [switch]$SurfaceOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT' -and -not $SurfaceOnly) {
    throw 'The technician bootstrap prerequisite gate must run on Windows.'
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve the prerequisite-gate directory. Supply -RepoRoot explicitly.'
    }
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path

$enginePath = Join-Path $RepoRoot 'tooling\profiles\windows\Invoke-TechnicianAgentSwitchboardReady.ps1'
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Canonical technician readiness engine is missing: $enginePath"
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
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
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

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$ProcessTimeoutSeconds = 60
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
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

    foreach ($candidate in @(
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\wezterm.exe' })
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

if ($SurfaceOnly -or $env:TECHNICIAN_AGENTSWITCHBOARD_CI_SURFACE -eq '1') {
    Write-Host 'PASS: Technician prerequisite gate surface resolved without workstation mutation.' -ForegroundColor Green
    exit 0
}

$wezTermPath = Resolve-WezTermCli
if (-not $wezTermPath) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'WezTerm is missing and WinGet is unavailable. Install WezTerm, then rerun the repository-owned technician command.'
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
Write-Host "PASS: WezTerm prerequisite :: $wezTermPath :: $($wezTermVersion.Stdout)" -ForegroundColor Green

$wslPath = Join-Path $env:SystemRoot 'System32\wsl.exe'
if (-not (Test-Path -LiteralPath $wslPath -PathType Leaf)) {
    throw 'WSL is not installed. Run Repair-Technician-WSL-Ubuntu.cmd before AgentSwitchboard readiness.'
}

$rawDistributions = @(& $wslPath --list --quiet)
if ($LASTEXITCODE -ne 0) {
    throw 'WSL exists but could not enumerate distributions. Run Repair-Technician-WSL-Ubuntu.cmd.'
}
$distributions = @($rawDistributions | ForEach-Object { (ConvertFrom-NativeText $_).Trim() } | Where-Object { $_ })
if ($Distribution -notin $distributions) {
    throw "WSL distribution '$Distribution' is not initialized. Run Repair-Technician-WSL-Ubuntu.cmd."
}

$tmuxSetup = @'
set -euo pipefail
if ! command -v tmux >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y tmux
fi
command -v tmux
tmux -V
'@

$tmuxResult = Invoke-BoundedProcess -FilePath $wslPath -ArgumentList @(
    '-d', $Distribution, '--', 'bash', '-lc', $tmuxSetup
) -ProcessTimeoutSeconds 300
if ($tmuxResult.TimedOut -or $tmuxResult.ExitCode -ne 0) {
    throw "tmux prerequisite setup failed in '$Distribution'. exit=$($tmuxResult.ExitCode) timeout=$($tmuxResult.TimedOut) stdout=$($tmuxResult.Stdout) stderr=$($tmuxResult.Stderr)"
}
if ($tmuxResult.Stdout -notmatch '(?m)^tmux\s') {
    throw "tmux prerequisite setup completed without a version readback. stdout=$($tmuxResult.Stdout)"
}
Write-Host "PASS: tmux prerequisite :: $Distribution :: $($tmuxResult.Stdout -replace "`r?`n", ' :: ')" -ForegroundColor Green
exit 0
