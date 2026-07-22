[CmdletBinding()]
param(
    [ValidateSet('continue', 'new')]
    [string]$Mode = 'continue',

    [ValidateSet('Plan', 'Launch')]
    [string]$Operation = 'Launch',

    [string]$ManifestPath = (Join-Path $PSScriptRoot 'windows-tmux-launch.json'),

    [string[]]$ExistingSessions,

    [string]$OutputDirectory,

    [string]$WslExe,

    [string]$WezTermExe,

    [ValidateRange(5, 120)]
    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Executable {
    param(
        [string]$RequestedPath,
        [string[]]$CommandNames,
        [string[]]$Candidates,
        [string]$DisplayName
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
    }

    foreach ($name in $CommandNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "$DisplayName was not found."
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][int]$Timeout
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
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

    if (-not $process.WaitForExit($Timeout * 1000)) {
        try { $process.Kill($true) } catch {}
        try { $process.WaitForExit() } catch {}
        throw "Process timed out after ${Timeout}s: $FilePath"
    }

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdoutTask.GetAwaiter().GetResult().Replace([string][char]0, [string]::Empty).Trim()
        Stderr = $stderrTask.GetAwaiter().GetResult().Replace([string][char]0, [string]::Empty).Trim()
    }
}

function Write-JsonArtifact {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function Get-ExistingFrontend {
    param([Parameter(Mandatory)][string]$WindowClass)

    if ($env:OS -ne 'Windows_NT') { return $null }

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^wezterm(-gui)?\.exe$' -and
            -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
            $_.CommandLine.Contains($WindowClass, [StringComparison]::OrdinalIgnoreCase)
        } |
        Select-Object -First 1
}

function Try-ActivateFrontend {
    param([Parameter(Mandatory)][int]$ProcessId)

    if ($env:OS -ne 'Windows_NT') { return $false }

    if (-not ('AgentSwitchboard.NativeWindow' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace AgentSwitchboard {
    public static class NativeWindow {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    }
}
'@
    }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process -or $process.MainWindowHandle -eq 0) { return $false }

    [void][AgentSwitchboard.NativeWindow]::ShowWindowAsync($process.MainWindowHandle, 9)
    return [AgentSwitchboard.NativeWindow]::SetForegroundWindow($process.MainWindowHandle)
}

$manifest = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop) -Raw | ConvertFrom-Json
if ($manifest.schema -ne 'agentswitchboard.windows-tmux-launch.v1') {
    throw "Unsupported manifest schema: $($manifest.schema)"
}

$distribution = [string]$manifest.distribution
$continueSession = [string]$manifest.continueSession
$newPrefix = [string]$manifest.newSessionPrefix
$workspacePrefix = [string]$manifest.workspacePrefix
$classPrefix = [string]$manifest.classPrefix
$initialWindowName = [string]$manifest.initialWindowName
$maximumInstances = [int]$manifest.maximumInstances

