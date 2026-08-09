Set-StrictMode -Version Latest

function Resolve-WayfinderPython {
    [CmdletBinding()]
    param(
        [string]$PythonPath,
        [string]$RootPath = (Get-Location).Path
    )

    $RootPath = (Resolve-Path -LiteralPath $RootPath).Path

    function Resolve-Candidate {
        param(
            [Parameter(Mandatory = $true)][string]$Candidate,
            [Parameter(Mandatory = $true)][string]$Source
        )

        $commandPath = $null
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            $commandPath = (Resolve-Path -LiteralPath $Candidate).Path
        }
        else {
            $command = Get-Command $Candidate -ErrorAction SilentlyContinue
            if ($command) { $commandPath = if ($command.Source) { $command.Source } else { $command.Path } }
        }
        if ([string]::IsNullOrWhiteSpace($commandPath)) { return $null }

        $probe = @(& $commandPath -c 'import json,sys; print(json.dumps({"executable":sys.executable,"major":sys.version_info.major,"version":sys.version.split()[0]}))' 2>&1)
        if ($LASTEXITCODE -ne 0) { return $null }

        $payload = $null
        for ($index = $probe.Count - 1; $index -ge 0; $index--) {
            try {
                $candidatePayload = [string]$probe[$index] | ConvertFrom-Json -ErrorAction Stop
                if ($candidatePayload.executable) {
                    $payload = $candidatePayload
                    break
                }
            }
            catch { continue }
        }
        if (-not $payload -or $payload.major -ne 3) { return $null }

        $reportedPath = [string]$payload.executable
        if (Test-Path -LiteralPath $reportedPath -PathType Leaf) { $reportedPath = (Resolve-Path -LiteralPath $reportedPath).Path }

        return [pscustomobject]@{
            Path = $reportedPath
            Source = $Source
            Version = [string]$payload.version
            RequestedPath = $commandPath
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) {
        $binding = Resolve-Candidate -Candidate $PythonPath -Source 'explicit-parameter'
        if (-not $binding) { throw "Explicit Wayfinder PythonPath is not a usable Python 3 interpreter: $PythonPath" }
        return $binding
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ASB_WAYFINDER_PYTHON)) {
        $binding = Resolve-Candidate -Candidate $env:ASB_WAYFINDER_PYTHON -Source 'ASB_WAYFINDER_PYTHON'
        if (-not $binding) { throw "ASB_WAYFINDER_PYTHON is set but is not a usable Python 3 interpreter: $($env:ASB_WAYFINDER_PYTHON)" }
        return $binding
    }

    if (-not [string]::IsNullOrWhiteSpace($env:VIRTUAL_ENV)) {
        foreach ($relative in @('Scripts/python.exe', 'bin/python')) {
            $candidate = Join-Path $env:VIRTUAL_ENV $relative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $binding = Resolve-Candidate -Candidate $candidate -Source 'VIRTUAL_ENV'
                if ($binding) { return $binding }
            }
        }
        throw "VIRTUAL_ENV is set but does not contain a usable Python 3 interpreter: $($env:VIRTUAL_ENV)"
    }

    foreach ($relative in @('.venv/Scripts/python.exe', '.venv/bin/python')) {
        $candidate = Join-Path $RootPath $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $binding = Resolve-Candidate -Candidate $candidate -Source 'repository-.venv'
            if ($binding) { return $binding }
        }
    }

    foreach ($name in @('python', 'python3')) {
        $binding = Resolve-Candidate -Candidate $name -Source 'PATH'
        if ($binding) { return $binding }
    }

    throw 'Unable to resolve a usable Python 3 interpreter for the Wayfinder harness. Pass -PythonPath, set ASB_WAYFINDER_PYTHON, activate VIRTUAL_ENV, create .venv, or install Python on PATH.'
}
