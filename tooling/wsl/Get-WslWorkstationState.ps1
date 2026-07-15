[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$WslExe = "wsl.exe",
    [switch]$IncludeDockerDesktop
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-WslCommand {
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30
    )

    $result = [ordered]@{
        Distribution = $Distribution
        Arguments = $Arguments
        ExitCode = $null
        TimedOut = $false
        Output = ""
    }

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardInput = $true
        $psi.CreateNoWindow = $true
        $psi.FileName = $WslExe
        [void]$psi.ArgumentList.Add("-d")
        [void]$psi.ArgumentList.Add($Distribution)
        foreach ($argument in $Arguments) {
            [void]$psi.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        $process.StandardInput.Close()

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $result.TimedOut = $true
            try {
                $process.Kill($true)
                $process.WaitForExit()
            }
            catch {}
        }
        else {
            $result.ExitCode = $process.ExitCode
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $result.Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
    catch {
        $result.Output = $_.Exception.Message
    }

    return [pscustomobject]$result
}

function Test-WslAvailable {
    $command = Get-Command $WslExe -ErrorAction SilentlyContinue
    if (-not $command) {
        return [pscustomobject]@{
            Available = $false
            Evidence = "wsl.exe not found on PATH."
            WslPath = $null
        }
    }

    try {
        $statusOutput = & $WslExe --status 2>&1
        return [pscustomobject]@{
            Available = $true
            Evidence = "wsl.exe --status succeeded."
            WslPath = $command.Source
            StatusOutput = ($statusOutput -join [Environment]::NewLine).Trim()
        }
    }
    catch {
        return [pscustomobject]@{
            Available = $true
            Evidence = "wsl.exe found but --status failed: $($_.Exception.Message)"
            WslPath = $command.Source
            StatusOutput = $null
        }
    }
}

function Get-WslDistributionList {
    $listOutput = & $WslExe --list --verbose 2>&1
    $lines = @($listOutput | ForEach-Object { [string]$_ })

    $distributions = [System.Collections.Generic.List[object]]::new()

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }
        if ($trimmed -match "^(NAME|---)") {
            continue
        }

        $parts = $trimmed -split "\s{2,}"
        if ($parts.Count -ge 3) {
            $name = $parts[0].TrimStart("* ").Trim()
            $state = $parts[1].Trim()
            $version = $parts[2].Trim()

            $isDefault = $line.Contains("*")
            $isDockerDesktop = $name -eq "docker-desktop" -or $name -match "docker"

            $distributions.Add([pscustomobject]@{
                Name = $name
                State = $state
                Version = $version
                IsDefault = $isDefault
                IsDockerDesktop = $isDockerDesktop
            })
        }
    }

    return @($distributions)
}

function Get-WslDefaultDistribution {
    $statusOutput = & $WslExe --status 2>&1
    foreach ($line in @($statusOutput)) {
        if ($line -match "Default Distribution:\s*(.+)") {
            return $matches[1].Trim()
        }
    }
    return $null
}

