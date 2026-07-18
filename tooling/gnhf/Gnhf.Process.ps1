Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-GnhfProcessStartInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
        throw "Working directory not found: $WorkingDirectory"
    }

    $resolvedFile = $FilePath
    if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
        $resolvedFile = (Get-Item -LiteralPath $FilePath -Force).FullName
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = (Get-Item -LiteralPath $WorkingDirectory -Force).FullName

    if ($resolvedFile.EndsWith(".ps1", [StringComparison]::OrdinalIgnoreCase)) {
        $pwsh = Get-Command pwsh -ErrorAction Stop
        $psi.FileName = $pwsh.Source
        foreach ($argument in @("-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $resolvedFile)) {
            [void]$psi.ArgumentList.Add($argument)
        }
    }
    elseif ($resolvedFile.EndsWith(".cmd", [StringComparison]::OrdinalIgnoreCase) -or
            $resolvedFile.EndsWith(".bat", [StringComparison]::OrdinalIgnoreCase)) {
        $psi.FileName = if ($env:ComSpec) { $env:ComSpec } else { "cmd.exe" }
        foreach ($argument in @("/d", "/s", "/c", $resolvedFile)) {
            [void]$psi.ArgumentList.Add($argument)
        }
    }
    else {
        $psi.FileName = $resolvedFile
    }

    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add($argument)
    }

    return $psi
}

function Invoke-GnhfBoundedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [ValidateRange(1, 600)][int]$TimeoutSeconds = 30,
        [AllowEmptyString()][string]$StandardInput = ""
    )

    $result = [ordered]@{
        filePath = $FilePath
        arguments = @($ArgumentList)
        exitCode = $null
        timedOut = $false
        output = ""
        dispatch = "native"
    }

    $psi = New-GnhfProcessStartInfo -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory
    if ($FilePath.EndsWith(".ps1", [StringComparison]::OrdinalIgnoreCase)) {
        $result.dispatch = "pwsh-file"
    }
    elseif ($FilePath.EndsWith(".cmd", [StringComparison]::OrdinalIgnoreCase) -or
            $FilePath.EndsWith(".bat", [StringComparison]::OrdinalIgnoreCase)) {
        $result.dispatch = "cmd-file"
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        if ($StandardInput) {
            $process.StandardInput.Write($StandardInput)
        }
        $process.StandardInput.Close()

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $result.timedOut = $true
            try {
                $process.Kill($true)
                if (-not $process.WaitForExit(5000)) {
                    throw "process did not exit within five seconds after termination"
                }
            }
            catch {
                throw "Timed-out process could not be terminated safely: $($_.Exception.Message)"
            }
        }
        else {
            $result.exitCode = $process.ExitCode
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $result.output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
    finally {
        $process.Dispose()
    }

    return [pscustomobject]$result
}
