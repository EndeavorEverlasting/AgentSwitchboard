[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot,
    [string]$BaseRef = 'origin/main',
    [switch]$ListOnly,
    [switch]$IncludeAllPathGates
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $tempRoot = [Environment]::GetEnvironmentVariable('RUNNER_TEMP')
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        $tempRoot = [IO.Path]::GetTempPath()
    }
    $OutputRoot = Join-Path $tempRoot ('agentswitchboard-merge-gate-local-proof-' + [Guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path

$manifestPath = Join-Path $RootPath '.ai/harness/merge-gate-local.manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing merge-gate-local manifest: $manifestPath"
}

function Get-PythonCommand {
    foreach ($candidate in @('python3', 'python')) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $cmd) { return $cmd.Source }
    }
    return $null
}

function Get-GitHead([string]$RepositoryPath) {
    $text = (& git -C $RepositoryPath rev-parse HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($text)) {
        return 'UNKNOWN'
    }
    return $text
}

function Get-ChangedFiles([string]$RepositoryPath, [string]$BaseReference) {
    $text = (& git -C $RepositoryPath diff --name-only $BaseReference 2>$null | Out-String)
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "git diff failed against $BaseReference; treating as no changes"
        return @()
    }
    $lines = $text -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    return @($lines)
}

function Test-PathMatch([string]$FilePath, [string]$Pattern) {
    # Simple glob matching for workflow paths filters
    # Supports ** for directory recursion and * for single segment wildcard
    $Pattern = $Pattern.Replace('\', '/')
    $FilePath = $FilePath.Replace('\', '/')
    
    if ($Pattern -match '\*\*') {
        # Pattern contains **, convert to regex
        $regexPattern = '^' + [regex]::Escape($Pattern).Replace('\*\*/', '.*').Replace('\*\*', '.*').Replace('\*', '[^/]*') + '$'
        return $FilePath -match $regexPattern
    }
    elseif ($Pattern -match '\*') {
        # Pattern contains single *, convert to regex
        $regexPattern = '^' + [regex]::Escape($Pattern).Replace('\*', '[^/]*') + '$'
        return $FilePath -match $regexPattern
    }
    else {
        # Exact match
        return $FilePath -eq $Pattern
    }
}

function Test-GatePathActivated([object]$Gate, [string[]]$ChangedFiles) {
    if ($Gate.tier -eq 'always-on') {
        return $true
    }
    foreach ($file in $ChangedFiles) {
        foreach ($pattern in $Gate.paths) {
            if (Test-PathMatch -FilePath $file -Pattern $pattern) {
                return $true
            }
        }
    }
    return $false
}

function Get-CurrentHost {
    if ($IsLinux) {
        return 'linux'
    }
    elseif ($IsWindows -or ($null -eq $IsWindows)) {
        return 'windows'
    }
    elseif ($IsMacOS) {
        return 'macos'
    }
    else {
        return 'unknown'
    }
}

function Test-HostCapable([string]$RequiredHost, [string]$CurrentHost) {
    if ($RequiredHost -eq 'any') {
        return $true
    }
    if ($RequiredHost -eq 'admin-box') {
        # Admin box detection would require additional context; fail closed
        return $false
    }
    return $CurrentHost -eq $RequiredHost
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Combined = ((([string]$stdoutTask.GetAwaiter().GetResult()) + [Environment]::NewLine + ([string]$stderrTask.GetAwaiter().GetResult())).Trim())
        }
    }
    finally {
        $process.Dispose()
    }
}

# Load manifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

# Get current state
$candidateSha = Get-GitHead -RepositoryPath $RootPath
$currentHost = Get-CurrentHost
$changedFiles = Get-ChangedFiles -RepositoryPath $RootPath -BaseReference $BaseRef

Write-Host ("MERGE_GATE_LOCAL candidateSha={0} baseRef={1} changedFiles={2} currentHost={3} outputRoot={4}" -f $candidateSha, $BaseRef, $changedFiles.Count, $currentHost, $OutputRoot)

