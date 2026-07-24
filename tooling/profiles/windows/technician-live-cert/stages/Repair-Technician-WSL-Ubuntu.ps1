[CmdletBinding()]
param(
    [string]$RepairId = 'WSL-Ubuntu',
    [string]$RunId,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'WSL-Ubuntu repair requires Windows_NT.'
}

$stateRoot = Join-Path $env:ProgramData 'AgentSwitchBoard\Technician'
$statePath = Join-Path $stateRoot 'wsl-ubuntu-repair-state.json'
$runOncePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
$runOnceName = 'AgentSwitchBoardWslUbuntuRepair'
$repairCmd = if ($RepoRoot) { Join-Path $RepoRoot 'Repair-Technician-WSL-Ubuntu.cmd' } else { $null }

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [int[]]$AllowedExitCodes = @(0)
    )

    Write-Host ("> {0} {1}" -f $FilePath, ($ArgumentList -join ' ')) -ForegroundColor DarkGray
    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exitCode) {
        throw "$FilePath exited with code $exitCode."
    }
    return $exitCode
}

function Get-WslDistributionState {
    param([Parameter(Mandatory)][string]$WslPath)

    $raw = @(& $WslPath --list --quiet 2>&1)
    $exitCode = $LASTEXITCODE
    $names = @(
        $raw |
        ForEach-Object { ([string]$_).Replace([char]0, '').Trim() } |
        Where-Object { $_ -and $_ -notmatch '^Copyright ' }
    )

    return [pscustomobject]@{
        ExitCode = $exitCode
        Names = $names
        Raw = ($raw -join [Environment]::NewLine)
    }
}

function Save-RebootState {
    param([string]$Reason)

    $null = New-Item -ItemType Directory -Path $stateRoot -Force
    [ordered]@{
        schema = 'agentswitchboard.technician-wsl-repair-state.v1'
        status = 'reboot-required'
        reason = $Reason
        requestedAt = (Get-Date).ToUniversalTime().ToString('o')
        repoRoot = $RepoRoot
        repairCmd = $repairCmd
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM

    if ($repairCmd -and (Test-Path -LiteralPath $repairCmd -PathType Leaf)) {
        $null = New-Item -Path $runOncePath -Force
        $resume = 'cmd.exe /d /c ""{0}""' -f $repairCmd
        New-ItemProperty -Path $runOncePath -Name $runOnceName -Value $resume -PropertyType String -Force | Out-Null
        Write-Host '[PASS] Registered one-time post-reboot continuation for this same Windows user.' -ForegroundColor Green
    }
}

function Clear-RebootState {
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $runOncePath -Name $runOnceName -ErrorAction SilentlyContinue
}

$continuingAfterReboot = Test-Path -LiteralPath $statePath -PathType Leaf

Write-Host 'Repairing Windows WSL platform and Ubuntu for a first-machine install...' -ForegroundColor Yellow
Write-Host 'Windows optional features are machine-wide; Ubuntu registration is for the current Windows user.' -ForegroundColor Gray

# The repair dispatcher already requires same-user UAC elevation. Enable the two
# Windows components required by the repository's WSL 2 profile. DISM is used
# directly so this works from PowerShell 7 without depending on WindowsPowerShell
# module compatibility.
$rebootRequired = $false
foreach ($featureName in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    Write-Host "Enabling Windows feature: $featureName" -ForegroundColor Cyan
    & dism.exe /Online /Enable-Feature "/FeatureName:$featureName" /All /NoRestart
    $featureExit = $LASTEXITCODE
    if ($featureExit -notin @(0, 3010)) {
        throw "DISM could not enable '$featureName' (exit $featureExit)."
    }
    if ($featureExit -eq 3010) {
        $rebootRequired = $true
    }
}

$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCommand) {
    if ($continuingAfterReboot) {
        throw 'Windows features were enabled and the repair resumed after reboot, but wsl.exe is still unavailable. This Windows image needs separate WSL platform servicing.'
    }
    Save-RebootState -Reason 'Windows features enabled; wsl.exe is not active yet.'
    Write-Host '[REBOOT REQUIRED] WSL Windows components were enabled system-wide. Restart Windows once; this repair is registered to reopen after sign-in.' -ForegroundColor Yellow
    return 3010
}

$wslPath = $wslCommand.Source
$distributionState = Get-WslDistributionState -WslPath $wslPath

# A present wsl.exe whose distribution API cannot initialize is a normal state
# immediately after enabling the Windows components. Treat the first occurrence
# as a reboot boundary, not as an installation failure. If the same state remains
# after the registered continuation, fail closed instead of creating a reboot loop.
if ($rebootRequired -or $distributionState.ExitCode -ne 0) {
    if ($continuingAfterReboot) {
        throw "WSL is still unable to enumerate distributions after the reboot continuation. wsl --list --quiet exit=$($distributionState.ExitCode). Output: $($distributionState.Raw)"
    }
    Save-RebootState -Reason "WSL platform activation pending. listExit=$($distributionState.ExitCode)"
    Write-Host '[REBOOT REQUIRED] WSL is installed/enabled system-wide but the platform is not active yet.' -ForegroundColor Yellow
    Write-Host 'Restart Windows once. The repair will reopen automatically for the same Windows user after sign-in.' -ForegroundColor Yellow
    return 3010
}

