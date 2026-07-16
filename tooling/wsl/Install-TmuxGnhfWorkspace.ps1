[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot "tmux-gnhf-workstation.example.json"),
    [switch]$Apply,
    [switch]$ForceRebootAck,
    [switch]$ReplaceExistingWezTermConfig,
    [string]$WslExe = "wsl.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "This bootstrap requires PowerShell 7. Open pwsh and rerun the command."
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function Resolve-ManifestRelativePath {
    param(
        [Parameter(Mandatory)][string]$BaseManifestPath,
        [Parameter(Mandatory)][string]$Value
    )

    if ([System.IO.Path]::IsPathRooted($Value)) {
        return [System.IO.Path]::GetFullPath($Value)
    }

    $baseDirectory = Split-Path -Parent $BaseManifestPath
    return [System.IO.Path]::GetFullPath((Join-Path $baseDirectory $Value))
}

function Convert-WindowsPathToWsl {
    param([Parameter(Mandatory)][string]$WindowsPath)

    $resolved = [System.IO.Path]::GetFullPath($WindowsPath)
    if ($resolved -notmatch '^(?<drive>[A-Za-z]):\\(?<rest>.*)$') {
        throw "Only drive-letter Windows paths can be mapped to WSL: $resolved"
    }

    $drive = $Matches.drive.ToLowerInvariant()
    $rest = $Matches.rest -replace '\\', '/'
    return "/mnt/$drive/$rest"
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 120
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.FileName = $FilePath
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $process.StandardInput.Close()

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill($true); $process.WaitForExit() } catch {}
        throw "Command timed out after ${TimeoutSeconds}s: $FilePath $($ArgumentList -join ' ')"
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
        Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
}

function Find-WezTermGui {
    $command = Get-Command wezterm-gui.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $searchRoots = @(
        (Join-Path $env:ProgramFiles "WezTerm"),
        (Join-Path $env:LOCALAPPDATA "Programs\WezTerm")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }

    foreach ($root in $searchRoots) {
        $candidate = Get-ChildItem -LiteralPath $root -Filter wezterm-gui.exe -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    return $null
}

function Install-WezTermIfMissing {
    param([bool]$PlanMode)

    $gui = Find-WezTermGui
    if ($gui) {
        return $gui
    }

    if ($PlanMode) {
        Write-Host "[PLAN] Install WezTerm with WinGet package wez.wezterm." -ForegroundColor Yellow
        return $null
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "WezTerm is missing and winget.exe is unavailable. Install WezTerm, then rerun."
    }

    $result = Invoke-BoundedProcess -FilePath $winget.Source -ArgumentList @(
        "install", "--id", "wez.wezterm", "--exact", "--source", "winget",
        "--accept-source-agreements", "--accept-package-agreements"
    ) -TimeoutSeconds 300
    if ($result.ExitCode -ne 0) {
        throw "WinGet failed to install WezTerm. $($result.Output)"
    }

    $gui = Find-WezTermGui
    if (-not $gui) {
        throw "WezTerm installation completed, but wezterm-gui.exe was not found."
    }
    return $gui
}

$resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) {
    throw "Unsupported tmux/GNHF manifest schemaVersion: $($manifest.schemaVersion). Expected 1."
}

$distribution = [string]$manifest.distribution
$sessionName = [string]$manifest.workspace.sessionName
$keepAliveProcessName = [string]$manifest.workspace.keepAliveProcessName
if ($distribution -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Unsafe WSL distribution name: $distribution"
}
if ($sessionName -notmatch '^[A-Za-z0-9_-]+$') {
    throw "Unsafe tmux session name: $sessionName"
}
if ($keepAliveProcessName -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Unsafe keepalive process name: $keepAliveProcessName"
}

$planMode = -not $Apply
$installRootText = [Environment]::ExpandEnvironmentVariables([string]$manifest.workspace.installRoot)
$installRoot = [System.IO.Path]::GetFullPath($installRootText)
$wslManifestPath = Resolve-ManifestRelativePath -BaseManifestPath $resolvedManifestPath -Value ([string]$manifest.wslBootstrapManifest)
$wslInstallerPath = Join-Path $PSScriptRoot "Install-AgentSwitchboardWsl.ps1"
$gnhfBootstrapPath = Join-Path $PSScriptRoot "scripts\configure-gnhf-workspace.sh"
$wezTermTemplatePath = Join-Path $PSScriptRoot "templates\wezterm-tmux.lua"

