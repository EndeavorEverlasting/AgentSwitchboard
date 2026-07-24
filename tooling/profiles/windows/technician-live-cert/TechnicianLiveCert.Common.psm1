# TechnicianLiveCert.Common.psm1
# Shared module for Technician Clickable Live-Cert runner

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TechnicianCurrentSid {
    [CmdletBinding()]
    param()
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

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
        throw "$ContextName requires administrator elevation."
    }
}

function Resolve-TechnicianRepoRoot {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $candidate = $RepoRoot.Trim().Trim('"').TrimEnd('\', '/')
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $fallback = Join-Path $PSScriptRoot '..\..\..\..'
    if (-not (Test-Path -LiteralPath $fallback -PathType Container)) {
        throw "Unable to resolve AgentSwitchboard repository root from '$RepoRoot' or module path '$PSScriptRoot'."
    }
    return (Resolve-Path -LiteralPath $fallback).Path
}

function Get-TechnicianRepoGitState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $resolvedRoot = Resolve-TechnicianRepoRoot -RepoRoot $RepoRoot

    $headOutput = @(& git -C $resolvedRoot rev-parse HEAD 2>$null)
    $headExit = $LASTEXITCODE
    $head = if ($headOutput.Count -gt 0) { ([string]$headOutput[0]).Trim() } else { '' }
    if ($headExit -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
        throw "Unable to resolve repository HEAD for '$resolvedRoot'."
    }

    $branchOutput = @(& git -C $resolvedRoot symbolic-ref --quiet --short HEAD 2>$null)
    $branchExit = $LASTEXITCODE
    $branch = if ($branchOutput.Count -gt 0) { ([string]$branchOutput[0]).Trim() } else { '' }
    if ($branchExit -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
        $branch = 'DETACHED'
    }

    return [pscustomobject]@{
        Root = $resolvedRoot
        Head = $head
        Branch = $branch
    }
}

function Get-TechnicianLiveCertBaseDir {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )

    $resolvedRepoRoot = Resolve-TechnicianRepoRoot -RepoRoot $RepoRoot
    $candidate = Join-Path $resolvedRepoRoot 'tooling\profiles\windows\technician-live-cert'
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "Technician live-cert directory not found under repository root: $resolvedRepoRoot"
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Get-TechnicianLiveCertManifestPath {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )
    $baseDir = Get-TechnicianLiveCertBaseDir -RepoRoot $RepoRoot
    $manifestPath = Join-Path $baseDir 'technician-live-cert.manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
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

function Get-TechnicianLiveCertStateDir {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is unavailable; technician live-cert state cannot be created.'
    }

    $stateDir = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\technician-live-cert'
    if (-not (Test-Path -LiteralPath $stateDir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $stateDir -Force
    }
    return $stateDir
}

function Get-TechnicianLiveCertRunsDir {
    [CmdletBinding()]
    param()

    $runsDir = Join-Path (Get-TechnicianLiveCertStateDir) 'runs'
    if (-not (Test-Path -LiteralPath $runsDir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $runsDir -Force
    }
    return $runsDir
}

function Get-TechnicianLiveCertActiveRunPath {
    [CmdletBinding()]
    param()
    return (Join-Path (Get-TechnicianLiveCertStateDir) 'active-run.json')
}

function Set-TechnicianLiveCertActiveRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RunContext
    )

    $pointer = [ordered]@{
        schema = 'agentswitchboard.technician-live-cert-active-run.v1'
        runId = [string]$RunContext.runId
        startedAt = [string]$RunContext.startedAt
        accountSid = [string]$RunContext.accountSid
        repositoryRoot = [string]$RunContext.repositoryRoot
        branch = [string]$RunContext.branch
        head = [string]$RunContext.head
        evidenceRoot = [string]$RunContext.evidenceRoot
    }
    Write-TechnicianLiveCertJson -Object $pointer -Path (Get-TechnicianLiveCertActiveRunPath)
}