function Get-WslDistributionDetails {
    param([Parameter(Mandatory)][string]$Distribution)

    $details = [ordered]@{
        name = $Distribution
        accessible = $false
        shell = $null
        distroIdentity = $null
        systemdState = $null
        git = $null
        tmux = $null
        node = $null
        npm = $null
        agy = $null
        opencode = $null
        goose = $null
    }

    $accessProbe = Invoke-WslCommand -Distribution $Distribution -Arguments @("echo", "ok") -TimeoutSeconds 10
    if ($accessProbe.TimedOut -or $accessProbe.ExitCode -ne 0) {
        $details.accessible = $false
        return $details
    }
    $details.accessible = $true

    $shellProbe = Invoke-WslCommand -Distribution $Distribution -Arguments @("-c", "echo `$SHELL") -TimeoutSeconds 10
    if (-not $shellProbe.TimedOut -and $shellProbe.ExitCode -eq 0) {
        $details.shell = $shellProbe.Output.Trim()
    }

    $identityProbe = Invoke-WslCommand -Distribution $Distribution -Arguments @("-c", "cat /etc/os-release 2>/dev/null | head -5") -TimeoutSeconds 10
    if (-not $identityProbe.TimedOut -and $identityProbe.ExitCode -eq 0) {
        $details.distroIdentity = $identityProbe.Output.Trim()
    }

    $systemdProbe = Invoke-WslCommand -Distribution $Distribution -Arguments @("-c", "systemctl is-system-running 2>/dev/null || echo 'systemd-unavailable'") -TimeoutSeconds 15
    if (-not $systemdProbe.TimedOut) {
        $details.systemdState = $systemdProbe.Output.Trim()
    }

    $toolProbes = @{
        git = @("git", "--version")
        tmux = @("tmux", "-V")
        node = @("node", "--version")
        npm = @("npm", "--version")
        agy = @("agy", "--help")
        opencode = @("opencode", "--version")
        goose = @("goose", "--version")
    }

    foreach ($tool in $toolProbes.Keys) {
        $probeArgs = $toolProbes[$tool]
        $probe = Invoke-WslCommand -Distribution $Distribution -Arguments @("-c", ($probeArgs -join " ")) -TimeoutSeconds 10
        $available = (-not $probe.TimedOut -and $probe.ExitCode -eq 0)
        $version = if ($available -and $probe.Output) {
            ($probe.Output -split "\r?\n" | Select-Object -First 1).Trim()
        }
        else {
            $null
        }

        $details[$tool] = [ordered]@{
            available = $available
            version = $version
            evidence = if ($available) { "$tool detected." } else { "$tool not found or probe failed." }
        }
    }

    return $details
}

$state = [ordered]@{
    schemaVersion = 1
    queriedAt = (Get-Date).ToString("o")
    manifestPath = $ManifestPath
    wsl = [ordered]@{
        available = $false
        evidence = $null
        wslPath = $null
        statusOutput = $null
    }
    distributions = @()
    defaultDistribution = $null
    developerDistributions = @()
    dockerDesktopPresent = $false
}

$wslInfo = Test-WslAvailable
$state.wsl.available = $wslInfo.Available
$state.wsl.evidence = $wslInfo.Evidence
$state.wsl.wslPath = $wslInfo.WslPath
$state.wsl.statusOutput = $wslInfo.StatusOutput

if ($wslInfo.Available) {
    $allDistributions = Get-WslDistributionList
    $state.defaultDistribution = Get-WslDefaultDistribution

    $filteredDistributions = @($allDistributions | Where-Object {
        $IncludeDockerDesktop -or -not $_.IsDockerDesktop
    })

    $state.distributions = @($filteredDistributions | ForEach-Object {
        [ordered]@{
            name = $_.Name
            state = $_.State
            version = $_.Version
            isDefault = $_.IsDefault
            isDockerDesktop = $_.IsDockerDesktop
        }
    })

    $state.dockerDesktopPresent = @($allDistributions | Where-Object { $_.IsDockerDesktop }).Count -gt 0

    $state.developerDistributions = @($allDistributions |
        Where-Object { -not $_.IsDockerDesktop -and $_.State -eq "Running" } |
        ForEach-Object {
            $details = Get-WslDistributionDetails -Distribution $_.Name
            $details
        }
    )
}

if ($ManifestPath -and (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $state.manifestLoaded = $true
    $state.manifestSchemaVersion = $manifest.schemaVersion
}
else {
    $state.manifestLoaded = $false
}

$statePath = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\wsl-setup"
if (-not (Test-Path -LiteralPath $statePath -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $statePath -Force)
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$jsonPath = Join-Path $statePath "wsl-state-$timestamp.json"
$state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM

Write-Host "WSL Workstation State" -ForegroundColor Cyan
Write-Host "WSL available: $($state.wsl.available)" -ForegroundColor $(if ($state.wsl.available) { "Green" } else { "Red" })
Write-Host "Default distribution: $($state.defaultDistribution)"
Write-Host "Developer distributions: $($state.developerDistributions.Count)"
Write-Host "Docker Desktop present: $($state.dockerDesktopPresent)"
Write-Host ""
Write-Host "State saved: $jsonPath" -ForegroundColor Green

return $state
