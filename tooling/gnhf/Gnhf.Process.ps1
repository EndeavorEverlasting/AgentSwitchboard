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

function Resolve-OpenCodeNativeExecutable {
    [CmdletBinding()]
    param(
        [string]$PreferredPath
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($PreferredPath) {
        [void]$candidates.Add($PreferredPath)
    }

    $command = Get-Command opencode -ErrorAction SilentlyContinue
    if ($command) {
        [void]$candidates.Add($command.Source)
    }

    foreach ($relative in @(
        (Join-Path $env:APPDATA 'npm\node_modules\opencode-ai\bin\opencode.exe'),
        (Join-Path $env:LOCALAPPDATA 'npm\node_modules\opencode-ai\bin\opencode.exe')
    )) {
        [void]$candidates.Add($relative)
    }

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }

        $item = Get-Item -LiteralPath $candidate -Force
        if ($item.FullName.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
            return $item.FullName
        }

        if ($item.FullName.EndsWith('.cmd', [StringComparison]::OrdinalIgnoreCase) -or
            $item.FullName.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase) -or
            $item.Name -eq 'opencode') {
            $shimDir = $item.DirectoryName
            $fromShim = Join-Path $shimDir 'node_modules\opencode-ai\bin\opencode.exe'
            if (Test-Path -LiteralPath $fromShim -PathType Leaf) {
                return (Get-Item -LiteralPath $fromShim -Force).FullName
            }
        }
    }

    throw "Unable to resolve the native OpenCode executable (opencode.exe). Install OpenCode, then rerun AgentSwitchboard setup."
}

function Set-GnhfOpenCodeNativePathOverride {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OpenCodeExePath,
        [string]$ConfigPath = (Join-Path $HOME '.gnhf\config.yml')
    )

    if (-not (Test-Path -LiteralPath $OpenCodeExePath -PathType Leaf)) {
        throw "OpenCode executable not found: $OpenCodeExePath"
    }
    if (-not $OpenCodeExePath.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
        throw "GNHF agentPathOverride.opencode must point at opencode.exe on Windows. Refusing: $OpenCodeExePath"
    }

    $configDir = Split-Path -Parent $ConfigPath
    [void](New-Item -ItemType Directory -Path $configDir -Force)

    $escaped = $OpenCodeExePath.Replace('\', '/')
    $block = @(
        '# Managed by AgentSwitchboard provider-route installer.',
        '# Absolute opencode.ps1/.cmd paths break GNHF on Windows because it spawns with shell:true.',
        'agentPathOverride:',
        "  opencode: $escaped"
    ) -join [Environment]::NewLine

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        Set-Content -LiteralPath $ConfigPath -Value ($block + [Environment]::NewLine) -Encoding utf8
        return [pscustomobject]@{
            configPath = $ConfigPath
            openCodeExePath = $OpenCodeExePath
            action = 'created'
        }
    }

    $existing = Get-Content -LiteralPath $ConfigPath -Raw
    if ($existing -match '(?m)^agentPathOverride:\s*\r?\n(?:[ \t]+.+\r?\n)*') {
        $replacement = "agentPathOverride:`r`n  opencode: $escaped`r`n"
        $updated = [regex]::Replace($existing, '(?m)^agentPathOverride:\s*\r?\n(?:[ \t]+.+\r?\n)*', $replacement, 1)
    }
    else {
        $updated = $existing.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine
    }

    if ($updated -ne $existing) {
        $backup = "$ConfigPath.agentswitchboard.bak"
        Copy-Item -LiteralPath $ConfigPath -Destination $backup -Force
        Set-Content -LiteralPath $ConfigPath -Value $updated -Encoding utf8NoBOM
        return [pscustomobject]@{
            configPath = $ConfigPath
            openCodeExePath = $OpenCodeExePath
            action = 'updated'
            backupPath = $backup
        }
    }

    return [pscustomobject]@{
        configPath = $ConfigPath
        openCodeExePath = $OpenCodeExePath
        action = 'unchanged'
    }
}

function Test-OpenCodeServeReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OpenCodeExePath,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [ValidateRange(5, 120)][int]$TimeoutSeconds = 30
    )

    if (-not (Test-Path -LiteralPath $OpenCodeExePath -PathType Leaf)) {
        throw "OpenCode executable not found for serve preflight: $OpenCodeExePath"
    }

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $listener.Stop()

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $OpenCodeExePath
    foreach ($argument in @('serve', '--hostname', '127.0.0.1', '--port', [string]$port, '--print-logs')) {
        [void]$psi.ArgumentList.Add($argument)
    }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = (Get-Item -LiteralPath $WorkingDirectory -Force).FullName

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $healthy = $false
        $body = ''

        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            if ($process.HasExited) {
                $stdout = $stdoutTask.GetAwaiter().GetResult()
                $stderr = $stderrTask.GetAwaiter().GetResult()
                throw "OpenCode serve exited before becoming ready on port $port. $($stderr.Trim()) $($stdout.Trim())".Trim()
            }

            try {
                $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/global/health" -UseBasicParsing -TimeoutSec 2
                if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                    $healthy = $true
                    $body = [string]$response.Content
                    break
                }
            }
            catch {
                # keep polling until timeout
            }

            Start-Sleep -Milliseconds 250
        }

        if (-not $healthy) {
            throw "Timed out waiting for opencode serve to become ready on port $port during AgentSwitchboard preflight."
        }

        return [pscustomobject]@{
            openCodeExePath = $OpenCodeExePath
            port = $port
            healthy = $true
            body = $body
            elapsedMs = $sw.ElapsedMilliseconds
            dispatch = 'native-exe'
        }
    }
    finally {
        if (-not $process.HasExited) {
            try { $process.Kill($true) } catch { }
            [void]$process.WaitForExit(5000)
        }
        $process.Dispose()
    }
}
