[CmdletBinding()]
param(
    [string]$RepairId = 'WezTerm',
    [string]$RunId,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Repairing WezTerm installation via WinGet...' -ForegroundColor Yellow
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if (-not $winget) {
    throw 'winget.exe is unavailable; WezTerm repair cannot use the approved WinGet source.'
}

& $winget.Source install --id wez.wezterm --exact --source winget --silent --accept-source-agreements --accept-package-agreements
$installExit = $LASTEXITCODE

$candidates = [System.Collections.Generic.List[string]]::new()
$pathCommand = Get-Command wezterm.exe -ErrorAction SilentlyContinue
if ($pathCommand) { [void]$candidates.Add($pathCommand.Source) }
foreach ($candidate in @(
    (Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\wezterm.exe')
)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate)) { [void]$candidates.Add($candidate) }
}

$wezTermPath = $null
foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $wezTermPath = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}
if (-not $wezTermPath) {
    throw "WinGet repair exited $installExit and no supported wezterm.exe path is resolvable."
}

$output = (& $wezTermPath --version 2>&1 | Out-String).Trim()
$versionExit = $LASTEXITCODE
if ($versionExit -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
    throw "WezTerm exists at '$wezTermPath' but its version probe failed with exit code $versionExit."
}

Write-Host "WezTerm repair verified: $output" -ForegroundColor Green
return 0
