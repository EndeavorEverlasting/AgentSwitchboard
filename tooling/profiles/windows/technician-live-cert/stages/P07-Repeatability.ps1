[CmdletBinding()]
param(
    [string]$StageId = 'P07',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Running P07-Repeatability stage...' -ForegroundColor Yellow

$setupScript = Join-Path $RepoRoot 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) {
    throw "Canonical technician setup/launcher script is missing: $setupScript"
}
$pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source

function Invoke-SetupMode {
    param([Parameter(Mandatory)][string]$Mode)
    Write-Host "Repeatability action: $Mode" -ForegroundColor Gray
    $proc = Start-Process -FilePath $pwshPath -ArgumentList @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $setupScript),
        '-Mode', $Mode,
        '-RepoRoot', ('"{0}"' -f $RepoRoot)
    ) -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Repeatability action '$Mode' failed with exit code $($proc.ExitCode)."
    }
    return $proc.ExitCode
}

function Get-OptionalFileHash {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'MISSING' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-WslTmuxConfigHash {
    $output = (& wsl.exe -d Ubuntu -- bash -lc 'if [ -f "$HOME/.tmux.conf" ]; then sha256sum "$HOME/.tmux.conf" | cut -d" " -f1; else printf MISSING; fi' 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read Ubuntu tmux configuration hash: $output"
    }
    return $output
}

$headBefore = (& git.exe -C $RepoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve repository HEAD before repeatability checks.' }
$wezConfig = Join-Path $HOME '.wezterm.lua'
$wezHashBefore = Get-OptionalFileHash -Path $wezConfig
$tmuxHashBefore = Get-WslTmuxConfigHash

$actions = [System.Collections.Generic.List[object]]::new()
foreach ($mode in @('setup', 'shell', 'shell', 'agy', 'opencode')) {
    $startedAt = (Get-Date).ToUniversalTime().ToString('o')
    $code = Invoke-SetupMode -Mode $mode
    [void]$actions.Add([pscustomobject]@{
        mode = $mode
        startedAt = $startedAt
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
        exitCode = $code
    })
}

$shimRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin'
$env:Path = "$shimRoot;$([Environment]::GetEnvironmentVariable('Path','Machine'));$([Environment]::GetEnvironmentVariable('Path','User'))"
$tmuxCommand = Get-Command tmux -ErrorAction Stop

$sessionLines = @(& $tmuxCommand.Source list-sessions -F '#S' 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "tmux session enumeration failed: $($sessionLines -join ' ')"
}
$devSessionCount = @($sessionLines | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -eq 'dev' }).Count
if ($devSessionCount -ne 1) {
    throw "Repeatability expected exactly one tmux session named 'dev'; observed $devSessionCount."
}

$windowLines = @(& $tmuxCommand.Source list-windows -t dev -F '#W' 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "tmux window enumeration failed: $($windowLines -join ' ')"
}
$windowNames = @($windowLines | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
$agyWindowCount = @($windowNames | Where-Object { $_ -eq 'agy' }).Count
$openCodeWindowCount = @($windowNames | Where-Object { $_ -eq 'opencode' }).Count
if ($agyWindowCount -ne 1) {
    throw "Repeatability expected exactly one 'agy' tmux window; observed $agyWindowCount."
}
if ($openCodeWindowCount -ne 1) {
    throw "Repeatability expected exactly one 'opencode' tmux window; observed $openCodeWindowCount."
}

$headAfter = (& git.exe -C $RepoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve repository HEAD after repeatability checks.' }
if ($headAfter -ne $headBefore) {
    throw "Repository HEAD changed during repeatability validation: $headBefore -> $headAfter"
}
$dirty = @(& git.exe -C $RepoRoot status --porcelain=v1 --untracked-files=normal 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Unable to verify repository cleanliness after repeatability checks.' }
if ($dirty.Count -gt 0) {
    throw "Repository became dirty during repeatability validation. Nothing will be reset or cleaned automatically."
}

$wezHashAfter = Get-OptionalFileHash -Path $wezConfig
$tmuxHashAfter = Get-WslTmuxConfigHash
if ($wezHashAfter -ne $wezHashBefore) {
    throw 'Repeatability validation detected a change to ~/.wezterm.lua.'
}
if ($tmuxHashAfter -ne $tmuxHashBefore) {
    throw 'Repeatability validation detected a change to Ubuntu ~/.tmux.conf.'
}

$summaryData = [ordered]@{
    schema = 'agentswitchboard.technician-live-cert-repeatability.v1'
    actions = $actions
    devSessionCount = $devSessionCount
    tmuxWindows = $windowNames
    agyWindowCount = $agyWindowCount
    openCodeWindowCount = $openCodeWindowCount
    repositoryHeadBefore = $headBefore
    repositoryHeadAfter = $headAfter
    repositoryClean = $true
    weztermConfigHashBefore = $wezHashBefore
    weztermConfigHashAfter = $wezHashAfter
    tmuxConfigHashBefore = $tmuxHashBefore
    tmuxConfigHashAfter = $tmuxHashAfter
    commandProof = 'passed'
    visibleDuplicateWindowProof = 'manual-observation-required'
    passed = $true
}
$repeatabilityFile = Join-Path $StageDir 'repeatability-summary.json'
$summaryData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $repeatabilityFile -Encoding utf8NoBOM

Write-Host 'P07 command-level repeatability checks passed. Manual duplicate-window observation remains required.' -ForegroundColor Green
return 0