foreach ($requiredPath in @($wslManifestPath, $wslInstallerPath, $gnhfBootstrapPath, $wezTermTemplatePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required bootstrap file is missing: $requiredPath"
    }
}

Write-Section "AgentSwitchboard tmux + GNHF Workstation"
Write-Host "Mode:         $(if ($planMode) { 'PLAN' } else { 'APPLY' })"
Write-Host "Distribution: $distribution"
Write-Host "tmux session: $sessionName"
Write-Host "Manifest:     $resolvedManifestPath"
Write-Host "Install root: $installRoot"

Write-Section "WSL and tmux bootstrap"
$wslArguments = @{
    ManifestPath = $wslManifestPath
    WslExe = $WslExe
}
if ($planMode) {
    $wslArguments.PlanOnly = $true
}
if ($ForceRebootAck) {
    $wslArguments.ForceRebootAck = $true
}
& $wslInstallerPath @wslArguments

if ($planMode) {
    Write-Section "GNHF and persistent workspace plan"
    [void](Install-WezTermIfMissing -PlanMode $true)
    Write-Host "[PLAN] Verify or install checksum-validated official Node LTS inside $distribution." -ForegroundColor Yellow
    Write-Host "[PLAN] Install GNHF from its published npm package and configure its upstream-supported config.yml." -ForegroundColor Yellow
    Write-Host "[PLAN] Install the default agent inside WSL and create bounded gnhf-safe worktree wrapper." -ForegroundColor Yellow
    Write-Host "[PLAN] Render a WezTerm config that enters tmux automatically without nesting tmux." -ForegroundColor Yellow
    Write-Host "[PLAN] Create idempotent Start, Status, and destructive Stop scripts plus an optional desktop shortcut." -ForegroundColor Yellow
    return [pscustomobject]@{
        schemaVersion = 1
        status = "plan-only"
        distribution = $distribution
        sessionName = $sessionName
        installRoot = $installRoot
        proof = [ordered]@{
            installation = $false
            configuration = $false
            tmuxPersistence = $false
            authentication = $false
        }
    }
}

Write-Section "Configure GNHF inside WSL"
$configJson = $manifest | ConvertTo-Json -Depth 12 -Compress
$configEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($configJson))
$gnhfBootstrapWslPath = Convert-WindowsPathToWsl -WindowsPath $gnhfBootstrapPath
$gnhfCommand = "printf '%s' '$configEncoded' | base64 -d | bash '$gnhfBootstrapWslPath'"
$gnhfResult = Invoke-BoundedProcess -FilePath $WslExe -ArgumentList @(
    "-d", $distribution, "-e", "bash", "-lc", $gnhfCommand
) -TimeoutSeconds 900
Write-Host $gnhfResult.Output
if ($gnhfResult.ExitCode -ne 0) {
    throw "GNHF configuration failed with exit code $($gnhfResult.ExitCode)."
}

Write-Section "Install persistent Windows launcher"
$wezTermGui = Install-WezTermIfMissing -PlanMode $false
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
$stateRoot = Join-Path $installRoot "state"
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

$wezTermTemplate = Get-Content -LiteralPath $wezTermTemplatePath -Raw
$wezTermConfig = $wezTermTemplate.
    Replace("__DISTRO__", $distribution).
    Replace("__SESSION__", $sessionName)
$wezTermConfigPath = Join-Path $HOME ".wezterm.lua"
$managedMarker = "-- AgentSwitchboard managed tmux/GNHF configuration"