Write-Host 'WSL platform is active.' -ForegroundColor Green

# Update the Store-delivered WSL package when possible. A failed normal update gets
# one documented web-download fallback; this is bounded and does not loop.
& $wslPath --update
$updateExit = $LASTEXITCODE
if ($updateExit -ne 0) {
    Write-Host "Normal WSL update returned $updateExit; trying --web-download once." -ForegroundColor Yellow
    Invoke-NativeChecked -FilePath $wslPath -ArgumentList @('--update', '--web-download') | Out-Null
}

Invoke-NativeChecked -FilePath $wslPath -ArgumentList @('--set-default-version', '2') | Out-Null

$distributionState = Get-WslDistributionState -WslPath $wslPath
if ($distributionState.Names -notcontains 'Ubuntu') {
    Write-Host "Ubuntu is not registered for Windows user '$env:USERNAME'. Installing it now..." -ForegroundColor Cyan
    $installExit = Invoke-NativeChecked -FilePath $wslPath -ArgumentList @('--install', '-d', 'Ubuntu', '--web-download', '--no-launch') -AllowedExitCodes @(0, 3010)
    if ($installExit -eq 3010) {
        Save-RebootState -Reason 'Ubuntu installation requested a Windows restart.'
        Write-Host '[REBOOT REQUIRED] Ubuntu installation requested a restart. Continuation is registered.' -ForegroundColor Yellow
        return 3010
    }

    $registered = $false
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        Start-Sleep -Seconds 2
        $distributionState = Get-WslDistributionState -WslPath $wslPath
        if ($distributionState.ExitCode -ne 0) {
            break
        }
        if ($distributionState.Names -contains 'Ubuntu') {
            $registered = $true
            break
        }
    }

    if (-not $registered) {
        if ($distributionState.ExitCode -ne 0 -and -not $continuingAfterReboot) {
            Save-RebootState -Reason "Ubuntu install completed but WSL became restart-pending. listExit=$($distributionState.ExitCode)"
            Write-Host '[REBOOT REQUIRED] Ubuntu installation completed but WSL needs one restart before registration is visible. Continuation is registered.' -ForegroundColor Yellow
            return 3010
        }
        throw "Ubuntu installation returned successfully but Ubuntu did not register within 60 seconds. Current distro list: $($distributionState.Names -join ', ')"
    }
}

Write-Host '[PASS] Ubuntu is registered.' -ForegroundColor Green

Invoke-NativeChecked -FilePath $wslPath -ArgumentList @('--set-version', 'Ubuntu', '2') | Out-Null

# The Microsoft Ubuntu package has a per-user first-run step. Do not invent a
# password or silently create passwordless sudo. Launch that official first-run
# experience when the default user cannot yet execute a command, then verify it.
& $wslPath -d Ubuntu -- bash -lc 'printf AGENT_SWITCHBOARD_UBUNTU_READY' | Out-Null
$defaultUserExit = $LASTEXITCODE
if ($defaultUserExit -ne 0) {
    Write-Host ''
    Write-Host 'Ubuntu is installed but its per-user first-run initialization is not complete.' -ForegroundColor Yellow
    Write-Host 'The Ubuntu setup will open now. Create the requested Linux username/password.' -ForegroundColor Yellow
    Write-Host "When the Linux prompt appears, type 'exit' once to return to this repair." -ForegroundColor Yellow
    & $wslPath -d Ubuntu
    if ($LASTEXITCODE -ne 0) {
        throw "Ubuntu first-run initialization exited with code $LASTEXITCODE."
    }

    & $wslPath -d Ubuntu -- bash -lc 'printf AGENT_SWITCHBOARD_UBUNTU_READY' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Ubuntu is registered but the initialized default Linux user still cannot execute a non-interactive Bash command.'
    }
}

Clear-RebootState

$verboseList = @(& $wslPath --list --verbose 2>&1)
Write-Host ($verboseList -join [Environment]::NewLine)
Write-Host ''
Write-Host 'WSL Ubuntu repair verified:' -ForegroundColor Green
Write-Host '  - Windows Subsystem for Linux feature enabled system-wide' -ForegroundColor Green
Write-Host '  - Virtual Machine Platform feature enabled system-wide' -ForegroundColor Green
Write-Host '  - WSL platform active' -ForegroundColor Green
Write-Host '  - Ubuntu registered for the current Windows user' -ForegroundColor Green
Write-Host '  - Ubuntu default user can execute Bash non-interactively' -ForegroundColor Green
Write-Host 'P00 may now be rerun.' -ForegroundColor Green
return 0
