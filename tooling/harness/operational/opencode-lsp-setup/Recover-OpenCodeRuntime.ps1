[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoPath,
    [string]$ModelId = 'opencode/nemotron-3-ultra-free',
    [string]$Distribution = 'Ubuntu',
    [ValidateRange(30, 900)][int]$InstallTimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

function Stop-Recovery {
    param([Parameter(Mandatory)][string]$Code, [Parameter(Mandatory)][string]$Message)
    throw ([InvalidOperationException]::new("$Code|$Message"))
}

function ConvertFrom-NativeText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace(([char]0).ToString(), [string]::Empty)
}

function ConvertTo-WslBashPayload {
    param([Parameter(Mandatory)][string]$Script)

    return $Script.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [ValidateRange(1, 960)][int]$ProcessTimeoutSeconds = 60
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.FileName = $FilePath
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $timedOut = -not $process.WaitForExit($ProcessTimeoutSeconds * 1000)
    if ($timedOut) {
        try { $process.Kill($true) } catch {}
        try { $process.WaitForExit() } catch {}
    }

    return [pscustomobject]@{
        ExitCode = if ($timedOut) { $null } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = (ConvertFrom-NativeText -Value ($stdoutTask.GetAwaiter().GetResult())).Trim()
        Stderr = (ConvertFrom-NativeText -Value ($stderrTask.GetAwaiter().GetResult())).Trim()
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'OpenCode runtime recovery is Windows-only.'
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'OpenCode runtime recovery requires PowerShell 7.'
}

$RepoPath = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
$runnerPath = Join-Path $RepoPath 'tooling\harness\operational\opencode-lsp-setup\Invoke-OpenCodeLspWorkstationSetup.ps1'
$stateBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
$stateRoot = Join-Path $stateBase 'AgentSwitchboard\opencode-lsp'
$runId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path $stateRoot "runs\$runId"
$null = New-Item -ItemType Directory -Path $runRoot -Force
$receiptPath = Join-Path $runRoot 'opencode-runtime-recovery.json'
$reportPath = Join-Path $runRoot 'opencode-runtime-recovery.md'
$canonicalShim = Join-Path $stateBase 'AgentSwitchboard\bin\opencode.cmd'
$wslPath = Join-Path $env:SystemRoot 'System32\wsl.exe'

$script:stage = 'initialize'
$script:status = 'failed'
$script:failureCode = $null
$script:failureMessage = $null
$script:lastExitCode = $null
$script:lastTimedOut = $false
$script:lastStdoutPresent = $false
$script:lastStderrPresent = $false
$script:initialOpenCodePath = $null
$script:initialVersionExitCode = $null
$script:initialVersionTimedOut = $false
$script:installAttempted = $false
$script:installReason = $null
$script:openCodePath = $null
$script:openCodeVersion = $null
$script:inspectExitCode = $null
$script:inspectFailureCode = $null

function Set-LastResult {
    param([Parameter(Mandatory)]$Result)
    $script:lastExitCode = $Result.ExitCode
    $script:lastTimedOut = [bool]$Result.TimedOut
    $script:lastStdoutPresent = -not [string]::IsNullOrWhiteSpace([string]$Result.Stdout)
    $script:lastStderrPresent = -not [string]::IsNullOrWhiteSpace([string]$Result.Stderr)
}

function Invoke-WslBash {
    param(
        [Parameter(Mandatory)][string]$Script,
        [ValidateRange(1, 960)][int]$TimeoutSeconds = 60
    )

    $payload = ConvertTo-WslBashPayload -Script $Script
    return Invoke-BoundedProcess -FilePath $wslPath -ArgumentList @(
        '-d', $Distribution, '--', 'bash', '-lc', $payload
    ) -ProcessTimeoutSeconds $TimeoutSeconds
}

function Get-FirstOutputLine {
    param([AllowNull()][string]$Text)
    $lines = @($Text -split "[`r`n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($lines.Count -eq 0) { return $null }
    return [string]$lines[0]
}

function Assert-SafeOpenCodePath {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -notmatch '^/[A-Za-z0-9._/+~-]+$') {
        Stop-Recovery 'OPENCODE_PATH_UNSAFE' "WSL returned an unsafe OpenCode command path during $script:stage."
    }
}

function Write-RecoveryEvidence {
    $receipt = [ordered]@{
        schema = 'agentswitchboard.opencode-runtime-recovery-receipt.v1'
        runId = $runId
        status = $script:status
        stage = $script:stage
        failureCode = $script:failureCode
        failureMessage = $script:failureMessage
        repoPath = $RepoPath
        distribution = $Distribution
        modelId = $ModelId
        installTimeoutSeconds = $InstallTimeoutSeconds
        initialOpenCodePath = $script:initialOpenCodePath
        initialVersionExitCode = $script:initialVersionExitCode
        initialVersionTimedOut = $script:initialVersionTimedOut
        installAttempted = $script:installAttempted
        installReason = $script:installReason
        recoveredOpenCodePath = $script:openCodePath
        recoveredOpenCodeVersion = $script:openCodeVersion
        canonicalShim = $canonicalShim
        lastExitCode = $script:lastExitCode
        lastTimedOut = $script:lastTimedOut
        lastStdoutPresent = $script:lastStdoutPresent
        lastStderrPresent = $script:lastStderrPresent
        inspectExitCode = $script:inspectExitCode
        inspectFailureCode = $script:inspectFailureCode
        secretOrEnvironmentDumpPersisted = $false
        proofCeiling = 'Recovery evidence proves bounded local runtime repair state only. Provider/model/LSP behavior remains owned by the Inspect/Configure/Verify receipts.'
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM

    $report = @(
        '# OpenCode Runtime Recovery Report','',
        "- Status: ``$($script:status)``",
        "- Stage: ``$($script:stage)``",
        "- Failure code: ``$($script:failureCode)``",
        "- Failure message: ``$($script:failureMessage)``",
        "- Distribution: ``$Distribution``",
        "- Initial OpenCode path: ``$($script:initialOpenCodePath)``",
        "- Initial version exit: ``$($script:initialVersionExitCode)``",
        "- Install attempted: ``$($script:installAttempted)``",
        "- Install reason: ``$($script:installReason)``",
        "- Recovered OpenCode path: ``$($script:openCodePath)``",
        "- Recovered OpenCode version: ``$($script:openCodeVersion)``",
        "- Canonical shim: ``$canonicalShim``",
        "- Last bounded exit: ``$($script:lastExitCode)``",
        "- Last command timed out: ``$($script:lastTimedOut)``",
        "- Last stdout present: ``$($script:lastStdoutPresent)``",
        "- Last stderr present: ``$($script:lastStderrPresent)``",
        "- Inspect exit: ``$($script:inspectExitCode)``",
        "- Inspect failure code: ``$($script:inspectFailureCode)``",'',
        'No environment dump, provider credential, or inherited OpenCode configuration content is persisted in this recovery evidence.'
    )
    $report | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM

    Write-Host "OPENCODE_RUNTIME_RECOVERY_STATUS=$($script:status)"
    Write-Host "OPENCODE_RUNTIME_RECOVERY_STAGE=$($script:stage)"
    Write-Host "OPENCODE_RUNTIME_RECOVERY_FAILURE_CODE=$($script:failureCode)"
    Write-Host "OPENCODE_RUNTIME_RECOVERY_RECEIPT=$receiptPath"
    Write-Host "OPENCODE_RUNTIME_RECOVERY_REPORT=$reportPath"
}

try {
    foreach ($requiredPath in @($runnerPath, $wslPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            Stop-Recovery 'RUNTIME_RECOVERY_ENTRYPOINT_MISSING' "Required runtime-recovery entrypoint is missing: $requiredPath"
        }
    }

    $script:stage = 'wsl-distribution-discovery'
    $distributionProbe = Invoke-BoundedProcess -FilePath $wslPath -ArgumentList @('--list', '--quiet') -ProcessTimeoutSeconds 30
    Set-LastResult -Result $distributionProbe
    if ($distributionProbe.TimedOut) {
        Stop-Recovery 'WSL_DISTRIBUTION_DISCOVERY_TIMEOUT' 'WSL distribution discovery timed out after 30 seconds.'
    }
    if ($distributionProbe.ExitCode -ne 0) {
        Stop-Recovery 'WSL_DISTRIBUTION_DISCOVERY_FAILED' "WSL distribution discovery failed with exit code $($distributionProbe.ExitCode)."
    }
    $distributions = @($distributionProbe.Stdout -split "[`r`n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($Distribution -notin $distributions) {
        Stop-Recovery 'WSL_DISTRIBUTION_NOT_FOUND' "WSL distribution '$Distribution' is not initialized."
    }

    $script:stage = 'opencode-command-discovery'
    $discoveryScript = @'
set -u
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
if command -v opencode >/dev/null 2>&1; then
  command -v opencode
  exit 0
fi
exit 44
'@
    $discovery = Invoke-WslBash -Script $discoveryScript -TimeoutSeconds 30
    Set-LastResult -Result $discovery
    if ($discovery.TimedOut) {
        Stop-Recovery 'OPENCODE_COMMAND_DISCOVERY_TIMEOUT' 'OpenCode command discovery timed out after 30 seconds.'
    }
    if ($discovery.ExitCode -eq 0) {
        $script:initialOpenCodePath = Get-FirstOutputLine -Text $discovery.Stdout
        if ([string]::IsNullOrWhiteSpace($script:initialOpenCodePath)) {
            Stop-Recovery 'OPENCODE_COMMAND_DISCOVERY_EMPTY' 'OpenCode command discovery returned success without a command path.'
        }
        Assert-SafeOpenCodePath -Path $script:initialOpenCodePath

        $script:stage = 'opencode-version-probe'
        $versionScript = @'
set -u
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
opencode --version
'@
        $initialVersion = Invoke-WslBash -Script $versionScript -TimeoutSeconds 30
        Set-LastResult -Result $initialVersion
        $script:initialVersionExitCode = $initialVersion.ExitCode
        $script:initialVersionTimedOut = [bool]$initialVersion.TimedOut
        $initialVersionText = Get-FirstOutputLine -Text $initialVersion.Stdout
        if ($initialVersion.TimedOut) {
            $script:installReason = 'existing-runtime-version-timeout'
        }
        elseif ($initialVersion.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($initialVersionText)) {
            $script:installReason = 'existing-runtime-version-failed'
        }
        else {
            $script:openCodePath = $script:initialOpenCodePath
            $script:openCodeVersion = $initialVersionText
        }
    }
    elseif ($discovery.ExitCode -eq 44) {
        $script:installReason = 'command-not-found'
    }
    else {
        Stop-Recovery 'OPENCODE_COMMAND_DISCOVERY_FAILED' "OpenCode command discovery failed with exit code $($discovery.ExitCode)."
    }

    if ($script:installReason) {
        Write-Host "OpenCode recovery reason=$($script:installReason); starting bounded OpenCode-only installation."
        $script:stage = 'opencode-install-prerequisites'
        $prerequisiteScript = @'
set -u
command -v curl >/dev/null 2>&1 || exit 61
command -v timeout >/dev/null 2>&1 || exit 62
exit 0
'@
        $prerequisiteProbe = Invoke-WslBash -Script $prerequisiteScript -TimeoutSeconds 30
        Set-LastResult -Result $prerequisiteProbe
        if ($prerequisiteProbe.TimedOut) {
            Stop-Recovery 'OPENCODE_INSTALL_PREREQUISITE_TIMEOUT' 'OpenCode installation prerequisite discovery timed out after 30 seconds.'
        }
        if ($prerequisiteProbe.ExitCode -eq 61) {
            Stop-Recovery 'OPENCODE_INSTALL_CURL_MISSING' "OpenCode-only recovery requires curl inside WSL '$Distribution'; unrelated technician tools will not be installed as a side effect."
        }
        if ($prerequisiteProbe.ExitCode -eq 62) {
            Stop-Recovery 'OPENCODE_INSTALL_TIMEOUT_TOOL_MISSING' "OpenCode-only recovery requires GNU timeout inside WSL '$Distribution' so network installation cannot hang indefinitely."
        }
        if ($prerequisiteProbe.ExitCode -ne 0) {
            Stop-Recovery 'OPENCODE_INSTALL_PREREQUISITE_FAILED' "OpenCode installation prerequisite discovery failed with exit code $($prerequisiteProbe.ExitCode)."
        }

        $script:stage = 'opencode-install'
        $script:installAttempted = $true
        $installScript = @'
set -euo pipefail
export OPENCODE_INSTALL_DIR="$HOME/.opencode/bin"
timeout --signal=TERM --kill-after=10s __INSTALL_TIMEOUT__s bash -lc 'set -euo pipefail; curl --connect-timeout 15 --max-time __INSTALL_TIMEOUT__ -fsSL https://opencode.ai/install | bash'
'@.Replace('__INSTALL_TIMEOUT__', [string]$InstallTimeoutSeconds)
        $installResult = Invoke-WslBash -Script $installScript -TimeoutSeconds ($InstallTimeoutSeconds + 30)
        Set-LastResult -Result $installResult
        if (-not [string]::IsNullOrWhiteSpace($installResult.Stdout)) { Write-Host $installResult.Stdout }
        if (-not [string]::IsNullOrWhiteSpace($installResult.Stderr)) { Write-Warning $installResult.Stderr }
        if ($installResult.TimedOut) {
            Stop-Recovery 'OPENCODE_INSTALL_WINDOWS_TIMEOUT' "OpenCode installation exceeded the Windows recovery timeout of $($InstallTimeoutSeconds + 30) seconds."
        }
        if ($installResult.ExitCode -eq 124 -or $installResult.ExitCode -eq 137) {
            Stop-Recovery 'OPENCODE_INSTALL_WSL_TIMEOUT' "OpenCode installation exceeded the bounded WSL install timeout of $InstallTimeoutSeconds seconds."
        }
        if ($installResult.ExitCode -ne 0) {
            Stop-Recovery 'OPENCODE_INSTALL_FAILED' "The official OpenCode installer returned exit code $($installResult.ExitCode)."
        }

        $script:stage = 'post-install-command-discovery'
        $postDiscovery = Invoke-WslBash -Script $discoveryScript -TimeoutSeconds 30
        Set-LastResult -Result $postDiscovery
        if ($postDiscovery.TimedOut) {
            Stop-Recovery 'OPENCODE_POST_INSTALL_DISCOVERY_TIMEOUT' 'OpenCode command discovery timed out after installation.'
        }
        if ($postDiscovery.ExitCode -ne 0) {
            Stop-Recovery 'OPENCODE_POST_INSTALL_NOT_FOUND' "OpenCode installation returned success but command discovery failed with exit code $($postDiscovery.ExitCode)."
        }
        $script:openCodePath = Get-FirstOutputLine -Text $postDiscovery.Stdout
        if ([string]::IsNullOrWhiteSpace($script:openCodePath)) {
            Stop-Recovery 'OPENCODE_POST_INSTALL_DISCOVERY_EMPTY' 'OpenCode installation returned success without a discoverable command path.'
        }
        Assert-SafeOpenCodePath -Path $script:openCodePath

        $script:stage = 'post-install-version-probe'
        $postVersion = Invoke-WslBash -Script $versionScript -TimeoutSeconds 30
        Set-LastResult -Result $postVersion
        if ($postVersion.TimedOut) {
            Stop-Recovery 'OPENCODE_POST_INSTALL_VERSION_TIMEOUT' 'OpenCode version probing timed out after bounded installation.'
        }
        $script:openCodeVersion = Get-FirstOutputLine -Text $postVersion.Stdout
        if ($postVersion.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($script:openCodeVersion)) {
            Stop-Recovery 'OPENCODE_POST_INSTALL_VERSION_FAILED' "OpenCode remained unhealthy after bounded installation; version probe exit=$($postVersion.ExitCode)."
        }
    }

    if ([string]::IsNullOrWhiteSpace($script:openCodePath) -or [string]::IsNullOrWhiteSpace($script:openCodeVersion)) {
        Stop-Recovery 'OPENCODE_RUNTIME_UNRESOLVED' 'OpenCode recovery completed without a proven command path and version.'
    }
    Assert-SafeOpenCodePath -Path $script:openCodePath

    $script:stage = 'shim-write'
    $shimDirectory = Split-Path -Parent $canonicalShim
    $null = New-Item -ItemType Directory -Path $shimDirectory -Force
    $shimLines = @(
        '@echo off',
        ('"{0}" -d "{1}" --exec "{2}" %*' -f $wslPath, $Distribution, $script:openCodePath),
        'exit /b %ERRORLEVEL%'
    )
    [System.IO.File]::WriteAllLines($canonicalShim, $shimLines, [System.Text.Encoding]::ASCII)
    if (-not (Test-Path -LiteralPath $canonicalShim -PathType Leaf)) {
        Stop-Recovery 'OPENCODE_SHIM_WRITE_FAILED' "OpenCode recovery could not create the canonical AgentSwitchboard shim: $canonicalShim"
    }

    Write-Host "OPENCODE_RUNTIME_RECOVERY_WSL_PATH=$($script:openCodePath)"
    Write-Host "OPENCODE_RUNTIME_RECOVERY_VERSION=$($script:openCodeVersion)"
    Write-Host "OPENCODE_RUNTIME_RECOVERY_SHIM=$canonicalShim"

    $script:stage = 'inspect-handoff'
    $inspectResult = Invoke-BoundedProcess -FilePath 'pwsh' -ArgumentList @(
        '-NoLogo','-NoProfile','-File',$runnerPath,'-Mode','Inspect','-RepoPath',$RepoPath,'-ModelId',$ModelId
    ) -ProcessTimeoutSeconds 150
    Set-LastResult -Result $inspectResult
    $script:inspectExitCode = $inspectResult.ExitCode
    if (-not [string]::IsNullOrWhiteSpace($inspectResult.Stdout)) { Write-Host $inspectResult.Stdout }
    if (-not [string]::IsNullOrWhiteSpace($inspectResult.Stderr)) { Write-Warning $inspectResult.Stderr }
    if ($inspectResult.TimedOut) {
        Stop-Recovery 'OPENCODE_INSPECT_HANDOFF_TIMEOUT' 'The post-recovery Inspect handoff exceeded 150 seconds.'
    }
    if ($inspectResult.Stdout -match '(?m)^FAILURE_CODE=([^\r\n]+)') {
        $script:inspectFailureCode = $Matches[1].Trim()
    }
    if ($inspectResult.ExitCode -ne 0) {
        $script:status = 'recovered-inspect-failed'
        $script:failureCode = 'OPENCODE_INSPECT_HANDOFF_FAILED'
        $script:failureMessage = if ($script:inspectFailureCode) { "Runtime recovery succeeded; Inspect advanced to $($script:inspectFailureCode)." } else { "Runtime recovery succeeded; Inspect returned exit code $($inspectResult.ExitCode)." }
    }
    else {
        $script:status = 'recovered-and-inspected'
    }
}
catch {
    $raw = [string]$_.Exception.Message
    if ($raw -match '^([A-Z0-9_]+)\|(.*)$') {
        $script:failureCode = $Matches[1]
        $script:failureMessage = $Matches[2]
    }
    else {
        $script:failureCode = 'UNEXPECTED_RUNTIME_RECOVERY_FAILURE'
        $script:failureMessage = 'OpenCode runtime recovery failed unexpectedly before completing its bounded stage.'
    }
}

Write-RecoveryEvidence

if ($script:failureCode) {
    Write-Host "OPENCODE_RUNTIME_RECOVERY_FAILURE_MESSAGE=$($script:failureMessage)"
    exit 1
}
exit 0
