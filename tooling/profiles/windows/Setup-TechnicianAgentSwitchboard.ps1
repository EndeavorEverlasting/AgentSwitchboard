[CmdletBinding()]
param(
    [ValidateSet('shell', 'agy', 'opencode', 'setup')]
    [string]$Mode = 'shell',

    [Parameter(Mandatory)]
    [string]$RepoRoot,

    [string]$GitRef = 'main',

    [string]$Distribution = 'Ubuntu'
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

$steps = [System.Collections.Generic.List[object]]::new()
$summary = [ordered]@{
    schema = 'agentswitchboard.technician-quickstart-result.v1'
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
    officialInstallSources = [ordered]@{
        wezterm = 'winget:wez.wezterm'
        agy = 'https://antigravity.google/cli/install.sh'
        opencode = 'https://opencode.ai/install'
    }
    steps = $steps
    error = $null
    proofLevel = 'workstation-setup-and-command-ack'
    proofCeiling = 'Installs and verifies prerequisites in the selected WSL distribution and requests the canonical Windows Profile. User-visible window behavior, authentication, provider response, and agent task quality remain separate runtime proof.'
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

function Resolve-WezTermCli {
    foreach ($commandName in @('wezterm.exe', 'wezterm')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    foreach ($candidate in @(
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe' })
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
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
        $wezTermPath = Resolve-WezTermCli
    }
    if (-not $wezTermPath) {
        throw 'WezTerm installation completed without a resolvable wezterm.exe.'
    }
    Add-Step -Name 'wezterm' -Status 'passed' -Evidence $wezTermPath

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
  installer="$(mktemp)"
  curl -fsSL https://antigravity.google/cli/install.sh -o "$installer"
  bash "$installer" --skip-aliases
  rm -f "$installer"
fi

export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
if ! command -v opencode >/dev/null 2>&1; then
  installer="$(mktemp)"
  curl -fsSL https://opencode.ai/install -o "$installer"
  bash "$installer"
  rm -f "$installer"
fi

export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
if tmux list-sessions >/dev/null 2>&1; then
  tmux set-environment -g PATH "$PATH"
fi

printf '__TMUX__='; tmux -V
printf '__AGY__='; agy --version
printf '__OPENCODE__='; opencode --version
'@

    Invoke-WslInteractive -WslPath $wslPath -Script $linuxSetup -Stage 'Install or verify tmux, AGY, and OpenCode inside Ubuntu'
    Add-Step -Name 'wsl-agent-tools' -Status 'passed' -Evidence 'tmux, agy, and opencode version probes exited successfully inside Ubuntu.'

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
    Add-Step -Name 'windows-profile-launch' -Status 'passed' -Evidence 'Canonical open-or-activate command was acknowledged.'

    if ($Mode -in @('agy', 'opencode')) {
        $toolWindowScript = @'
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
session='dev'
window='__TOOL__'
if ! tmux has-session -t "$session" 2>/dev/null; then
  echo "Expected tmux session '$session' was not found." >&2
  exit 50
fi
if tmux list-windows -t "$session" -F '#W' | grep -Fxq "$window"; then
  tmux select-window -t "$session:$window"
else
  tmux new-window -d -t "$session" -n "$window" "env PATH=\"$HOME/.local/bin:$HOME/.opencode/bin:$PATH\" __TOOL__"
  tmux select-window -t "$session:$window"
fi
'@.Replace('__TOOL__', $Mode)

        Invoke-WslInteractive -WslPath $wslPath -Script $toolWindowScript -Stage "Open or select the $Mode tmux window"
        Add-Step -Name 'agent-window' -Status 'passed' -Evidence "Requested tmux window '$Mode' in session 'dev'. Authentication and provider response remain interactive runtime gates."
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