function Get-TechnicianLiveCertActiveRunId {
    [CmdletBinding()]
    param()

    $pointerPath = Get-TechnicianLiveCertActiveRunPath
    if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) {
        return $null
    }

    $pointer = Get-Content -LiteralPath $pointerPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$pointer.runId)) {
        throw "Active live-cert pointer is invalid: $pointerPath"
    }

    $runJson = Join-Path (Join-Path (Get-TechnicianLiveCertRunsDir) $pointer.runId) 'run.json'
    if (-not (Test-Path -LiteralPath $runJson -PathType Leaf)) {
        throw "Active live-cert pointer is stale: run '$($pointer.runId)' is missing. Start again with Technician-LiveCert-P00-Preflight.cmd."
    }

    return [string]$pointer.runId
}

function Get-LatestCompletedTechnicianLiveCertRunId {
    [CmdletBinding()]
    param()

    $runsDir = Get-TechnicianLiveCertRunsDir
    $candidates = Get-ChildItem -LiteralPath $runsDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending

    foreach ($candidate in $candidates) {
        $runJson = Join-Path $candidate.FullName 'run.json'
        if (-not (Test-Path -LiteralPath $runJson -PathType Leaf)) {
            continue
        }

        try {
            $run = Get-Content -LiteralPath $runJson -Raw | ConvertFrom-Json
        }
        catch {
            continue
        }

        if ($run.status -eq 'completed' -and
            $run.stages -and
            $run.stages.PSObject.Properties['P08'] -and
            $run.stages.P08.status -eq 'passed') {
            return [string]$run.runId
        }
    }

    return $null
}

function Clear-TechnicianLiveCertActiveRun {
    [CmdletBinding()]
    param(
        [string]$RunId
    )

    $pointerPath = Get-TechnicianLiveCertActiveRunPath
    if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) {
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        $pointer = Get-Content -LiteralPath $pointerPath -Raw | ConvertFrom-Json
        if ([string]$pointer.runId -ne $RunId) {
            return
        }
    }

    Remove-Item -LiteralPath $pointerPath -Force
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
        throw 'RunId is required. Start P00 or use the active-run pointer.'
    }

    $runDir = Join-Path $runsDir $RunId
    if (-not (Test-Path -LiteralPath $runDir -PathType Container)) {
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

    $gitState = Get-TechnicianRepoGitState -RepoRoot $RepoRoot
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $username = $identity.Name
    $accountSid = $identity.User.Value
    $hostname = [Environment]::MachineName
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
        repositoryRoot = $gitState.Root
        branch = $gitState.Branch
        head = $gitState.Head
        distribution = 'Ubuntu'
        elevationState = $elevState
        evidenceRoot = $evidenceRoot
        proofCeiling = 'Technician clickable live certification pipeline executing P00-P08 with explicit command, observation, and evidence gates.'
        stages = $stagesObj
        optionalStages = $optionalStagesObj
        status = 'running'
    }

    $runJsonPath = Join-Path $evidenceRoot 'run.json'
    Write-TechnicianLiveCertJson -Object $runContext -Path $runJsonPath
    Set-TechnicianLiveCertActiveRun -RunContext $runContext

    return $runContext
}

function Get-TechnicianLiveCertRunContext {
    [CmdletBinding()]
    param(
        [string]$RunId
    )

    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = Get-TechnicianLiveCertActiveRunId
        if ([string]::IsNullOrWhiteSpace($RunId)) {
            throw 'No active technician live-cert run exists. Start with Technician-LiveCert-P00-Preflight.cmd or Run-Technician-LiveCert.cmd.'
        }
    }

    $runDir = Get-TechnicianLiveCertRunDir -RunId $RunId
    $runJsonPath = Join-Path $runDir 'run.json'
    if (-not (Test-Path -LiteralPath $runJsonPath -PathType Leaf)) {
        throw "Technician live-cert run '$RunId' is missing run.json. Start a new run with P00."
    }
    return Get-Content -LiteralPath $runJsonPath -Raw | ConvertFrom-Json
}

function Assert-TechnicianLiveCertRunIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RunContext,
        [Parameter(Mandatory)][string]$RepoRoot,
        [switch]$AllowHeadChange
    )

    $currentSid = Get-TechnicianCurrentSid
    if ($currentSid -ne [string]$RunContext.accountSid) {
        throw "Live-cert account mismatch. Run started as SID '$($RunContext.accountSid)' but current SID is '$currentSid'."
    }

    $gitState = Get-TechnicianRepoGitState -RepoRoot $RepoRoot
    if ($RunContext.PSObject.Properties['repositoryRoot'] -and
        -not [string]::IsNullOrWhiteSpace([string]$RunContext.repositoryRoot) -and
        $gitState.Root.TrimEnd('\') -ine ([string]$RunContext.repositoryRoot).TrimEnd('\')) {
        throw "Live-cert repository mismatch. Run root '$($RunContext.repositoryRoot)' does not match '$($gitState.Root)'."
    }

    if (-not $AllowHeadChange -and $gitState.Head -ne [string]$RunContext.head) {
        throw "Live-cert repository HEAD changed during the run. Expected '$($RunContext.head)', found '$($gitState.Head)'. Start a new P00 run."
    }

    return $gitState
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
    $json = ConvertTo-Json -InputObject $Object -Depth 12
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
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
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add($argument)
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
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()

    $stdOutText = $stdout.GetAwaiter().GetResult().Replace([char]0, '')
    $stdErrText = $stderr.GetAwaiter().GetResult().Replace([char]0, '')
    $combinedLog = "STDOUT:`n$stdOutText`nSTDERR:`n$stdErrText"

    if ($LogPath) {
        $dir = Split-Path -Parent $LogPath
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $dir -Force
        }
        [System.IO.File]::WriteAllText($LogPath, $combinedLog, [System.Text.UTF8Encoding]::new($false))
    }

    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        StandardOutput = $stdOutText
        StandardError = $stdErrText
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

    if ($NonInteractive) {
        return [pscustomobject]@{
            prompt = $PromptText
            response = '3'
            notes = 'Manual observation is not proven in non-interactive mode.'
        }
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host " MANUAL OBSERVATION REQUIRED FOR STAGE $StageId" -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host $PromptText -ForegroundColor White
    Write-Host ''
    Write-Host '1) YES - Observed expected behavior' -ForegroundColor Green
    Write-Host '2) NO  - Expected behavior was not observed' -ForegroundColor Red
    Write-Host '3) BLOCK - Cannot make the required observation' -ForegroundColor Yellow
    Write-Host ''

    $choice = Read-Host 'Select option [1, 2, or 3]'
    $notes = Read-Host 'Enter observation notes (optional)'
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
    'Get-TechnicianCurrentSid',
    'Test-IsElevated',
    'Assert-Elevation',
    'Resolve-TechnicianRepoRoot',
    'Get-TechnicianRepoGitState',
    'Get-TechnicianLiveCertBaseDir',
    'Get-TechnicianLiveCertManifestPath',
    'Get-TechnicianLiveCertManifest',
    'Get-TechnicianLiveCertStateDir',
    'Get-TechnicianLiveCertRunsDir',
    'Get-TechnicianLiveCertActiveRunPath',
    'Set-TechnicianLiveCertActiveRun',
    'Get-TechnicianLiveCertActiveRunId',
    'Get-LatestCompletedTechnicianLiveCertRunId',
    'Clear-TechnicianLiveCertActiveRun',
    'New-TechnicianLiveCertRunId',
    'Get-TechnicianLiveCertRunDir',
    'New-TechnicianLiveCertRunContext',
    'Get-TechnicianLiveCertRunContext',
    'Assert-TechnicianLiveCertRunIdentity',
    'Save-TechnicianLiveCertRunContext',
    'Write-TechnicianLiveCertJson',
    'Invoke-CapturedProcess',
    'Invoke-ManualObservationPrompt'
)
