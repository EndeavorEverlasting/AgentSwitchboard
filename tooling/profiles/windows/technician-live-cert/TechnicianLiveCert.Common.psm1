# TechnicianLiveCert.Common.psm1
# Shared module for Technician Clickable Live-Cert runner

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsElevated {
    [CmdletBinding()]
    param()
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Elevation {
    [CmdletBinding()]
    param(
        [string]$ContextName = 'This operation'
    )
    if (-not (Test-IsElevated)) {
        throw "$ContextName requires administrator elevation. Please run in an elevated PowerShell/CMD session."
    }
}

function Get-TechnicianLiveCertBaseDir {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )
    if ($RepoRoot -and (Test-Path -LiteralPath $RepoRoot)) {
        $candidate = Join-Path $RepoRoot 'tooling\profiles\windows\technician-live-cert'
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    return (Resolve-Path -LiteralPath $scriptDir).Path
}

function Get-TechnicianLiveCertManifestPath {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )
    $baseDir = Get-TechnicianLiveCertBaseDir -RepoRoot $RepoRoot
    $manifestPath = Join-Path $baseDir 'technician-live-cert.manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Technician live cert manifest not found at: $manifestPath"
    }
    return $manifestPath
}

function Get-TechnicianLiveCertManifest {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )
    $path = Get-TechnicianLiveCertManifestPath -RepoRoot $RepoRoot
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-TechnicianLiveCertRunsDir {
    [CmdletBinding()]
    param()
    $runsDir = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\technician-live-cert\runs'
    if (-not (Test-Path -LiteralPath $runsDir)) {
        $null = New-Item -ItemType Directory -Path $runsDir -Force
    }
    return $runsDir
}

function New-TechnicianLiveCertRunId {
    [CmdletBinding()]
    param()
    $now = Get-Date
    $ts = $now.ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $guid = ([guid]::NewGuid().ToString('N')).Substring(0, 8)
    return "${ts}-${guid}"
}

function Get-TechnicianLiveCertRunDir {
    [CmdletBinding()]
    param(
        [string]$RunId
    )
    $runsDir = Get-TechnicianLiveCertRunsDir
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $latest = Get-ChildItem -Path $runsDir -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) {
            return $latest.FullName
        }
        throw "No existing technician live cert run directory found."
    }
    $runDir = Join-Path $runsDir $RunId
    if (-not (Test-Path -LiteralPath $runDir)) {
        $null = New-Item -ItemType Directory -Path $runDir -Force
    }
    return $runDir
}

function New-TechnicianLiveCertRunContext {
    [CmdletBinding()]
    param(
        [string]$RunId = (New-TechnicianLiveCertRunId),
        [string]$RepoRoot = ''
    )

    if (-not $RepoRoot) {
        $RepoRoot = (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName
    }

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $username = $identity.Name
    $accountSid = $identity.User.Value
    $hostname = [Environment]::MachineName

    $head = '0000000000000000000000000000000000000000'
    $branch = 'unknown'
    try {
        $head = (git rev-parse HEAD 2>$null).Trim()
        $branch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
    } catch {}

    $evidenceRoot = Get-TechnicianLiveCertRunDir -RunId $RunId

    $elevState = if (Test-IsElevated) { 'elevated' } else { 'none' }

    $stagesObj = [ordered]@{}
    foreach ($stageId in @('P00', 'P01', 'P02', 'P03', 'P04', 'P05', 'P06', 'P07', 'P08')) {
        $stagesObj[$stageId] = [ordered]@{
            stageId = $stageId
            name = ''
            status = 'pending'
            startedAt = $null
            completedAt = $null
            exitCode = $null
            evidencePath = $null
            classification = $null
            manualObservation = $null
            error = $null
        }
    }

    $optionalStagesObj = [ordered]@{
        P09 = [ordered]@{
            stageId = 'P09'
            name = 'Hermes Optional'
            status = 'pending'
            startedAt = $null
            completedAt = $null
            exitCode = $null
            evidencePath = $null
            classification = $null
            manualObservation = $null
            error = $null
        }
    }

    $runContext = [ordered]@{
        schema = 'agentswitchboard.technician-live-cert-run.v1'
        runId = $RunId
        startedAt = (Get-Date).ToUniversalTime().ToString('o')
        completedAt = $null
        accountSid = $accountSid
        username = $username
        hostname = $hostname
        repository = 'https://github.com/EndeavorEverlasting/AgentSwitchboard'
        branch = $branch
        head = $head
        distribution = 'Ubuntu'
        elevationState = $elevState
        evidenceRoot = $evidenceRoot
        proofCeiling = 'Technician clickable live certification pipeline executing P00-P08 with manual operator gates and evidence capture.'
        stages = $stagesObj
        optionalStages = $optionalStagesObj
        status = 'running'
    }

    $runJsonPath = Join-Path $evidenceRoot 'run.json'
    Write-TechnicianLiveCertJson -Object $runContext -Path $runJsonPath

    return $runContext
}

function Get-TechnicianLiveCertRunContext {
    [CmdletBinding()]
    param(
        [string]$RunId
    )
    $runDir = Get-TechnicianLiveCertRunDir -RunId $RunId
    $runJsonPath = Join-Path $runDir 'run.json'
    if (-not (Test-Path -LiteralPath $runJsonPath)) {
        return New-TechnicianLiveCertRunContext -RunId $RunId
    }
    return Get-Content -LiteralPath $runJsonPath -Raw | ConvertFrom-Json
}

function Save-TechnicianLiveCertRunContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RunContext
    )
    $runDir = Get-TechnicianLiveCertRunDir -RunId $RunContext.runId
    $runJsonPath = Join-Path $runDir 'run.json'
    Write-TechnicianLiveCertJson -Object $RunContext -Path $runJsonPath
}