# Select gates
$selectedGates = [System.Collections.Generic.List[object]]::new()
foreach ($gate in $manifest.gates) {
    if ($IncludeAllPathGates) {
        [void]$selectedGates.Add($gate)
    }
    elseif (Test-GatePathActivated -Gate $gate -ChangedFiles $changedFiles) {
        [void]$selectedGates.Add($gate)
    }
}

if ($ListOnly) {
    Write-Host "`nSelected gates ($($selectedGates.Count)):"
    foreach ($gate in $selectedGates) {
        Write-Host ("  [{0}] {1} (tier={2}, host={3}, commands={4})" -f $gate.id, $gate.workflow, $gate.tier, $gate.host, $gate.commands.Count)
    }
    exit 0
}

# Check for pwsh availability
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($null -eq $pwsh) {
    Write-Error "FAIL_CLOSED: pwsh not found; cannot execute PowerShell gates"
    exit 1
}

# Check for python availability
$python = Get-PythonCommand
if ($null -eq $python) {
    Write-Error "FAIL_CLOSED: python not found; cannot execute Python gates"
    exit 1
}

# Execute gates
$steps = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($gate in $selectedGates) {
    Write-Host ("`n=== Gate: {0} ===" -f $gate.id)
    
    # Check host capability
    if (-not (Test-HostCapable -RequiredHost $gate.host -CurrentHost $currentHost)) {
        $blockReason = "Host capability mismatch: gate requires {0}, current host is {1}" -f $gate.host, $currentHost
        Write-Host ("BLOCKED: {0}" -f $blockReason)
        $steps.Add([ordered]@{
                id           = $gate.id
                tier         = $gate.tier
                workflow     = $gate.workflow
                job          = $gate.job
                status       = 'BLOCKED_HOST_REQUIRED'
                exitCode     = -1
                detail       = $blockReason
                next         = ("Run on {0} host or update gate host requirement" -f $gate.host)
            })
        $failures.Add(("{0}: {1}" -f $gate.id, $blockReason))
        continue
    }
    
    # Execute commands
    $gateOk = $true
    $gateDetails = [System.Collections.Generic.List[string]]::new()
    $gateExitCodes = [System.Collections.Generic.List[int]]::new()
    
    foreach ($cmd in $gate.commands) {
        Write-Host ("Running: {0}" -f $cmd)
        
        # Parse command
        $parts = $cmd -split '\s+', 2
        $executable = $parts[0]
        $args = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        
        # Resolve executable
        $resolvedExe = $null
        if ($executable -eq 'pwsh') {
            $resolvedExe = $pwsh.Source
        }
        elseif ($executable -eq 'python') {
            $resolvedExe = $python
        }
        elseif ($executable -eq 'bash') {
            $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
            if ($null -eq $bashCmd) {
                Write-Host "FAIL: bash not found"
                $gateOk = $false
                [void]$gateDetails.Add("bash not found")
                [void]$gateExitCodes.Add(-1)
                continue
            }
            $resolvedExe = $bashCmd.Source
        }
        elseif ($executable -eq 'git') {
            $gitCmd = Get-Command git -ErrorAction SilentlyContinue
            if ($null -eq $gitCmd) {
                Write-Host "FAIL: git not found"
                $gateOk = $false
                [void]$gateDetails.Add("git not found")
                [void]$gateExitCodes.Add(-1)
                continue
            }
            $resolvedExe = $gitCmd.Source
        }
        else {
            Write-Host ("FAIL: unknown executable: {0}" -f $executable)
            $gateOk = $false
            [void]$gateDetails.Add("unknown executable: $executable")
            [void]$gateExitCodes.Add(-1)
            continue
        }
        
        # Split arguments properly
        $argList = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace($args)) {
            # Simple argument splitting (doesn't handle all edge cases)
            $currentArg = ''
            $inQuotes = $false
            for ($i = 0; $i -lt $args.Length; $i++) {
                $c = $args[$i]
                if ($c -eq '"' -or $c -eq "'") {
                    $inQuotes = -not $inQuotes
                }
                elseif ($c -eq ' ' -and -not $inQuotes) {
                    if ($currentArg) {
                        [void]$argList.Add($currentArg)
                        $currentArg = ''
                    }
                }
                else {
                    $currentArg += $c
                }
            }
            if ($currentArg) {
                [void]$argList.Add($currentArg)
            }
        }
        
        # Execute
        $result = Invoke-CapturedProcess -FilePath $resolvedExe -ArgumentList $argList -WorkingDirectory $RootPath
        [void]$gateExitCodes.Add($result.ExitCode)
        
        if ($result.ExitCode -eq 0) {
            Write-Host "PASS"
            [void]$gateDetails.Add("command passed")
        }
        else {
            Write-Host ("FAIL: exit code {0}" -f $result.ExitCode)
            if ($result.Combined) {
                Write-Host $result.Combined
            }
            $gateOk = $false
            [void]$gateDetails.Add(("command failed with exit code {0}" -f $result.ExitCode))
        }
    }
    
    # Record step
    $stepStatus = if ($gateOk) { 'PASS' } else { 'FAIL' }
    $steps.Add([ordered]@{
            id           = $gate.id
            tier         = $gate.tier
            workflow     = $gate.workflow
            job          = $gate.job
            status       = $stepStatus
            exitCodes    = @($gateExitCodes)
            detail       = ($gateDetails -join '; ')
            commandCount = $gate.commands.Count
        })
    
    if (-not $gateOk) {
        $failures.Add(("{0} gate failed" -f $gate.id))
    }
}

