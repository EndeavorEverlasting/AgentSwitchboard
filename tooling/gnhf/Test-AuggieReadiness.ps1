[CmdletBinding()]
param(
    [string]$AuggiePath,
    [string]$OutputPath,
    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 15,
    [switch]$FailIfNotReady
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-BoundedProbe {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][int]$Timeout
    )

    $result = [ordered]@{
        exitCode = $null
        timedOut = $false
        startError = $null
        output = ''
    }

    $process = $null
    try {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardInput = $true
        $psi.CreateNoWindow = $true

        if ($FilePath.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase)) {
            $pwsh = Get-Command pwsh -ErrorAction Stop
            $psi.FileName = $pwsh.Source
            foreach ($prefix in @('-NoLogo', '-NoProfile', '-File', $FilePath)) {
                [void]$psi.ArgumentList.Add($prefix)
            }
        }
        elseif ($FilePath.EndsWith('.cmd', [StringComparison]::OrdinalIgnoreCase) -or $FilePath.EndsWith('.bat', [StringComparison]::OrdinalIgnoreCase)) {
            $cmd = if ($env:ComSpec) { $env:ComSpec } else { (Get-Command cmd.exe -ErrorAction Stop).Source }
            $psi.FileName = $cmd
            foreach ($prefix in @('/d', '/s', '/c', $FilePath)) {
                [void]$psi.ArgumentList.Add($prefix)
            }
        }
        else {
            $psi.FileName = $FilePath
        }

        foreach ($argument in $ArgumentList) {
            [void]$psi.ArgumentList.Add($argument)
        }

        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($Timeout * 1000)) {
            $result.timedOut = $true
            try { $process.Kill($true) } catch {}
            try { $process.WaitForExit() } catch {}
        }
        else {
            $result.exitCode = $process.ExitCode
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $result.output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
    catch {
        $result.startError = $_.Exception.Message
    }
    finally {
        if ($process) { $process.Dispose() }
    }

    return [pscustomobject]$result
}

function Get-ProbeMetadata {
    param([Parameter(Mandatory)]$Probe)
    return [ordered]@{
        exitCode = $Probe.exitCode
        timedOut = [bool]$Probe.timedOut
        startError = $Probe.startError
    }
}

$resolvedAuggie = $null
if (-not [string]::IsNullOrWhiteSpace($AuggiePath)) {
    $resolvedAuggie = (Resolve-Path -LiteralPath $AuggiePath -ErrorAction Stop).Path
}
else {
    $command = Get-Command auggie -ErrorAction SilentlyContinue
    if ($command) { $resolvedAuggie = $command.Source }
}

$versionProbe = $null
$helpProbe = $null
$version = $null
$acpAdvertised = $false
$printAdvertised = $false
$classification = 'command-not-found'

if ($resolvedAuggie) {
    $versionProbe = Invoke-BoundedProbe -FilePath $resolvedAuggie -ArgumentList @('--version') -Timeout $TimeoutSeconds
    if (-not $versionProbe.timedOut -and $versionProbe.exitCode -eq 0 -and -not $versionProbe.startError) {
        if (-not [string]::IsNullOrWhiteSpace($versionProbe.output)) {
            $version = ($versionProbe.output -split '\r?\n' | Select-Object -First 1).Trim()
        }
        else {
            $version = 'detected'
        }

        $helpProbe = Invoke-BoundedProbe -FilePath $resolvedAuggie -ArgumentList @('--help') -Timeout $TimeoutSeconds
        if (-not $helpProbe.timedOut -and $helpProbe.exitCode -eq 0 -and -not $helpProbe.startError) {
            $acpAdvertised = [regex]::IsMatch($helpProbe.output, '(?m)(?:^|\s)--acp(?:\s|$)')
            $printAdvertised = [regex]::IsMatch($helpProbe.output, '(?m)(?:^|\s)--print(?:\s|$)')
            $classification = if ($acpAdvertised) { 'ready' } else { 'acp-not-advertised' }
        }
        else {
            $classification = 'help-probe-failed'
        }
    }
    else {
        $classification = 'version-probe-failed'
    }
}

$status = if ($classification -eq 'ready') { 'ready' } else { 'blocked' }
$runId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $base = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\auggie-readiness\runs'
    }
    else {
        Join-Path ([IO.Path]::GetTempPath()) 'AgentSwitchboard/auggie-readiness/runs'
    }
    $OutputPath = Join-Path (Join-Path $base $runId) 'auggie-readiness-result.json'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force

$result = [ordered]@{
    schema = 'agentswitchboard.auggie-readiness-result.v1'
    runId = $runId
    status = $status
    classification = $classification
    commandPath = $resolvedAuggie
    version = $version
    versionProbe = if ($versionProbe) { Get-ProbeMetadata -Probe $versionProbe } else { $null }
    helpProbe = if ($helpProbe) { Get-ProbeMetadata -Probe $helpProbe } else { $null }
    capabilities = [ordered]@{
        acpServerAdvertised = $acpAdvertised
        nonInteractivePrintAdvertised = $printAdvertised
        acpAgentSpec = if ($acpAdvertised) { 'acp:auggie --acp' } else { $null }
    }
    safety = [ordered]@{
        authenticationChecked = $false
        acpServerStarted = $false
        rawHelpPersisted = $false
        repositoryMutationAttempted = $false
    }
    proofLevel = 'cli-readiness'
    proofCeiling = 'Proves command discovery plus bounded --version/--help execution and advertised CLI capabilities only. It does not prove authentication, ACP handshake, model/provider readiness, repository mutation, terminal rendering, or unattended GNHF execution.'
    evidencePath = $OutputPath
}

$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
Write-Host "STATUS=$status"
Write-Host "CLASSIFICATION=$classification"
Write-Host "ACP_ADVERTISED=$acpAdvertised"
Write-Host "PRINT_ADVERTISED=$printAdvertised"
Write-Host "ARTIFACT=$OutputPath"
Write-Host "PROOF_CEILING=$($result.proofCeiling)"

if ($FailIfNotReady -and $status -ne 'ready') {
    throw "Auggie is not readiness-proven. Classification: $classification. Evidence: $OutputPath"
}