function Write-TechnicianLiveCertJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Path
    )
    $json = ConvertTo-Json -InputObject $Object -Depth 10
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.Encoding]::UTF8)
}

function Invoke-CapturedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = '',
        [string]$LogPath = ''
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    if ($ArgumentList -and $ArgumentList.Count -gt 0) {
        $psi.Arguments = $ArgumentList -join ' '
    }
    if ($WorkingDirectory) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi

    $stdOut = [System.Text.StringBuilder]::new()
    $stdErr = [System.Text.StringBuilder]::new()

    $proc.add_OutputDataReceived({
        param($s, $e)
        if ($e.Data -ne $null) { [void]$stdOut.AppendLine($e.Data) }
    })
    $proc.add_ErrorDataReceived({
        param($s, $e)
        if ($e.Data -ne $null) { [void]$stdErr.AppendLine($e.Data) }
    })

    [void]$proc.Start()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
    $proc.WaitForExit()

    $exitCode = $proc.ExitCode

    $combinedLog = "STDOUT:`n" + $stdOut.ToString() + "`nSTDERR:`n" + $stdErr.ToString()

    if ($LogPath) {
        $dir = Split-Path -Parent $LogPath
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Path $dir -Force
        }
        [System.IO.File]::WriteAllText($LogPath, $combinedLog, [System.Text.Encoding]::UTF8)
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        StandardOutput = $stdOut.ToString()
        StandardError = $stdErr.ToString()
        CombinedOutput = $combinedLog
    }
}

function Invoke-ManualObservationPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StageId,
        [Parameter(Mandatory)][string]$PromptText,
        [switch]$NonInteractive
    )

    if ($env:TECHNICIAN_LIVE_CERT_AUTO_PASS -eq '1' -or $NonInteractive) {
        return [pscustomobject]@{
            prompt = $PromptText
            response = "1"
            notes = "Auto-confirmed in non-interactive / automated mode."
        }
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " MANUAL OBSERVATION REQUIRED FOR STAGE $StageId" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $PromptText -ForegroundColor White
    Write-Host ""
    Write-Host "1) YES - Observed expected behavior" -ForegroundColor Green
    Write-Host "2) NO  - Did not see expected window or action failed" -ForegroundColor Red
    Write-Host "3) SKIP / BLOCK - Cannot observe or skipping stage" -ForegroundColor Yellow
    Write-Host ""

    $choice = Read-Host "Select option [1, 2, or 3]"
    $notes = Read-Host "Enter observation notes (optional)"

    if ($choice -notin @('1', '2', '3')) {
        $choice = '2'
    }

    return [pscustomobject]@{
        prompt = $PromptText
        response = $choice
        notes = $notes
    }
}

Export-ModuleMember -Function @(
    'Test-IsElevated',
    'Assert-Elevation',
    'Get-TechnicianLiveCertBaseDir',
    'Get-TechnicianLiveCertManifestPath',
    'Get-TechnicianLiveCertManifest',
    'Get-TechnicianLiveCertRunsDir',
    'New-TechnicianLiveCertRunId',
    'Get-TechnicianLiveCertRunDir',
    'New-TechnicianLiveCertRunContext',
    'Get-TechnicianLiveCertRunContext',
    'Save-TechnicianLiveCertRunContext',
    'Write-TechnicianLiveCertJson',
    'Invoke-CapturedProcess',
    'Invoke-ManualObservationPrompt'
)
