[CmdletBinding()]
param(
    [ValidateSet('open-or-activate', 'new-instance')]
    [string]$Mode = 'open-or-activate',

    [string]$InstanceId = 'auto',

    [ValidateSet('Plan', 'Launch')]
    [string]$Operation = 'Launch',

    [string]$ManifestPath = (Join-Path $PSScriptRoot 'tmux-new-instance-shortcut.example.json'),

    [string[]]$ExistingSessions,

    [string]$OutputDirectory,

    [string]$WslExe,

    [string]$WezTermExe,

    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-WezTermCli {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $resolved = (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
        if ([System.IO.Path]::GetFileName($resolved) -notin @('wezterm.exe', 'wezterm')) {
            throw "The supplied WezTerm path is not the scripting CLI: $resolved"
        }
        return $resolved
    }

    $command = Get-Command wezterm.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $command = Get-Command wezterm -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @()
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe')
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe')
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'wezterm.exe was not found. Install WezTerm or pass -WezTermExe.'
}

function Resolve-WslExecutable {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
    }

    if ($env:SystemRoot) {
        $candidate = Join-Path $env:SystemRoot 'System32\wsl.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $command = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    throw 'wsl.exe was not found. Install and initialize WSL before launching the Windows Profile.'
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

    $stdout = $stdoutTask.GetAwaiter().GetResult().Replace([char]0, '')
    $stderr = $stderrTask.GetAwaiter().GetResult().Replace([char]0, '')
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
    }
}

function Get-NewInstanceIdentity {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][string[]]$Sessions,
        [Parameter(Mandatory)][string]$RequestedInstanceId,
        [Parameter(Mandatory)][int]$MaximumInstances,
        [Parameter(Mandatory)][string]$WorkspacePrefix,
        [Parameter(Mandatory)][string]$ClassPrefix
    )

    $existing = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($session in $Sessions) {
        if (-not [string]::IsNullOrWhiteSpace($session)) {
            [void]$existing.Add($session.Trim())
        }
    }

    if ($RequestedInstanceId -eq 'auto') {
        $selected = $null
        for ($index = 1; $index -le $MaximumInstances; $index++) {
            $candidate = "$Prefix-$index"
            if (-not $existing.Contains($candidate)) {
                $selected = [string]$index
                break
            }
        }
        if (-not $selected) {
            throw "No free tmux instance remains beneath the configured maximum of $MaximumInstances."
        }
    }
    else {
        if ($RequestedInstanceId -notmatch '^[a-z0-9][a-z0-9-]*$') {
            throw "Unsafe instance ID: $RequestedInstanceId"
        }
        $selected = $RequestedInstanceId
        $candidate = "$Prefix-$selected"
        if ($existing.Contains($candidate)) {
            throw "tmux instance '$candidate' already exists; a new-instance request may not attach to it."
        }
    }

    $sessionName = "$Prefix-$selected"
    return [pscustomobject]@{
        InstanceId = $selected
        SessionName = $sessionName
        Workspace = "$WorkspacePrefix-$sessionName"
        WindowClass = "$ClassPrefix.$sessionName"
    }
}

function Write-JsonArtifact {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    $null = New-Item -ItemType Directory -Path $directory -Force
    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
}

$resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 'agentswitchboard.tmux-new-instance-shortcut-manifest.v1') {
    throw "Unsupported manifest schema: $($manifest.schema)"
}

$distribution = [string]$manifest.distribution
$sessionPrefix = [string]$manifest.sessionPrefix
$workspacePrefix = [string]$manifest.workspacePrefix
$classPrefix = [string]$manifest.classPrefix
$initialWindowName = [string]$manifest.initialWindowName
$maximumInstances = [int]$manifest.maximumInstances

if ($distribution -notmatch '^[A-Za-z0-9._-]+$') { throw "Unsafe WSL distribution: $distribution" }
if ($sessionPrefix -notmatch '^[A-Za-z0-9_-]+$') { throw "Unsafe tmux session prefix: $sessionPrefix" }
if ($workspacePrefix -notmatch '^[A-Za-z0-9_-]+$') { throw "Unsafe WezTerm workspace prefix: $workspacePrefix" }
if ($classPrefix -notmatch '^[A-Za-z0-9._-]+$') { throw "Unsafe WezTerm class prefix: $classPrefix" }
if ($initialWindowName -notmatch '^[A-Za-z0-9_-]+$') { throw "Unsafe tmux window name: $initialWindowName" }
if ($maximumInstances -lt 1 -or $maximumInstances -gt 999) { throw 'maximumInstances must be between 1 and 999.' }

if ($Mode -eq 'open-or-activate') {
    Write-Error 'The default open-or-activate path remains blocked on this branch. This tracked launcher currently owns only explicit new-instance requests.'
    exit 42
}

if ($Operation -eq 'Launch' -and $null -ne $ExistingSessions -and $ExistingSessions.Count -gt 0) {
    throw '-ExistingSessions is allowed only with -Operation Plan.'
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $root = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\profiles\windows\tmux-new-instance\runs'
    }
    else {
        Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/tmux-new-instance/runs'
    }
    $runId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $OutputDirectory = Join-Path $root $runId
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

$sessionInventory = @()
$resolvedWsl = $null
$resolvedWezTerm = $null