if (Test-Path -LiteralPath $wezTermConfigPath -PathType Leaf) {
    $existingConfig = Get-Content -LiteralPath $wezTermConfigPath -Raw
    if (-not $existingConfig.Contains($managedMarker) -and -not $ReplaceExistingWezTermConfig) {
        $proposedPath = Join-Path $installRoot "wezterm.agent-switchboard.proposed.lua"
        Set-Content -LiteralPath $proposedPath -Value $wezTermConfig -Encoding utf8NoBOM
        throw "Existing unmanaged WezTerm config was preserved. Review '$proposedPath', then rerun with -ReplaceExistingWezTermConfig if replacement is intended."
    }

    $backupPath = "$wezTermConfigPath.agent-switchboard-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $wezTermConfigPath -Destination $backupPath -Force
    Write-Host "[PASS] WezTerm config backup: $backupPath" -ForegroundColor Green
}
Set-Content -LiteralPath $wezTermConfigPath -Value $wezTermConfig -Encoding utf8NoBOM

$startScriptPath = Join-Path $installRoot "Start-TmuxGnhfWorkspace.ps1"
$statusScriptPath = Join-Path $installRoot "Get-TmuxGnhfWorkspaceStatus.ps1"
$stopScriptPath = Join-Path $installRoot "Stop-TmuxGnhfWorkspace.ps1"
$pidFilePath = Join-Path $stateRoot "wsl-keepalive.pid"

$startScriptTemplate = @'
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Distribution = '__DISTRO__'
$SessionName = '__SESSION__'
$KeepAliveName = '__KEEPALIVE__'
$WezTermGui = '__WEZTERM_GUI__'
$PidFile = '__PID_FILE__'

function Test-OwnedKeepAlive {
    if (-not (Test-Path -LiteralPath $PidFile -PathType Leaf)) { return $false }
    $savedPid = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($savedPid -notmatch '^\d+$') { return $false }
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid" -ErrorAction SilentlyContinue
    if (-not $process) { return $false }
    return ($process.Name -eq 'wsl.exe' -and $process.CommandLine -like "*$KeepAliveName*")
}

if (-not (Test-OwnedKeepAlive)) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.FileName = "$env:SystemRoot\System32\wsl.exe"
    foreach ($argument in @('-d', $Distribution, '-e', 'bash', '-lc', "exec -a $KeepAliveName sleep infinity")) {
        [void]$psi.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::Start($psi)
    Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ascii
    Start-Sleep -Seconds 2
}

& "$env:SystemRoot\System32\wsl.exe" -d $Distribution -e bash -lc "tmux has-session -t '$SessionName' 2>/dev/null || tmux new-session -d -s '$SessionName'"
if ($LASTEXITCODE -ne 0) { throw "Unable to create or verify tmux session '$SessionName'." }
Start-Process -FilePath $WezTermGui | Out-Null
'@
$startScript = $startScriptTemplate.
    Replace('__DISTRO__', $distribution).
    Replace('__SESSION__', $sessionName).
    Replace('__KEEPALIVE__', $keepAliveProcessName).
    Replace('__WEZTERM_GUI__', $wezTermGui.Replace("'", "''")).
    Replace('__PID_FILE__', $pidFilePath.Replace("'", "''"))

$statusScriptTemplate = @'
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Distribution = '__DISTRO__'
$SessionName = '__SESSION__'
$KeepAliveName = '__KEEPALIVE__'
$PidFile = '__PID_FILE__'

$keepAlive = $false
if (Test-Path -LiteralPath $PidFile -PathType Leaf) {
    $savedPid = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($savedPid -match '^\d+$') {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid" -ErrorAction SilentlyContinue
        $keepAlive = [bool]($process -and $process.Name -eq 'wsl.exe' -and $process.CommandLine -like "*$KeepAliveName*")
    }
}

$tmuxOutput = & "$env:SystemRoot\System32\wsl.exe" -d $Distribution -e bash -lc "tmux has-session -t '$SessionName' 2>/dev/null && tmux list-windows -t '$SessionName' -F '#{window_index}:#{window_name}:#{window_active}' || true"
$sessionAvailable = ($LASTEXITCODE -eq 0 -and [bool]($tmuxOutput -join ''))

