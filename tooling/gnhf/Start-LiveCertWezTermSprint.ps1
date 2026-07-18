[CmdletBinding()]
param(
    [ValidateSet('BlacksmithCompile', 'BlacksmithNight', 'ModelMatrixOnly')]
    [string]$Profile = 'BlacksmithCompile',
    [string]$RepoPath = "$env:USERPROFILE\Desktop\dev\Mods\Bannerlord\BlacksmithGuild",
    [ValidatePattern('^deepseek/[^\s/]+$')]
    [string]$Model = 'deepseek/deepseek-v4-pro',
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$AlsoRunModelMatrix,
    [switch]$EnableSound
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Live cert WezTerm sprint requires PowerShell 7.'
}

$wezterm = Get-Command wezterm -ErrorAction Stop
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$modelMatrix = Join-Path $PSScriptRoot 'Start-LiveCertModelRouteProof.ps1'
$nightLauncher = Join-Path $InstallRoot 'Start-BlacksmithGuildNightShift.ps1'
if (-not (Test-Path -LiteralPath $nightLauncher -PathType Leaf)) {
    $nightLauncher = Join-Path $PSScriptRoot 'Start-BlacksmithGuildNightShift.ps1'
}
if (-not (Test-Path -LiteralPath $nightLauncher -PathType Leaf)) {
    throw "BlacksmithGuild night launcher missing. Run Install-BlacksmithGuildNightPanel.cmd first."
}

$logsRoot = Join-Path $InstallRoot 'logs\live-cert'
[void](New-Item -ItemType Directory -Path $logsRoot -Force)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$launchRecordPath = Join-Path $logsRoot "$stamp-wezterm-launch.json"

if ($AlsoRunModelMatrix -or $Profile -eq 'ModelMatrixOnly') {
    Write-Host 'Running model-route matrix before WezTerm sprint...' -ForegroundColor Cyan
    $matrixArgs = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $modelMatrix, '-OpenWezTermWindows')
    if ($EnableSound) { $matrixArgs += '-EnableSound' }
    & pwsh @matrixArgs
    if ($LASTEXITCODE -ne 0 -and $Profile -ne 'ModelMatrixOnly') {
        throw "Model-route matrix failed with exit $LASTEXITCODE; refusing to start a GNHF sprint."
    }
    if ($Profile -eq 'ModelMatrixOnly') {
        exit $LASTEXITCODE
    }
}

$stage = switch ($Profile) {
    'BlacksmithCompile' { 'Compile' }
    'BlacksmithNight' { 'Auto' }
}

$wrapper = @'
$Host.UI.RawUI.WindowTitle = "__WINDOW_TITLE__"
$ErrorActionPreference = "Stop"
Write-Host "=== AgentSwitchboard Live Cert WezTerm Sprint ===" -ForegroundColor Cyan
Write-Host "Profile:  __PROFILE__"
Write-Host "Repo:     __REPO__"
Write-Host "Model:    __MODEL__"
Write-Host "Stage:    __STAGE__"
Write-Host "Launcher: __LAUNCHER__"
Write-Host ""
& "__LAUNCHER__" -RepoPath "__REPO__" -Stage "__STAGE__" -Agent deepseek -DeepSeekModel "__MODEL__"
$code = $LASTEXITCODE
$color = if ($code -eq 0) { "Green" } else { "Yellow" }
Write-Host ""
Write-Host ("Live cert WezTerm sprint exited with code {0}" -f $code) -ForegroundColor $color
Write-Host "Preserve worktrees and provider-route evidence. Press Enter to close."
[void][Console]::ReadLine()
exit $code
'@
$wrapper = $wrapper.
    Replace('__WINDOW_TITLE__', "AgentSwitchboard Live Cert - $Profile").
    Replace('__PROFILE__', $Profile).
    Replace('__REPO__', $RepoPath).
    Replace('__MODEL__', $Model).
    Replace('__STAGE__', $stage).
    Replace('__LAUNCHER__', $nightLauncher)

$wrapperPath = Join-Path $logsRoot "$stamp-wezterm-$Profile.ps1"
Set-Content -LiteralPath $wrapperPath -Value $wrapper -Encoding utf8

$launch = [ordered]@{
    schemaVersion = 1
    kind = 'agentswitchboard.live-cert.wezterm-launch'
    promptKit = 'AI_Harness_Prompt_Kit_v39'
    relatedPrompts = @('P37', 'P38', 'P47', 'P48')
    profile = $Profile
    stage = $stage
    model = $Model
    repoPath = $RepoPath
    wrapperPath = $wrapperPath
    nightLauncher = $nightLauncher
    startedAt = (Get-Date).ToString('o')
    proofCeiling = 'Launch and operator-visible WezTerm surface proof. Delivery still requires a commit ahead of the BlacksmithGuild base plus validation.'
}
$launch | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $launchRecordPath -Encoding utf8

Write-Host "`nOpening WezTerm live-cert window..." -ForegroundColor Cyan
Write-Host "Wrapper: $wrapperPath"
Write-Host "Record:  $launchRecordPath"

Start-Process -FilePath $wezterm.Source -ArgumentList @(
    'start',
    '--cwd', $repoRoot,
    '--',
    'pwsh.exe',
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $wrapperPath
) | Out-Null

if ($EnableSound) {
    try {
        [Console]::Beep(660, 100)
        [Console]::Beep(880, 120)
    }
    catch { }
}

Write-Host 'WezTerm window launch requested. Monitor the new surface for provider preflight and GNHF progress.' -ForegroundColor Green
Write-Host "Launch record: $launchRecordPath"
exit 0
