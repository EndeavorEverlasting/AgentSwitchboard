[CmdletBinding()]
param(
    [string]$OutputRoot,
    [ValidateRange(1,30)][int]$TimeoutSeconds = 5,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Windows toolchain launch preflight is Windows-only.'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $base = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\technician-live-cert\toolchain-preflight'
    } else {
        Join-Path ([IO.Path]::GetTempPath()) 'AgentSwitchboard/technician-live-cert/toolchain-preflight'
    }
    $runId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0,8))
    $OutputRoot = Join-Path $base $runId
}
$null = New-Item -ItemType Directory -Path $OutputRoot -Force

$candidatePaths = New-Object 'System.Collections.Generic.List[string]'
function Add-Candidate {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $full = [Environment]::ExpandEnvironmentVariables($Path)
    if ($candidatePaths -notcontains $full) { [void]$candidatePaths.Add($full) }
}

Add-Candidate (Join-Path $env:ProgramFiles 'Git\cmd\git.exe')
Add-Candidate (Join-Path $env:ProgramFiles 'Git\bin\git.exe')
if (${env:ProgramFiles(x86)}) {
    Add-Candidate (Join-Path ${env:ProgramFiles(x86)} 'Git\cmd\git.exe')
}
if ($env:LOCALAPPDATA) {
    Add-Candidate (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
}
Get-Command git.exe -All -ErrorAction SilentlyContinue | ForEach-Object { Add-Candidate $_.Source }

$rows = New-Object 'System.Collections.Generic.List[object]'
$selected = $null
foreach ($path in $candidatePaths) {
    $row = [ordered]@{
        path = $path
        exists = Test-Path -LiteralPath $path -PathType Leaf
        source = if ($path -like '*\WindowsApps\*') { 'app-execution-alias-or-windowsapps' } else { 'filesystem-or-path' }
        fileVersion = $null
        signatureStatus = $null
        launched = $false
        timedOut = $false
        exitCode = $null
        stdout = $null
        stderr = $null
        error = $null
        usable = $false
    }
    try {
        if (-not $row.exists) { throw 'candidate does not exist as a file' }
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        $row.fileVersion = [string]$item.VersionInfo.FileVersion
        try { $row.signatureStatus = [string](Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop).Status } catch { $row.signatureStatus = 'unavailable' }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $path
        $psi.Arguments = '--version'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        if (-not $process.Start()) { throw 'process start returned false' }
        $row.launched = $true
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $row.timedOut = $true
            try { $process.Kill() } catch {}
            try { $process.WaitForExit() } catch {}
            throw "git --version exceeded the ${TimeoutSeconds}s bound"
        }
        $row.stdout = $process.StandardOutput.ReadToEnd().Trim()
        $row.stderr = $process.StandardError.ReadToEnd().Trim()
        $row.exitCode = $process.ExitCode
        $row.usable = ($row.exitCode -eq 0 -and $row.stdout -match '^git version\s+')
        if ($row.usable -and -not $selected) { $selected = $path }
    }
    catch {
        $row.error = $_.Exception.Message
    }
    [void]$rows.Add([pscustomobject]$row)
}

$status = if ($selected) { 'passed' } else { 'blocked' }
$result = [ordered]@{
    schema = 'agentswitchboard.windows-toolchain-launch-preflight.v1'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    status = $status
    selectedGit = $selected
    timeoutSeconds = $TimeoutSeconds
    candidates = @($rows)
    proofLevel = if ($selected) { 'git-executable-launch-and-version-observed' } else { 'git-executable-launch-blocked' }
    proofCeiling = 'Proves only that one concrete Git executable can be started by Windows and returns git --version within the bound. It does not prove repository identity, fetch, worktree creation, setup, provider authentication, launcher behavior, or hosted response.'
}
$jsonPath = Join-Path $OutputRoot 'windows-toolchain-launch-preflight.json'
$mdPath = Join-Path $OutputRoot 'windows-toolchain-launch-preflight.md'
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = @($rows | ForEach-Object {
    '| `{0}` | {1} | {2} | {3} | {4} | {5} |' -f $_.path, $_.exists, $_.launched, $_.exitCode, $_.usable, ($_.error -replace '\|','/')
})
$markdown = @"
# Windows Toolchain Launch Preflight

- Status: **$status**
- Selected Git: `$(if($selected){$selected}else{'none'})`
- Timeout: ${TimeoutSeconds}s
- Proof level: `$($result.proofLevel)`

## Candidates

| Path | Exists | Launched | Exit | Usable | Error |
|---|---:|---:|---:|---:|---|
$($lines -join "`n")

## Proof ceiling

$($result.proofCeiling)
"@
Set-Content -LiteralPath $mdPath -Value $markdown -Encoding UTF8

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Windows Toolchain Launch Preflight' -ForegroundColor White
Write-Host " Status: $status"
Write-Host " Selected Git: $(if($selected){$selected}else{'none'})"
Write-Host " JSON: $jsonPath"
Write-Host " Report: $mdPath"
Write-Host '============================================================' -ForegroundColor Cyan

if ($PassThru) { return [pscustomobject]$result }
if (-not $selected) { exit 31 }
exit 0