foreach ($value in @($continueSession, $newPrefix, $workspacePrefix, $initialWindowName)) {
    if ($value -notmatch '^[A-Za-z0-9_-]+$') { throw "Unsafe tmux/workspace value: $value" }
}
if ($classPrefix -notmatch '^[A-Za-z0-9._-]+$') { throw "Unsafe class prefix: $classPrefix" }
if ($distribution -notmatch '^[A-Za-z0-9._-]+$') { throw "Unsafe WSL distribution: $distribution" }

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $root = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\profiles\windows\runs'
    }
    else {
        Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/windows-tmux-launch/runs'
    }
    $OutputDirectory = Join-Path $root ('{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), ([guid]::NewGuid().ToString('N').Substring(0, 8)))
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

$sessionInventory = @()
$resolvedWsl = $null
$resolvedWezTerm = $null

if ($Operation -eq 'Plan') {
    $sessionInventory = @($ExistingSessions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
else {
    $wslCandidates = if ($env:SystemRoot) { @(Join-Path $env:SystemRoot 'System32\wsl.exe') } else { @() }
    $wezCandidates = @()
    if ($env:ProgramFiles) { $wezCandidates += (Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe') }
    if ($env:LOCALAPPDATA) { $wezCandidates += (Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe') }

    $resolvedWsl = Resolve-Executable -RequestedPath $WslExe -CommandNames @('wsl.exe') -Candidates $wslCandidates -DisplayName 'WSL'
    $resolvedWezTerm = Resolve-Executable -RequestedPath $WezTermExe -CommandNames @('wezterm.exe', 'wezterm') -Candidates $wezCandidates -DisplayName 'WezTerm'

    $inventory = Invoke-BoundedProcess -FilePath $resolvedWsl -ArgumentList @(
        '-d', $distribution, '-e', 'bash', '-lc', "if ! command -v tmux >/dev/null 2>&1; then exit 40; fi; tmux list-sessions -F '#S' 2>/dev/null || true"
    ) -Timeout $TimeoutSeconds
    if ($inventory.ExitCode -eq 40) { throw "tmux is not installed in WSL distribution '$distribution'." }
    if ($inventory.ExitCode -ne 0) { throw "Unable to inspect tmux sessions. $($inventory.Stderr)" }
    $sessionInventory = @($inventory.Stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$sessionName = $null
$workspace = $null
$windowClass = $null
$requiresCreation = $false
$existingFrontend = $null

if ($Mode -eq 'continue') {
    $sessionName = $continueSession
    $workspace = "$workspacePrefix-continue-$sessionName"
    $windowClass = "$classPrefix.continue.$sessionName"
    $requiresCreation = ($sessionInventory -notcontains $sessionName)

    if ($Operation -eq 'Launch') {
        $existingFrontend = Get-ExistingFrontend -WindowClass $windowClass
        if ($existingFrontend) {
            if ($requiresCreation) {
                throw "A marked continue frontend exists, but tmux session '$sessionName' does not. No duplicate frontend was launched."
            }

            $activated = Try-ActivateFrontend -ProcessId ([int]$existingFrontend.ProcessId)
            $result = [ordered]@{
                schema = 'agentswitchboard.windows-tmux-launch-result.v1'
                status = if ($activated) { 'activated-existing' } else { 'existing-detected-not-duplicated' }
                mode = $Mode
                sessionName = $sessionName
                workspace = $workspace
                windowClass = $windowClass
                wezTermProcessId = [int]$existingFrontend.ProcessId
                newSessionCreated = $false
                newFrontendStarted = $false
                proofLevel = 'process-observation'
                proofCeiling = 'A marked frontend process was detected and no duplicate was launched. Foreground activation may still require operator observation.'
            }
            Write-JsonArtifact -Value $result -Path (Join-Path $OutputDirectory 'windows-tmux-launch-result.json')
            $result | ConvertTo-Json -Depth 10
            exit 0
        }
    }
}
else {
    $selected = $null
    for ($index = 1; $index -le $maximumInstances; $index++) {
        $candidate = "$newPrefix-$index"
        if ($sessionInventory -notcontains $candidate) {
            $selected = $candidate
            break
        }
    }
    if (-not $selected) { throw "No unused numbered tmux session remains below $maximumInstances." }

    $sessionName = $selected
    $workspace = "$workspacePrefix-new-$sessionName"
    $windowClass = "$classPrefix.new.$sessionName"
    $requiresCreation = $true
}

$attachCommand = "exec tmux attach-session -t '$sessionName'"
$createCommand = "set -euo pipefail; tmux new-session -d -s '$sessionName' -n '$initialWindowName'; tmux has-session -t '$sessionName'"
$wezTermArguments = @(
    'start', '--always-new-process', '--workspace', $workspace, '--class', $windowClass, '--',
    $(if ($resolvedWsl) { $resolvedWsl } else { 'wsl.exe' }), '-d', $distribution, '-e', 'bash', '-lc', $attachCommand
)

$plan = [ordered]@{
    schema = 'agentswitchboard.windows-tmux-launch-plan.v1'
    operation = $Operation
    mode = $Mode
    distribution = $distribution
    sessionName = $sessionName
    existingSessions = @($sessionInventory)
    requiresSessionCreation = $requiresCreation
    workspace = $workspace
    windowClass = $windowClass
    createSessionCommand = if ($requiresCreation) { $createCommand } else { $null }
    attachCommand = $attachCommand
    wezTermArguments = $wezTermArguments
    continueNeverAllocatesNumberedSession = ($Mode -eq 'continue')
    newNeverAttachesExistingSession = ($Mode -eq 'new')
    oneRequestMaximumNewFrontends = 1
    generatedEvidenceTracked = $false
    proofCeiling = [string]$manifest.proofCeiling
}
$planPath = Join-Path $OutputDirectory 'windows-tmux-launch-plan.json'
Write-JsonArtifact -Value $plan -Path $planPath

if ($Operation -eq 'Plan') {
    $plan | ConvertTo-Json -Depth 10
    exit 0
}

if ($requiresCreation) {
    $created = Invoke-BoundedProcess -FilePath $resolvedWsl -ArgumentList @(
        '-d', $distribution, '-e', 'bash', '-lc', $createCommand
    ) -Timeout $TimeoutSeconds
    if ($created.ExitCode -ne 0) { throw "Unable to create tmux session '$sessionName'. $($created.Stderr)" }
}

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.FileName = $resolvedWezTerm
foreach ($argument in $wezTermArguments) { [void]$psi.ArgumentList.Add([string]$argument) }
$wezTermProcess = [System.Diagnostics.Process]::Start($psi)
if (-not $wezTermProcess) { throw 'WezTerm did not return a process handle.' }

$result = [ordered]@{
    schema = 'agentswitchboard.windows-tmux-launch-result.v1'
    status = 'launch-command-accepted'
    mode = $Mode
    sessionName = $sessionName
    workspace = $workspace
    windowClass = $windowClass
    wezTermProcessId = $wezTermProcess.Id
    newSessionCreated = $requiresCreation
    newFrontendStarted = $true
    planPath = $planPath
    proofLevel = 'command-ack'
    proofCeiling = 'The tmux command succeeded and one WezTerm process was requested. Visible-window, attachment, layout, and operator acceptance remain runtime proof.'
}
Write-JsonArtifact -Value $result -Path (Join-Path $OutputDirectory 'windows-tmux-launch-result.json')
$result | ConvertTo-Json -Depth 10
