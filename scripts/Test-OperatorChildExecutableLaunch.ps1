[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ExecutablePath,
    [string[]]$ArgumentList = @(),
    [string]$Label = 'child-executable',
    [ValidateRange(1, 120)][int]$TimeoutSeconds = 10,
    [string]$OutputRoot,
    [switch]$SurfaceOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-NativeArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Limit-Text {
    param([AllowNull()][string]$Value, [int]$Maximum = 4096)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    if ($Value.Length -le $Maximum) { return $Value }
    return $Value.Substring(0, $Maximum) + "`n[truncated; originalLength=$($Value.Length)]"
}

$started = Get-Date
$runId = '{0}-{1}' -f $started.ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $base = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\operator-command-delivery\runs'
    }
    else {
        Join-Path ([IO.Path]::GetTempPath()) 'AgentSwitchboard/operator-command-delivery/runs'
    }
    $OutputRoot = Join-Path $base $runId
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$null = New-Item -ItemType Directory -Path $OutputRoot -Force
$resultPath = Join-Path $OutputRoot 'child-executable-launch-result.json'

$result = [ordered]@{
    schema = 'agentswitchboard.operator-child-executable-launch-result.v1'
    runId = $runId
    startedAt = $started.ToUniversalTime().ToString('o')
    completedAt = $null
    label = $Label
    executablePath = $ExecutablePath
    arguments = @($ArgumentList)
    status = 'running'
    startError = $null
    exitCode = $null
    timedOut = $false
    stdout = ''
    stderr = ''
    proofLevel = 'not-proven'
    proofCeiling = 'No executable launch proof has been observed yet.'
    evidencePath = $resultPath
}

$process = $null
$exitCode = 0
try {
    if ($SurfaceOnly) {
        $result.status = 'surface-passed'
        $result.proofLevel = 'surface-only'
        $result.proofCeiling = 'Proves the child-executable launch probe can load and emit its evidence contract without starting the requested executable.'
    }
    else {
        $resolved = (Resolve-Path -LiteralPath $ExecutablePath -ErrorAction Stop).Path
        $result.executablePath = $resolved

        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $resolved
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        if ($ArgumentList.Count -gt 0) {
            $psi.Arguments = (@($ArgumentList | ForEach-Object { ConvertTo-NativeArgument -Value ([string]$_) }) -join ' ')
        }

        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $psi
        $startedProcess = $false
        try {
            [void]$process.Start()
            $startedProcess = $true
        }
        catch {
            $result.status = 'blocked'
            $result.startError = $_.Exception.Message
            $result.stderr = $_.Exception.Message
            $result.proofLevel = 'child-executable-launch-blocked'
            $result.proofCeiling = 'The exact executable path was resolved, but process creation was blocked before downstream runtime work began.'
            $exitCode = 41
        }

        if ($startedProcess) {
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $result.status = 'timed-out'
                $result.timedOut = $true
                $result.proofLevel = 'child-executable-launch-timeout'
                $result.proofCeiling = 'The executable started but did not complete the bounded probe in time; downstream runtime work remains unproven.'
                try { $process.Kill() } catch {}
                try { $process.WaitForExit() } catch {}
                $exitCode = 42
            }
            else {
                $result.exitCode = $process.ExitCode
                if ($process.ExitCode -eq 0) {
                    $result.status = 'passed'
                    $result.proofLevel = 'child-executable-launch'
                    $result.proofCeiling = 'Proves this exact executable can start and complete only the supplied bounded arguments. It does not prove downstream launcher, tmux, GUI, provider, or operator behavior.'
                }
                else {
                    $result.status = 'child-nonzero'
                    $result.proofLevel = 'child-executable-launched-nonzero'
                    $result.proofCeiling = 'Proves process creation succeeded, but the bounded child command returned nonzero; downstream runtime work remains unproven.'
                    $exitCode = $process.ExitCode
                    if ($exitCode -lt 1 -or $exitCode -gt 255) { $exitCode = 43 }
                }
            }

            $result.stdout = Limit-Text -Value ($stdoutTask.GetAwaiter().GetResult()).Trim()
            $result.stderr = Limit-Text -Value ($stderrTask.GetAwaiter().GetResult()).Trim()
        }
    }
}
catch {
    if ($result.status -eq 'running') {
        $result.status = 'blocked'
        $result.startError = $_.Exception.Message
        $result.stderr = $_.Exception.Message
        $result.proofLevel = 'child-executable-launch-blocked'
        $result.proofCeiling = 'Executable resolution or process creation failed before downstream runtime work began.'
        $exitCode = 41
    }
}
finally {
    $result.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    if ($process) { $process.Dispose() }
    Write-Host "STATUS=$($result.status)"
    Write-Host "EXECUTABLE=$($result.executablePath)"
    Write-Host "CHILD_EXIT_CODE=$($result.exitCode)"
    Write-Host "ARTIFACT=$resultPath"
}

exit $exitCode
