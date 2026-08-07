[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Distribution = 'Ubuntu',

    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$SessionName = 'dev',

    [ValidateRange(10, 180)]
    [int]$TimeoutSeconds = 45,

    [string]$OutputRoot,

    [switch]$SurfaceOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-NativeText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace(([char]0).ToString(), [string]::Empty)
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [ValidateRange(1, 300)][int]$ProcessTimeoutSeconds = 30
    )

    $result = [ordered]@{
        ExitCode = $null
        TimedOut = $false
        Stdout = ''
        Stderr = ''
        StartError = $null
    }

    try {
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

        if (-not $process.WaitForExit($ProcessTimeoutSeconds * 1000)) {
            $result.TimedOut = $true
            try { $process.Kill($true) } catch {}
            try { $process.WaitForExit(1000) } catch {}
        }
        else {
            $result.ExitCode = $process.ExitCode
        }

        $result.Stdout = (ConvertFrom-NativeText -Value ($stdoutTask.GetAwaiter().GetResult())).Trim()
        $result.Stderr = (ConvertFrom-NativeText -Value ($stderrTask.GetAwaiter().GetResult())).Trim()
    }
    catch {
        $result.StartError = $_.Exception.Message
        $result.Stderr = $_.Exception.Message
    }

    return [pscustomobject]$result
}

function Refresh-WindowsPath {
    $segments = [Collections.Generic.List[string]]::new()
    foreach ($source in @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User'),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links' })
    )) {
        if ([string]::IsNullOrWhiteSpace($source)) { continue }
        foreach ($entry in ($source -split ';')) {
            $trimmed = $entry.Trim()
            if ($trimmed -and -not $segments.Contains($trimmed)) {
                [void]$segments.Add($trimmed)
            }
        }
    }
    $env:Path = $segments -join ';'
}

function Resolve-WezTermCli {
    Refresh-WindowsPath
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
    return $null
}

function Write-Proof {
    param([Parameter(Mandatory)][hashtable]$Proof)
    $Proof.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $Proof | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:ProofPath -Encoding utf8NoBOM
}

$runId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $base = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\tmux-live-proof\runs'
    }
    else {
        Join-Path ([IO.Path]::GetTempPath()) 'AgentSwitchboard/tmux-live-proof/runs'
    }
    $OutputRoot = Join-Path $base $runId
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$null = New-Item -ItemType Directory -Path $OutputRoot -Force
$script:ProofPath = Join-Path $OutputRoot 'tmux-live-proof.json'

$proof = [ordered]@{
    schema = 'agentswitchboard.tmux-live-proof.v1'
    runId = $runId
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    completedAt = $null
    status = 'running'
    distribution = $Distribution
    sessionName = $SessionName
    powershell = [ordered]@{
        status = 'reused'
        version = [string]$PSVersionTable.PSVersion
        executable = (Get-Process -Id $PID).Path
    }
    wezterm = $null
    wsl = $null
    tmux = $null
    session = $null
    launch = $null
    tmuxClientAttachedObserved = $false
    tmuxClientEvidence = @()
    proofLevel = 'not-proven'
    proofCeiling = 'No runtime proof has been observed yet.'
    evidencePath = $script:ProofPath
    error = $null
}

