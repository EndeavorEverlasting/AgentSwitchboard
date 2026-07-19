<#
.SYNOPSIS
    Canonical AgentSwitchboard WezTerm open-or-activate launcher.
.DESCRIPTION
    Queries WezTerm mux state before deciding whether to activate an existing
    managed workspace pane or start a new managed GUI window. This is the single
    authoritative launcher consumed by SysAdminSuite and desktop shortcuts.

    DOCTRINE: This launcher must NEVER use --always-new-process. That flag
    bypasses WezTerm's delegation to an existing GUI and deliberately starts
    another GUI process, causing duplicate windows. The correct pattern is:
    inventory first, decide second. Query WezTerm's own mux state via
    'wezterm cli list --format json' and 'wezterm cli list-clients --format json'
    before any launch decision.
.PARAMETER Workspace
    The managed WezTerm workspace name. Default: 'agent-switchboard'.
.PARAMETER Distro
    WSL distribution to enter. Default: 'Ubuntu'.
.PARAMETER TmuxSession
    tmux session to attach. Default: 'dev'.
.PARAMETER DryRun
    Return the decision without launching anything.
.PARAMETER OutputPath
    Write the versioned result JSON to this path.
#>
[CmdletBinding()]
param(
    [string]$Workspace = 'agent-switchboard',
    [string]$Distro = 'Ubuntu',
    [string]$TmuxSession = 'dev',
    [switch]$DryRun,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$script:LauncherId = 'agentswitchboard-wezterm-launcher'
$script:SchemaVersion = 'agentswitchboard-wezterm-launch-result/v1'
$script:SourceCommit = try { (git -C $PSScriptRoot rev-parse HEAD 2>$null).Trim() } catch { 'unknown' }

function Get-WezTermCli {
    $candidates = @(
        (Get-Command wezterm.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        (Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    return @($candidates)[0]
}

function Get-WezTermGuiPath {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'WezTerm\wezterm-gui.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm-gui.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    return @($candidates)[0]
}

function Get-WezTermVersion {
    param([string]$CliPath)
    if (-not $CliPath) { return $null }
    try {
        $output = & $CliPath -V 2>&1 | Select-Object -First 1
        if ($output -match 'wezterm\s+(\S+)') { return $Matches[1] }
        return "$output"
    } catch { return $null }
}

function Get-WezTermClients {
    param([string]$CliPath)
    if (-not $CliPath) { return @() }
    try {
        $json = & $CliPath cli list-clients --format json 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return @() }
        return ($json | ConvertFrom-Json)
    } catch { return @() }
}

function Get-WezTermPanes {
    param([string]$CliPath)
    if (-not $CliPath) { return @() }
    try {
        $json = & $CliPath cli list --format json 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return @() }
        return ($json | ConvertFrom-Json)
    } catch { return @() }
}

function Get-WezTermWindows {
    param([string]$CliPath)
    if (-not $CliPath) { return @() }
    try {
        $json = & $CliPath cli list --format json 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return @() }
        $panes = ($json | ConvertFrom-Json)
        $windows = @{}
        foreach ($pane in $panes) {
            $wid = $pane.window_id
            if (-not $windows.ContainsKey($wid)) {
                $windows[$wid] = [pscustomobject]@{
                    window_id = $wid
                    workspace = $pane.workspace
                    pane_count = 0
                    panes = @()
                }
            }
            $windows[$wid].pane_count++
            $windows[$wid].panes += $pane
        }
        return @($windows.Values)
    } catch { return @() }
}

function Get-GuiProcessCount {
    return @(Get-Process -Name wezterm-gui -ErrorAction SilentlyContinue).Count
}

function Get-TmuxState {
    param([string]$Distro, [string]$Session)
    $result = [pscustomobject]@{
        server_available = $false
        session_exists = $false
        attached_clients = 0
        window_count = 0
        windows = @()
    }
    try {
        & wsl.exe -d $Distro -- tmux list-sessions 2>$null | Out-Null
        $result.server_available = $LASTEXITCODE -eq 0
    } catch { return $result }
    if (-not $result.server_available) { return $result }
    try {
        & wsl.exe -d $Distro -- tmux has-session -t $Session 2>$null
        $result.session_exists = $LASTEXITCODE -eq 0
    } catch { return $result }
    if (-not $result.session_exists) { return $result }
    try {
        $clients = & wsl.exe -d $Distro -- tmux list-clients -t $Session 2>$null
        $result.attached_clients = @($clients).Count
    } catch {}
    try {
        $windows = & wsl.exe -d $Distro -- tmux list-windows -t $Session 2>$null
        $result.window_count = @($windows).Count
        $result.windows = @($windows)
    } catch {}
    return $result
}

function New-LaunchResult {
    param(
        [string]$Decision,
        [string]$Outcome,
        [string[]]$ReasonCodes = @(),
        [string]$Message,
        [int]$GuiProcessesBefore,
        [int]$GuiProcessesAfter,
        [int]$ManagedWindowsBefore,
        [int]$ManagedWindowsAfter,
        [int]$ClientsBefore,
        [int]$ClientsAfter,
        [string]$TargetPaneId = '',
        [bool]$DuplicateDetected = $false,
        [bool]$TmuxSessionsPreserved = $false
    )
    [pscustomobject]@{
        schema_version = $script:SchemaVersion
        launcher_id = $script:LauncherId
        source_commit = $script:SourceCommit
        operation = 'open-or-activate'
        outcome = $Outcome
        decision = $Decision
        reason_codes = $ReasonCodes
        message = $Message
        workspace = $Workspace
        distro = $Distro
        tmux_session = $TmuxSession
        target_pane_id = $TargetPaneId
        wezterm_version = $script:WezTermVersion
        clients_before = $ClientsBefore
        clients_after = $ClientsAfter
        managed_windows_before = $ManagedWindowsBefore
        managed_windows_after = $ManagedWindowsAfter
        gui_processes_before = $GuiProcessesBefore
        gui_processes_after = $GuiProcessesAfter
        tmux_server_available = $script:TmuxState.server_available
        tmux_session_exists = $script:TmuxState.session_exists
        tmux_attached_clients = $script:TmuxState.attached_clients
        tmux_window_count = $script:TmuxState.window_count
        duplicate_detected = $DuplicateDetected
        tmux_sessions_preserved = $TmuxSessionsPreserved
        new_gui_started = ($Decision -eq 'started_new_gui')
        new_managed_window_started = ($Decision -eq 'started_managed_window')
        existing_pane_activated = ($Decision -eq 'activated_existing')
        dry_run = [bool]$DryRun
        timestamp = (Get-Date -Format 'o')
    }
}

# --- Main ---

$cliPath = Get-WezTermCli
$guiPath = Get-WezTermGuiPath
$script:WezTermVersion = Get-WezTermVersion -CliPath $cliPath

# E: CLI unavailable
if (-not $cliPath) {
    $result = New-LaunchResult -Decision 'cli_unavailable' -Outcome 'failure' `
        -ReasonCodes @('wezterm-cli-not-found') `
        -Message "WezTerm CLI not found. Cannot proceed." `
        -GuiProcessesBefore 0 -GuiProcessesAfter 0 `
        -ManagedWindowsBefore 0 -ManagedWindowsAfter 0 `
        -ClientsBefore 0 -ClientsAfter 0
    if ($OutputPath) { $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
    return $result
}

# Capture pre-state
$guiBefore = Get-GuiProcessCount
$clientsBefore = Get-WezTermClients -CliPath $cliPath
$panesBefore = Get-WezTermPanes -CliPath $cliPath
$windowsBefore = Get-WezTermWindows -CliPath $cliPath
$script:TmuxState = Get-TmuxState -Distro $Distro -Session $TmuxSession

# Find managed workspace panes
$managedWindows = @($windowsBefore | Where-Object { $_.workspace -eq $Workspace })
$managedPanes = @($panesBefore | Where-Object { $_.workspace -eq $Workspace })

# D: Multiple managed windows
if ($managedWindows.Count -gt 1) {
    $result = New-LaunchResult -Decision 'action-required' -Outcome 'action-required' `
        -ReasonCodes @('duplicate-managed-wezterm-windows') `
        -Message "Found $($managedWindows.Count) managed windows in workspace '$Workspace'. Manual review required." `
        -GuiProcessesBefore $guiBefore -GuiProcessesAfter $guiBefore `
        -ManagedWindowsBefore $managedWindows.Count -ManagedWindowsAfter $managedWindows.Count `
        -ClientsBefore $clientsBefore.Count -ClientsAfter $clientsBefore.Count `
        -DuplicateDetected $true -TmuxSessionsPreserved $true
    if ($OutputPath) { $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
    return $result
}

# A: Existing managed workspace with exactly one window - activate
if ($managedWindows.Count -eq 1 -and $managedPanes.Count -ge 1) {
    $targetPane = $managedPanes[0]
    if (-not $DryRun -and $cliPath) {
        try {
            & $CliPath cli activate-pane --pane-id $targetPane.pane_id 2>$null
        } catch {
            # Activation may not work headlessly; record but don't fail
        }
    }
    $result = New-LaunchResult -Decision 'activated_existing' -Outcome 'success' `
        -Message "Activated existing managed pane $($targetPane.pane_id) in workspace '$Workspace'." `
        -GuiProcessesBefore $guiBefore -GuiProcessesAfter $guiBefore `
        -ManagedWindowsBefore 1 -ManagedWindowsAfter 1 `
        -ClientsBefore $clientsBefore.Count -ClientsAfter $clientsBefore.Count `
        -TargetPaneId "$($targetPane.pane_id)" -TmuxSessionsPreserved $true
    if ($OutputPath) { $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
    return $result
}

# B/C: No managed workspace - need to start
# Ensure tmux session exists
if (-not $script:TmuxState.session_exists) {
    if (-not $DryRun) {
        & wsl.exe -d $Distro --exec bash -lc "tmux new-session -d -s $TmuxSession" 2>$null
        if ($LASTEXITCODE -ne 0) {
            $result = New-LaunchResult -Decision 'failure' -Outcome 'failure' `
                -ReasonCodes @('tmux-session-create-failed') `
                -Message "Could not create tmux session '$TmuxSession' in distro '$Distro'." `
                -GuiProcessesBefore $guiBefore -GuiProcessesAfter $guiBefore `
                -ManagedWindowsBefore 0 -ManagedWindowsAfter 0 `
                -ClientsBefore $clientsBefore.Count -ClientsAfter $clientsBefore.Count
            if ($OutputPath) { $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
            return $result
        }
    }
}

if ($DryRun) {
    $result = New-LaunchResult -Decision 'would_start' -Outcome 'success' `
        -Message "Dry run: would start managed window in workspace '$Workspace'." `
        -GuiProcessesBefore $guiBefore -GuiProcessesAfter $guiBefore `
        -ManagedWindowsBefore 0 -ManagedWindowsAfter 0 `
        -ClientsBefore $clientsBefore.Count -ClientsAfter $clientsBefore.Count `
        -TmuxSessionsPreserved $true
    if ($OutputPath) { $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
    return $result
}

# C: WezTerm not running - start new GUI
# B: WezTerm running but no managed workspace - create new window in existing GUI
$weztermRunning = $guiBefore -gt 0

if ($weztermRunning) {
    # B: Existing GUI, no managed workspace - ask it to create a window in the managed workspace
    try {
        & $CliPath cli spawn --workspace $Workspace -- wsl.exe -d $Distro -e bash -lc "exec tmux new-session -A -s $TmuxSession" 2>$null
    } catch {
        # Fallback: start a new GUI with the workspace
        if ($guiPath) {
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $guiPath
            $startInfo.UseShellExecute = $true
            [void]$startInfo.ArgumentList.Add('start')
            [void]$startInfo.ArgumentList.Add('--workspace')
            [void]$startInfo.ArgumentList.Add($Workspace)
            [void][Diagnostics.Process]::Start($startInfo)
        }
    }
    $decision = 'started_managed_window'
    $message = "Created managed window in workspace '$Workspace' via existing GUI."
} else {
    # C: No GUI running - start new GUI
    if (-not $guiPath) {
        $result = New-LaunchResult -Decision 'failure' -Outcome 'failure' `
            -ReasonCodes @('wezterm-gui-not-found') `
            -Message "WezTerm GUI executable not found." `
            -GuiProcessesBefore 0 -GuiProcessesAfter 0 `
            -ManagedWindowsBefore 0 -ManagedWindowsAfter 0 `
            -ClientsBefore 0 -ClientsAfter 0
        if ($OutputPath) { $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
        return $result
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $guiPath
    $startInfo.UseShellExecute = $true
    [void]$startInfo.ArgumentList.Add('start')
    [void]$startInfo.ArgumentList.Add('--workspace')
    [void]$startInfo.ArgumentList.Add($Workspace)
    [void][Diagnostics.Process]::Start($startInfo)
    $decision = 'started_new_gui'
    $message = "Started new WezTerm GUI with workspace '$Workspace'."
}

# Brief settle time for GUI to register
Start-Sleep -Seconds 2

$guiAfter = Get-GuiProcessCount
$clientsAfter = Get-WezTermClients -CliPath $cliPath
$panesAfter = Get-WezTermPanes -CliPath $cliPath
$managedAfter = @($panesAfter | Where-Object { $_.workspace -eq $Workspace })

$result = New-LaunchResult -Decision $decision -Outcome 'success' `
    -Message $message `
    -GuiProcessesBefore $guiBefore -GuiProcessesAfter $guiAfter `
    -ManagedWindowsBefore 0 -ManagedWindowsAfter $managedAfter.Count `
    -ClientsBefore $clientsBefore.Count -ClientsAfter $clientsAfter.Count `
    -TmuxSessionsPreserved $true
if ($OutputPath) { $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
return $result