# Validate always-on gates were executed
$alwaysOnExecuted = $false
foreach ($step in $steps) {
    if ($step.tier -eq 'always-on') {
        $alwaysOnExecuted = $true
        break
    }
}

if (-not $alwaysOnExecuted) {
    Write-Error "FAIL_CLOSED: No always-on gates were executed"
    $failures.Add("No always-on gates executed")
}

$overall = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$packet = [ordered]@{
    schema           = 'agentswitchboard.merge-gate-local.proof.v1'
    generatedUtc     = [DateTime]::UtcNow.ToString('o')
    candidateSha     = $candidateSha
    baseRef          = $BaseRef
    changedFileCount = $changedFiles.Count
    currentHost      = $currentHost
    result           = $overall
    proofCeiling     = [string]$manifest.proofCeiling
    gatesSelected    = $selectedGates.Count
    gatesExecuted    = $steps.Count
    steps            = @($steps)
    failures         = @($failures)
}

$jsonPath = Join-Path $OutputRoot 'merge-gate-local-proof-packet.json'
$mdPath = Join-Path $OutputRoot 'merge-gate-local-proof-packet.md'
($packet | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $jsonPath -Encoding utf8

$md = [System.Collections.Generic.List[string]]::new()
[void]$md.Add('# Merge gate local proof packet')
[void]$md.Add('')
[void]$md.Add(('Result: **{0}**' -f $overall))
[void]$md.Add(('Candidate SHA: `{0}`' -f $candidateSha))
[void]$md.Add(('Base ref: `{0}`' -f $BaseRef))
[void]$md.Add(('Changed files: {0}' -f $changedFiles.Count))
[void]$md.Add(('Current host: {0}' -f $currentHost))
[void]$md.Add(('Gates selected: {0}' -f $selectedGates.Count))
[void]$md.Add('')
[void]$md.Add(('**Proof ceiling:** {0}' -f [string]$manifest.proofCeiling))
[void]$md.Add('')
[void]$md.Add('## Gate results')
[void]$md.Add('')
[void]$md.Add('| Gate | Tier | Status | Detail |')
[void]$md.Add('|---|---|---|---|')
foreach ($step in $steps) {
    $detail = ([string]$step.detail -replace '\|', '/') -replace '\r?\n', ' '
    [void]$md.Add(('| {0} | {1} | {2} | {3} |' -f $step.id, $step.tier, $step.status, $detail))
}
($md -join [Environment]::NewLine) | Set-Content -LiteralPath $mdPath -Encoding utf8

Write-Host ("`nMERGE_GATE_LOCAL_PROOF_PACKET_JSON={0}" -f $jsonPath)
Write-Host ("MERGE_GATE_LOCAL_PROOF_PACKET_MD={0}" -f $mdPath)
Write-Host ("MERGE_GATE_LOCAL_PROOF: {0}" -f $overall)

if ($overall -ne 'PASS') {
    exit 1
}
exit 0
