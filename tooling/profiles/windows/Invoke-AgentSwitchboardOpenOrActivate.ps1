[CmdletBinding()]
param(
    [ValidateSet('open-or-activate', 'new-instance')]
    [string]$Mode = 'open-or-activate',

    [string]$InstanceId = 'auto',

    [ValidateSet('Plan', 'Launch')]
    [string]$Operation = 'Launch',

    [string]$ManifestPath,

    [string[]]$ExistingSessions,

    [string]$OutputDirectory,

    [string]$WslExe,

    [string]$WezTermExe,

    [ValidateRange(5, 300)]
    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve the Windows Profile launcher directory. Supply -ManifestPath explicitly.'
    }
    $ManifestPath = Join-Path $PSScriptRoot 'tmux-new-instance-shortcut.example.json'
}

function ConvertFrom-NativeText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace(([char]0).ToString(), [string]::Empty)
}

function Resolve-WezTermCli {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $resolved = (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
        if ([IO.Path]::GetFileName($resolved) -notin @('wezterm.exe', 'wezterm')) {
            throw "The supplied WezTerm path is not the scripting CLI: $resolved"
        }
        return $resolved
    }

    foreach ($name in @('wezterm.exe', 'wezterm')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
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

    throw 'wezterm.exe was not found. Run Technician-AgentSwitchboard-Ready.cmd setup.'
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

    throw 'wsl.exe was not found. Run Repair-Technician-WSL-Ubuntu.cmd.'
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][int]$Timeout
    )

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.FileName = $FilePath
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }

    $process = [Diagnostics.Process]::new()
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
        Stdout = (ConvertFrom-NativeText -Value ($stdoutTask.GetAwaiter().GetResult())).Trim()
        Stderr = (ConvertFrom-NativeText -Value ($stderrTask.GetAwaiter().GetResult())).Trim()
    }
}