if ($Operation -eq 'Plan') {
    $sessionInventory = @($ExistingSessions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
else {
    $resolvedWsl = Resolve-WslExecutable -RequestedPath $WslExe
    $resolvedWezTerm = Resolve-WezTermCli -RequestedPath $WezTermExe
}

$mutex = $null
$lockAcquired = $false
try {
    if ($Operation -eq 'Launch') {
        $mutex = [System.Threading.Mutex]::new($false, 'Local\AgentSwitchboard.TmuxNewInstance')
        $lockAcquired = $mutex.WaitOne([TimeSpan]::FromSeconds(10))
        if (-not $lockAcquired) {
            throw 'Another tmux new-instance launch is still allocating a session. Try again after it completes.'
        }

        $inventoryCommand = "if ! command -v tmux >/dev/null 2>&1; then echo '__TMUX_MISSING__' >&2; exit 40; fi; tmux list-sessions -F '#S' 2>/dev/null || true"
        $inventory = Invoke-BoundedProcess -FilePath $resolvedWsl -ArgumentList @(
            '-d', $distribution, '-e', 'bash', '-lc', $inventoryCommand
        ) -Timeout $TimeoutSeconds
        if ($inventory.ExitCode -eq 40 -or $inventory.Stderr.Contains('__TMUX_MISSING__')) {
            throw "tmux is not installed inside WSL distribution '$distribution'."
        }
        if ($inventory.ExitCode -ne 0) {
            throw "Unable to inspect tmux sessions in '$distribution'. $($inventory.Stderr)"
        }
        $sessionInventory = @($inventory.Stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $identity = Get-NewInstanceIdentity -Prefix $sessionPrefix -Sessions $sessionInventory -RequestedInstanceId $InstanceId -MaximumInstances $maximumInstances -WorkspacePrefix $workspacePrefix -ClassPrefix $classPrefix

    $attachCommand = "exec tmux attach-session -t '$($identity.SessionName)'"
    $wezTermArguments = @(
        'start',
        '--always-new-process',
        '--workspace', $identity.Workspace,
        '--class', $identity.WindowClass,
        '--',
        $(if ($resolvedWsl) { $resolvedWsl } else { 'wsl.exe' }),
        '-d', $distribution,
        '-e', 'bash', '-lc', $attachCommand
    )

    $plan = [ordered]@{
        schema = 'agentswitchboard.tmux-new-instance-launch-plan.v1'
        mode = $Mode
        operation = $Operation
        distribution = $distribution
        instanceId = $identity.InstanceId
        sessionName = $identity.SessionName
        workspace = $identity.Workspace
        windowClass = $identity.WindowClass
        existingSessions = @($sessionInventory)
        allocationPolicy = [string]$manifest.allocationPolicy
        createSessionCommand = "tmux new-session -d -s '$($identity.SessionName)' -n '$initialWindowName'"
        attachCommand = $attachCommand
        wezTermArguments = $wezTermArguments
        oneRequestMaximumNewWindows = 1
        separateFrontendProcessRequired = $true
        generatedEvidenceTracked = $false
        proofCeiling = 'Deterministic identity allocation and command construction only until Launch completes and the operator observes the window.'
    }
    $planPath = Join-Path $OutputDirectory 'tmux-new-instance-launch-plan.json'
    Write-JsonArtifact -Value $plan -Path $planPath

    if ($Operation -eq 'Plan') {
        $plan | ConvertTo-Json -Depth 10
        exit 0
    }

    $createCommand = "set -euo pipefail; tmux new-session -d -s '$($identity.SessionName)' -n '$initialWindowName'; tmux has-session -t '$($identity.SessionName)'"
    $created = Invoke-BoundedProcess -FilePath $resolvedWsl -ArgumentList @(
        '-d', $distribution, '-e', 'bash', '-lc', $createCommand
    ) -Timeout $TimeoutSeconds
    if ($created.ExitCode -ne 0) {
        throw "Unable to create tmux session '$($identity.SessionName)'. $($created.Stderr)"
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.FileName = $resolvedWezTerm
    foreach ($argument in $wezTermArguments) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }
    $wezTermProcess = [System.Diagnostics.Process]::Start($psi)
    if (-not $wezTermProcess) {
        throw 'WezTerm did not return a process handle.'
    }

    $result = [ordered]@{
        schema = 'agentswitchboard.tmux-new-instance-launch-result.v1'
        status = 'launch-command-accepted'
        mode = $Mode
        distribution = $distribution
        instanceId = $identity.InstanceId
        sessionName = $identity.SessionName
        workspace = $identity.Workspace
        windowClass = $identity.WindowClass
        wezTermProcessId = $wezTermProcess.Id
        planPath = $planPath
        sessionCreated = $true
        separateFrontendProcessRequested = $true
        visibleWindowObserved = $false
        tmuxClientAttachedObserved = $false
        proofLevel = 'command-ack'
        proofCeiling = 'The tmux session was created and a separate WezTerm process was requested. Window visibility, attachment, layout, and operator acceptance remain end-to-end runtime proof.'
    }
    $resultPath = Join-Path $OutputDirectory 'tmux-new-instance-launch-result.json'
    Write-JsonArtifact -Value $result -Path $resultPath
    $result | ConvertTo-Json -Depth 10
    exit 0
}
catch {
    $failure = [ordered]@{
        schema = 'agentswitchboard.tmux-new-instance-launch-result.v1'
        status = 'failed'
        mode = $Mode
        error = $_.Exception.Message
        visibleWindowObserved = $false
        proofLevel = 'failure-evidence'
        proofCeiling = 'Failure evidence only; no successful tmux or WezTerm behavior is claimed.'
    }
    try {
        Write-JsonArtifact -Value $failure -Path (Join-Path $OutputDirectory 'tmux-new-instance-launch-result.json')
    }
    catch {}
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    if ($lockAcquired -and $mutex) {
        try { $mutex.ReleaseMutex() } catch {}
    }
    if ($mutex) { $mutex.Dispose() }
}