[pscustomobject]@{
    schemaVersion = 1
    distribution = $Distribution
    sessionName = $SessionName
    keepAliveRunning = $keepAlive
    sessionAvailable = $sessionAvailable
    windows = @($tmuxOutput)
    proof = [ordered]@{
        commandAck = $sessionAvailable
        behaviorObserved = $false
        persistenceObserved = $false
        authentication = $false
    }
}
'@
$statusScript = $statusScriptTemplate.
    Replace('__DISTRO__', $distribution).
    Replace('__SESSION__', $sessionName).
    Replace('__KEEPALIVE__', $keepAliveProcessName).
    Replace('__PID_FILE__', $pidFilePath.Replace("'", "''"))

$stopScriptTemplate = @'
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Distribution = '__DISTRO__'
$SessionName = '__SESSION__'
$KeepAliveName = '__KEEPALIVE__'
$PidFile = '__PID_FILE__'

if (-not $PSCmdlet.ShouldProcess("tmux session '$SessionName' and its WSL keepalive", "Terminate persistent coding workspace")) {
    return
}

& "$env:SystemRoot\System32\wsl.exe" -d $Distribution -e bash -lc "tmux kill-session -t '$SessionName' 2>/dev/null || true"
if (Test-Path -LiteralPath $PidFile -PathType Leaf) {
    $savedPid = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($savedPid -match '^\d+$') {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid" -ErrorAction SilentlyContinue
        if ($process -and $process.Name -eq 'wsl.exe' -and $process.CommandLine -like "*$KeepAliveName*") {
            Stop-Process -Id ([int]$savedPid) -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}
'@
$stopScript = $stopScriptTemplate.
    Replace('__DISTRO__', $distribution).
    Replace('__SESSION__', $sessionName).
    Replace('__KEEPALIVE__', $keepAliveProcessName).
    Replace('__PID_FILE__', $pidFilePath.Replace("'", "''"))

Set-Content -LiteralPath $startScriptPath -Value $startScript -Encoding utf8NoBOM
Set-Content -LiteralPath $statusScriptPath -Value $statusScript -Encoding utf8NoBOM
Set-Content -LiteralPath $stopScriptPath -Value $stopScript -Encoding utf8NoBOM

$shortcutPath = $null
if ([bool]$manifest.workspace.createDesktopShortcut) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop "$($manifest.workspace.shortcutName).lnk"
    $pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $pwsh
    $shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startScriptPath`""
    $shortcut.WorkingDirectory = $HOME
    $shortcut.IconLocation = "$wezTermGui,0"
    $shortcut.Description = "Open WezTerm and attach to persistent tmux session $sessionName"
    $shortcut.Save()
}

Write-Section "Automated validation"
& $startScriptPath
Start-Sleep -Seconds 3
$status = & $statusScriptPath
if (-not $status.keepAliveRunning -or -not $status.sessionAvailable) {
    throw "Workspace start validation failed: $($status | ConvertTo-Json -Depth 6 -Compress)"
}

$summaryPath = Join-Path $stateRoot "setup-summary.json"
$summary = [ordered]@{
    schemaVersion = 1
    completedAt = (Get-Date).ToString('o')
    status = "completed"
    distribution = $distribution
    sessionName = $sessionName
    installRoot = $installRoot
    wezTermConfigPath = $wezTermConfigPath
    startScript = $startScriptPath
    statusScript = $statusScriptPath
    stopScript = $stopScriptPath
    shortcut = $shortcutPath
    gnhfOutput = $gnhfResult.Output
    validation = $status
    proof = [ordered]@{
        installation = $true
        configuration = $true
        commandAck = $true
        behaviorObserved = $false
        tmuxPersistence = $false
        authentication = $false
        hostedAgentResponse = $false
    }
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM

Write-Section "Setup complete"
Write-Host "[PASS] Start:   $startScriptPath" -ForegroundColor Green
Write-Host "[PASS] Status:  $statusScriptPath" -ForegroundColor Green
Write-Host "[PASS] Stop:    $stopScriptPath" -ForegroundColor Green
Write-Host "[PASS] Summary: $summaryPath" -ForegroundColor Green
if ($shortcutPath) {
    Write-Host "[PASS] Shortcut: $shortcutPath" -ForegroundColor Green
}
Write-Host "GNHF is configured but not authenticated automatically." -ForegroundColor Yellow
Write-Host "Live detach/reopen persistence still requires operator observation." -ForegroundColor Yellow
return [pscustomobject]$summary
