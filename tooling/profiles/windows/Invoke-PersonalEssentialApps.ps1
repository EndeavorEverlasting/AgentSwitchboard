[CmdletBinding()]
param(
    [ValidateSet('Inspect', 'Apply')][string]$Mode = 'Inspect',
    [string]$OutputRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Essential desktop apps require Windows.' }
if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required.' }
if (-not $OutputRoot) { $OutputRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard/personal-workstation-bootstrap/runs' }
$runId = '{0}-{1}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'), [guid]::NewGuid().ToString('N').Substring(0,8)
$runRoot = Join-Path $OutputRoot "essential-apps-$runId"
$null = New-Item -Path $runRoot -ItemType Directory -Force
$receiptPath = Join-Path $runRoot 'essential-apps-summary.json'
$items = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param([string]$Id, [string]$State, [string]$Detail)
    [void]$items.Add([pscustomobject]@{ id=$Id; state=$State; detail=$Detail })
    Write-Host ('[{0}] {1}: {2}' -f $State.ToUpperInvariant(), $Id, $Detail)
}
function Get-BravePath {
    $roots = @($env:LOCALAPPDATA, $env:ProgramFiles, [Environment]::GetEnvironmentVariable('ProgramFiles(x86)'))
    $candidates = @($roots | Where-Object { $_ } | ForEach-Object { Join-Path $_ 'BraveSoftware/Brave-Browser/Application/brave.exe' })
    return @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
}
function Get-WisprState {
    $base = Join-Path $env:LOCALAPPDATA 'WisprFlow'
    $update = Join-Path $base 'Update.exe'
    $apps = @()
    if (Test-Path -LiteralPath $base -PathType Container) {
        foreach ($folder in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'app-*' })) {
            $apps += @((Join-Path $folder.FullName 'WisprFlow.exe'), (Join-Path $folder.FullName 'Wispr Flow.exe')) |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
        }
        $apps += @((Join-Path $base 'WisprFlow.exe'), (Join-Path $base 'Wispr Flow.exe')) |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    }
    if ($apps.Count -gt 0 -and (Test-Path -LiteralPath $update -PathType Leaf)) { return 'installed-files-present' }
    if ($apps.Count -gt 0 -or (Test-Path -LiteralPath $update -PathType Leaf)) { return 'partial-install-review-required' }
    return 'not-detected'
}

$summary = [ordered]@{
    schema = 'agentswitchboard.personal-essential-apps-result.v1'
    runId = $runId; mode = $Mode; startedAtUtc = [DateTime]::UtcNow.ToString('o')
    state = 'running'; apps = $items; nextAction = $null
    proofCeiling = 'On-disk app discovery and installer execution; actual launch, default browser, voice login, microphone and update health remain separate gates.'
}
try {
    $brave = @(Get-BravePath)
    $wispr = Get-WisprState
    if ($Mode -eq 'Inspect') {
        Add-Finding 'brave' $(if ($brave.Count) {'installed-files-present'} else {'not-detected'}) 'Brave executable paths inspected; not launched.'
        Add-Finding 'wispr-flow' $wispr 'Per-user Wispr app and updater files inspected; not launched.'
        $summary.state = 'inspection-complete'
        $summary.nextAction = 'To install missing apps, run -Mode Apply. Default browser, Wispr login and mic permission require interaction.'
    } else {
        if ($brave.Count) {
            Add-Finding 'brave' 'installed-files-present' 'Existing Brave executable detected; preserved without reinstall.'
        } else {
            $winget = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $winget) { throw 'WinGet unavailable. Install/update App Installer, then resume.' }
            Add-Finding 'brave' 'installing' 'Official Brave.Brave community WinGet package; Microsoft Store excluded.'
            & $winget.Source install --id Brave.Brave --exact --source winget --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) { throw "WinGet Brave installer failed ($LASTEXITCODE)." }
            $brave = @(Get-BravePath)
            if (-not $brave.Count) { throw 'Brave install exited zero, but executable not detected. Reopen a shell and inspect.' }
            Add-Finding 'brave' 'installed-files-present' 'Brave executable detected after installation.'
        }

        if ($wispr -eq 'installed-files-present') {
            Add-Finding 'wispr-flow' $wispr 'Existing Wispr and updater detected; preserved.'
        } elseif ($wispr -eq 'partial-install-review-required') {
            Add-Finding 'wispr-flow' $wispr 'Partial or orphaned installation; preserve files and preferences. Do not silently overwrite.'
            $summary.state = 'operator-review-required'
            $summary.nextAction = 'Review Wispr Flow in Installed apps and follow vendor repair; do not delete existing app data.'
        } else {
            $installer = Join-Path $runRoot 'WisprFlowInstaller.exe'
            Add-Finding 'wispr-flow' 'downloading' 'Official per-user Windows installer, direct vendor URL.'
            Invoke-WebRequest -Uri 'https://dl.wisprflow.ai/windows/latest' -OutFile $installer -MaximumRedirection 5 -TimeoutSec 300 -UseBasicParsing
            $file = Get-Item -LiteralPath $installer -ErrorAction Stop
            if ($file.Length -lt 10240) { throw 'Wispr response is too small to trust as executable.' }
            $sig = Get-AuthenticodeSignature -LiteralPath $installer
            if ($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate -or
                $sig.SignerCertificate.Subject -notmatch '(?i)Wispr AI') {
                throw 'Wispr installer failed official publisher code-signature verification. Refusing execution.'
            }
            Add-Finding 'wispr-flow' 'signature-verified' 'Trusted vendor signature verified before launching installer.'
            $process = Start-Process -FilePath $installer -PassThru -Wait
            if ($process.ExitCode -ne 0) { throw "Wispr installer exited $($process.ExitCode); inspect vendor UI." }
            $after = Get-WisprState
            if ($after -eq 'installed-files-present') {
                Add-Finding 'wispr-flow' $after 'Installer returned zero and app/updater exist.'
            } else {
                Add-Finding 'wispr-flow' 'installation-not-yet-verified' "Installer exited zero but state is $after; downloader/setup may continue."
                $summary.state = 'operator-review-required'
                $summary.nextAction = 'Let the vendor installer finish and open Wispr Flow; rerun Inspect.'
            }
        }
        if ($summary.state -eq 'running') {
            $summary.state = 'installed-files-present'
            $summary.nextAction = 'Choose Brave via Windows Default apps. Sign in to Wispr and grant microphone permission; test dictation.'
        }
    }
} catch {
    Add-Finding 'essential-apps' 'blocked' $_.Exception.Message
    $summary.state = 'blocked'
    $summary.nextAction = $_.Exception.Message
} finally {
    $summary.completedAtUtc = [DateTime]::UtcNow.ToString('o')
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    Write-Host "Receipt: $receiptPath"
    Write-Host "State: $($summary.state)"
    Write-Host "Next: $($summary.nextAction)"
}
if ($summary.state -eq 'blocked') { exit 1 }
exit 0
