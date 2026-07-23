[CmdletBinding()]
param(
    [string]$StageId = 'P03',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Running P03-Verify-Commands stage..." -ForegroundColor Yellow

$commandShimRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin'
$env:PATH = "$commandShimRoot;$env:PATH"

$commandsToVerify = @(
    @{ Name = 'wezterm'; Args = '--version' },
    @{ Name = 'wsl'; Args = '--status' },
    @{ Name = 'agy'; Args = '--version' },
    @{ Name = 'opencode'; Args = '--version' }
)

$results = [System.Collections.Generic.List[object]]::new()
$allVerified = $true

foreach ($cmd in $commandsToVerify) {
    $cmdName = $cmd.Name
    $args = $cmd.Args
    $cmdEntry = Get-Command $cmdName -ErrorAction SilentlyContinue
    if (-not $cmdEntry) {
        # Check in commandShimRoot
        $shimCandidate = Join-Path $commandShimRoot "$cmdName.cmd"
        if (Test-Path -LiteralPath $shimCandidate) {
            $cmdEntry = [pscustomobject]@{ Source = $shimCandidate }
        }
    }

    if ($cmdEntry) {
        [void]$results.Add([pscustomobject]@{
            command = $cmdName
            found = $true
            source = $cmdEntry.Source
        })
        Write-Host "Verified command '$cmdName': $($cmdEntry.Source)" -ForegroundColor Green
    } else {
        $allVerified = $false
        [void]$results.Add([pscustomobject]@{
            command = $cmdName
            found = $false
            source = $null
        })
        Write-Host "Missing command '$cmdName'" -ForegroundColor Red
    }
}

$cmdSummaryFile = Join-Path $StageDir 'commands-summary.json'
$json = ConvertTo-Json $results -Depth 5
[System.IO.File]::WriteAllText($cmdSummaryFile, $json, [System.Text.Encoding]::UTF8)

if (-not $allVerified) {
    Write-Warning "One or more technician commands were missing or unverified."
}

Write-Host "P03-Verify-Commands completed." -ForegroundColor Green
return 0