function Write-JsonArtifact {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    $null = New-Item -ItemType Directory -Path $directory -Force
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function Get-SessionIdentity {
    param(
        [Parameter(Mandatory)][string]$SessionPrefix,
        [Parameter(Mandatory)][string]$WorkspacePrefix,
        [Parameter(Mandatory)][string]$ClassPrefix,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Sessions,
        [Parameter(Mandatory)][string]$RequestedInstanceId,
        [Parameter(Mandatory)][int]$MaximumInstances
    )

    if ($Mode -eq 'open-or-activate') {
        return [pscustomobject]@{
            InstanceId = 'default'
            SessionName = $SessionPrefix
            Workspace = "$WorkspacePrefix-$SessionPrefix"
            WindowClass = "$ClassPrefix.$SessionPrefix"
        }
    }

    $existing = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($session in $Sessions) {
        if (-not [string]::IsNullOrWhiteSpace($session)) {
            [void]$existing.Add($session.Trim())
        }
    }

    $selected = $RequestedInstanceId
    if ($RequestedInstanceId -eq 'auto') {
        $selected = $null
        for ($index = 1; $index -le $MaximumInstances; $index++) {
            if (-not $existing.Contains("$SessionPrefix-$index")) {
                $selected = [string]$index
                break
            }
        }
        if (-not $selected) {
            throw "No free tmux instance remains beneath maximumInstances=$MaximumInstances."
        }
    }
    elseif ($RequestedInstanceId -notmatch '^[a-z0-9][a-z0-9-]*$') {
        throw "Unsafe instance ID: $RequestedInstanceId"
    }

    $sessionName = "$SessionPrefix-$selected"
    if ($existing.Contains($sessionName)) {
        throw "tmux instance '$sessionName' already exists; new-instance may not attach to it."
    }

    return [pscustomobject]@{
        InstanceId = $selected
        SessionName = $sessionName
        Workspace = "$WorkspacePrefix-$sessionName"
        WindowClass = "$ClassPrefix.$sessionName"
    }
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

if ($Operation -eq 'Launch' -and $null -ne $ExistingSessions -and $ExistingSessions.Count -gt 0) {
    throw '-ExistingSessions is allowed only with -Operation Plan.'
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $base = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\profiles\windows\tmux-new-instance\runs'
    }
    else {
        Join-Path ([IO.Path]::GetTempPath()) 'AgentSwitchboard/profiles/windows/tmux-new-instance/runs'
    }
    $runId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $OutputDirectory = Join-Path $base $runId
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

$resolvedWsl = $null
$resolvedWezTerm = $null
$sessionInventory = @()

if ($Operation -eq 'Plan') {
    $sessionInventory = @($ExistingSessions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
else {
    $resolvedWsl = Resolve-WslExecutable -RequestedPath $WslExe
    $resolvedWezTerm = Resolve-WezTermCli -RequestedPath $WezTermExe
    $inventory = Invoke-BoundedProcess -FilePath $resolvedWsl -ArgumentList @(
        '-d', $distribution, '-e', 'bash', '-lc',
        'if ! command -v tmux >/dev/null 2>&1; then echo __TMUX_MISSING__ >&2; exit 40; fi; tmux list-sessions -F "#S" 2>/dev/null || true'
    ) -Timeout $TimeoutSeconds
    if ($inventory.ExitCode -eq 40 -or $inventory.Stderr.Contains('__TMUX_MISSING__')) {
        throw "tmux is not installed inside WSL distribution '$distribution'."
    }
    if ($inventory.ExitCode -ne 0) {
        throw "Unable to inspect tmux sessions in '$distribution'. $($inventory.Stderr)"
    }
    $sessionInventory = @($inventory.Stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$identity = Get-SessionIdentity `
    -SessionPrefix $sessionPrefix `
    -WorkspacePrefix $workspacePrefix `
    -ClassPrefix $classPrefix `
    -Sessions $sessionInventory `
    -RequestedInstanceId $InstanceId `
    -MaximumInstances $maximumInstances

$sessionAlreadyExisted = $identity.SessionName -in $sessionInventory
$createSessionCommand = if ($sessionAlreadyExisted) {
    $null
}
else {
    "tmux new-session -d -s '$($identity.SessionName)' -n '$initialWindowName'"
}
$attachCommand = "exec tmux attach-session -t '$($identity.SessionName)'"
$wezTermArguments = @('start')
if ($Mode -eq 'new-instance') {
    $wezTermArguments += '--always-new-process'
}
$wezTermArguments += @(
    '--workspace', $identity.Workspace,
    '--class', $identity.WindowClass,
    '--',
    $(if ($resolvedWsl) { $resolvedWsl } else { 'wsl.exe' }),
    '-d', $distribution,
    '-e', 'bash', '-lc', $attachCommand
)

$plan = [ordered]@{
    schema = 'agentswitchboard.windows-profile-launch-plan.v2'
    mode = $Mode
    operation = $Operation
    distribution = $distribution
    instanceId = $identity.InstanceId
    sessionName = $identity.SessionName
    workspace = $identity.Workspace
    windowClass = $identity.WindowClass
    sessionAlreadyExisted = $sessionAlreadyExisted
    existingSessions = @($sessionInventory)
    allocationPolicy = if ($Mode -eq 'open-or-activate') { 'default-session-identity' } else { 'first-free-bounded-instance' }
    createSessionCommand = $createSessionCommand
    attachCommand = $attachCommand
    wezTermArguments = $wezTermArguments
    generatedEvidenceTracked = $false
    proofCeiling = 'Deterministic identity resolution and command construction. Launch mode additionally proves tmux session existence and WezTerm process acknowledgement, not window focus or operator acceptance.'
}
$planFileName = if ($Mode -eq 'new-instance') { 'tmux-new-instance-launch-plan.json' } else { 'windows-profile-launch-plan.json' }
$planPath = Join-Path $OutputDirectory $planFileName
Write-JsonArtifact -Value $plan -Path $planPath

if ($Operation -eq 'Plan') {
    $plan | ConvertTo-Json -Depth 12
    exit 0
}

$mutex = [Threading.Mutex]::new($false, 'Local\AgentSwitchboard.TmuxNewInstance')
$lockAcquired = $false
$createdSession = $false
try {
    $lockAcquired = $mutex.WaitOne([TimeSpan]::FromSeconds(10))
    if (-not $lockAcquired) {
        throw 'Another AgentSwitchboard launch is allocating a tmux session.'
    }

    if (-not $sessionAlreadyExisted) {
        $created = Invoke-BoundedProcess -FilePath $resolvedWsl -ArgumentList @(
            '-d', $distribution, '-e', 'bash', '-lc',
            "set -euo pipefail; $createSessionCommand; tmux has-session -t '$($identity.SessionName)'"
        ) -Timeout $TimeoutSeconds
        if ($created.ExitCode -ne 0) {
            throw "Unable to create tmux session '$($identity.SessionName)'. $($created.Stderr)"
        }
        $createdSession = $true
    }

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.FileName = $resolvedWezTerm
    foreach ($argument in $wezTermArguments) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }
    $process = [Diagnostics.Process]::Start($psi)
    if (-not $process) {
        throw 'WezTerm did not return a process handle.'
    }

    $result = [ordered]@{
        schema = 'agentswitchboard.windows-profile-launch-result.v2'
        status = 'launch-command-accepted'
        mode = $Mode
        distribution = $distribution
        sessionName = $identity.SessionName
        workspace = $identity.Workspace
        windowClass = $identity.WindowClass
        sessionAlreadyExisted = $sessionAlreadyExisted
        sessionCreated = $createdSession
        wezTermProcessId = $process.Id
        planPath = $planPath
        visibleWindowObserved = $false
        tmuxClientAttachedObserved = $false
        proofLevel = 'command-ack'
        proofCeiling = 'tmux session existence and WezTerm process acknowledgement only; focus, attachment, and operator acceptance remain live runtime proof.'
    }
    $resultFileName = if ($Mode -eq 'new-instance') { 'tmux-new-instance-launch-result.json' } else { 'windows-profile-launch-result.json' }
    $resultPath = Join-Path $OutputDirectory $resultFileName
    Write-JsonArtifact -Value $result -Path $resultPath
    $result | ConvertTo-Json -Depth 12
}
catch {
    if ($createdSession -and $resolvedWsl) {
        try {
            [void](Invoke-BoundedProcess -FilePath $resolvedWsl -ArgumentList @(
                '-d', $distribution, '-e', 'bash', '-lc',
                "tmux kill-session -t '$($identity.SessionName)' 2>/dev/null || true"
            ) -Timeout 15)
        }
        catch {}
    }
    throw
}
finally {
    if ($lockAcquired) {
        try { $mutex.ReleaseMutex() } catch {}
    }
    $mutex.Dispose()
}

exit 0