try {
    if ($SurfaceOnly) {
        $proof.status = 'surface-passed'
        $proof.proofLevel = 'surface-only'
        $proof.proofCeiling = 'Proves the repository-owned tmux live-proof entrypoint loads and can emit its evidence contract without workstation mutation.'
        Write-Proof -Proof $proof
        Write-Host '[PASS] AgentSwitchboard tmux live-proof surface loaded.' -ForegroundColor Green
        Write-Host "Evidence: $script:ProofPath"
        exit 0
    }

    if ($env:OS -ne 'Windows_NT') {
        throw 'AgentSwitchboard tmux live proof must run on Windows because it launches WSL through WezTerm.'
    }

    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' AgentSwitchboard tmux auto-config + live proof' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host "Distribution: $Distribution"
    Write-Host "Session:      $SessionName"
    Write-Host "Evidence:     $script:ProofPath"

    $wezTermPath = Resolve-WezTermCli
    $wezTermState = 'reused'
    if (-not $wezTermPath) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $winget) {
            throw 'WezTerm is missing and WinGet is unavailable. Install WezTerm, then rerun Open-AgentSwitchboard-Tmux.cmd.'
        }
        Write-Host '[INSTALL] WezTerm is missing; installing it with WinGet.' -ForegroundColor Yellow
        & $winget.Source install --id wez.wezterm --exact --source winget --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet could not install WezTerm. Exit code: $LASTEXITCODE"
        }
        Refresh-WindowsPath
        $wezTermPath = Resolve-WezTermCli
        $wezTermState = 'installed'
    }
    if (-not $wezTermPath) {
        throw 'WezTerm installation completed, but wezterm.exe is still not resolvable.'
    }
    $wezVersion = Invoke-BoundedProcess -FilePath $wezTermPath -ArgumentList @('--version') -ProcessTimeoutSeconds 30
    if ($wezVersion.TimedOut -or $wezVersion.ExitCode -ne 0) {
        throw "WezTerm version probe failed. stderr=$($wezVersion.Stderr)"
    }
    $proof.wezterm = [ordered]@{
        status = $wezTermState
        executable = $wezTermPath
        version = ($wezVersion.Stdout -split "`r?`n" | Select-Object -First 1)
    }
    Write-Host "[$($wezTermState.ToUpperInvariant())] WezTerm: $wezTermPath" -ForegroundColor Green

    $wslPath = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32\wsl.exe' } else { $null }
    if (-not $wslPath -or -not (Test-Path -LiteralPath $wslPath -PathType Leaf)) {
        $wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
        if ($wslCommand) { $wslPath = $wslCommand.Source }
    }
    if (-not $wslPath -or -not (Test-Path -LiteralPath $wslPath -PathType Leaf)) {
        throw 'WSL is not installed. Run Repair-Technician-WSL-Ubuntu.cmd, then rerun this command.'
    }

    $distributionProbe = Invoke-BoundedProcess -FilePath $wslPath -ArgumentList @('--list', '--quiet') -ProcessTimeoutSeconds 30
    if ($distributionProbe.TimedOut -or $distributionProbe.ExitCode -ne 0) {
        throw "WSL could not enumerate distributions. stderr=$($distributionProbe.Stderr)"
    }
    $distributions = @($distributionProbe.Stdout -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($Distribution -notin $distributions) {
        throw "WSL distribution '$Distribution' is not initialized. Run Repair-Technician-WSL-Ubuntu.cmd, then rerun this command."
    }
    $proof.wsl = [ordered]@{
        status = 'reused'
        executable = $wslPath
        distribution = $Distribution
    }
    Write-Host "[REUSED] WSL distribution: $Distribution" -ForegroundColor Green

    $tmuxProbe = Invoke-BoundedProcess -FilePath $wslPath -ArgumentList @(
        '-d', $Distribution, '--', 'bash', '-lc',
        'command -v tmux >/dev/null 2>&1 && command -v tmux && tmux -V'
    ) -ProcessTimeoutSeconds 30

    $tmuxState = 'reused'
    if ($tmuxProbe.TimedOut -or $tmuxProbe.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($tmuxProbe.Stdout)) {
        Write-Host "[INSTALL] tmux is missing in $Distribution; installing it through the distribution's root user." -ForegroundColor Yellow
        $tmuxInstall = Invoke-BoundedProcess -FilePath $wslPath -ArgumentList @(
            '-d', $Distribution, '-u', 'root', '--', 'bash', '-lc',
            'set -euo pipefail; apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y tmux; command -v tmux; tmux -V'
        ) -ProcessTimeoutSeconds 180
        if ($tmuxInstall.TimedOut -or $tmuxInstall.ExitCode -ne 0) {
            throw "tmux installation failed. exit=$($tmuxInstall.ExitCode) timeout=$($tmuxInstall.TimedOut) stderr=$($tmuxInstall.Stderr)"
        }
        $tmuxProbe = $tmuxInstall
        $tmuxState = 'installed'
    }

    $tmuxLines = @($tmuxProbe.Stdout -split "`r?`n" | Where-Object { $_ })
    $tmuxPath = $tmuxLines | Where-Object { $_ -match '^/' } | Select-Object -First 1
    $tmuxVersion = $tmuxLines | Where-Object { $_ -match '^tmux\s' } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($tmuxPath) -or [string]::IsNullOrWhiteSpace($tmuxVersion)) {
        throw "tmux was invoked but its path/version evidence was incomplete. stdout=$($tmuxProbe.Stdout)"
    }
    $proof.tmux = [ordered]@{
        status = $tmuxState
        executable = $tmuxPath
        version = $tmuxVersion
    }
    Write-Host "[$($tmuxState.ToUpperInvariant())] $tmuxVersion at $tmuxPath" -ForegroundColor Green

    $sessionProbe = Invoke-BoundedProcess -FilePath $wslPath -ArgumentList @(
        '-d', $Distribution, '--', 'bash', '-lc',
        "tmux has-session -t '$SessionName' 2>/dev/null"
    ) -ProcessTimeoutSeconds 15
    $sessionState = 'reused'
    if ($sessionProbe.ExitCode -ne 0) {
        $createSession = Invoke-BoundedProcess -FilePath $wslPath -ArgumentList @(
            '-d', $Distribution, '--', 'bash', '-lc',
            "set -euo pipefail; tmux new-session -d -s '$SessionName' -n shell; tmux has-session -t '$SessionName'"
        ) -ProcessTimeoutSeconds 30
        if ($createSession.TimedOut -or $createSession.ExitCode -ne 0) {
            throw "Unable to create tmux session '$SessionName'. stderr=$($createSession.Stderr)"
        }
        $sessionState = 'created'
    }
    $proof.session = [ordered]@{
        status = $sessionState
        name = $SessionName
    }
    Write-Host "[$($sessionState.ToUpperInvariant())] tmux session: $SessionName" -ForegroundColor Green

    $attachCommand = "exec tmux attach-session -t '$SessionName'"
    $workspace = "agentswitchboard-$SessionName"
    $windowClass = "org.agentswitchboard.$SessionName"
    $wezArgs = @(
        'start',
        '--workspace', $workspace,
        '--class', $windowClass,
        '--',
        $wslPath,
        '-d', $Distribution,
        '-e', 'bash', '-lc', $attachCommand
    )

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.FileName = $wezTermPath
    foreach ($argument in $wezArgs) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }
    $launchProcess = [Diagnostics.Process]::Start($psi)
    if (-not $launchProcess) {
        throw 'WezTerm did not return a process handle for the tmux launch.'
    }
    $proof.launch = [ordered]@{
        status = 'process-acknowledged'
        weztermProcessId = $launchProcess.Id
        workspace = $workspace
        windowClass = $windowClass
        attachCommand = $attachCommand
    }

    Write-Host "[LAUNCH] WezTerm accepted the tmux attachment request (PID $($launchProcess.Id))." -ForegroundColor Cyan
    Write-Host '[PROVE] Waiting for tmux to report a real attached client...' -ForegroundColor Cyan

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $clientEvidence = @()
    do {
        $clientScript = "tmux list-clients -t '$SessionName' -F '#{client_pid}|#{client_tty}|#{session_name}' 2>/dev/null || true"
        $clientProbe = Invoke-BoundedProcess -FilePath $wslPath -ArgumentList @(
            '-d', $Distribution, '--', 'bash', '-lc', $clientScript
        ) -ProcessTimeoutSeconds 5
        if (-not [string]::IsNullOrWhiteSpace($clientProbe.Stdout)) {
            $clientEvidence = @($clientProbe.Stdout -split "`r?`n" | Where-Object { $_ -match "\|$([regex]::Escape($SessionName))$" })
            if ($clientEvidence.Count -gt 0) { break }
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)

    if ($clientEvidence.Count -lt 1) {
        throw "WezTerm launched, but tmux did not report an attached client for session '$SessionName' within ${TimeoutSeconds}s."
    }

    $proof.tmuxClientAttachedObserved = $true
    $proof.tmuxClientEvidence = @($clientEvidence)
    $proof.launch.status = 'tmux-client-attached'
    $proof.status = 'success'
    $proof.proofLevel = 'tmux-client-attached'
    $proof.proofCeiling = 'Proves the repository-owned launcher reused or installed its owned prerequisites, established the requested tmux session, received a WezTerm process acknowledgement, and observed at least one live tmux client attached to that session. It does not prove visual focus, provider authentication, hosted model response, or agent task quality.'
    Write-Proof -Proof $proof

    Write-Host ''
    Write-Host '[PASS] TMUX IS LIVE.' -ForegroundColor Green
    Write-Host "Attached client: $($clientEvidence[0])"
    Write-Host "Evidence:        $script:ProofPath"
    exit 0
}
catch {
    $proof.status = 'failed'
    $proof.error = $_.Exception.ToString()
    $proof.proofCeiling = 'The live-proof gate did not complete; inspect the durable evidence and error before retrying.'
    Write-Proof -Proof $proof
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    Write-Host "Evidence: $script:ProofPath" -ForegroundColor Yellow
    exit 1
}
