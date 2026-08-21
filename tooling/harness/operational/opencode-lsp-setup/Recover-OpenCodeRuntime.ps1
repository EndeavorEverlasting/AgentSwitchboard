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

if ($env:OS -ne 'Windows_NT') {
    throw 'OpenCode runtime recovery is Windows-only.'
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'OpenCode runtime recovery requires PowerShell 7.'
}

$RepoPath = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
$runnerPath = Join-Path $RepoPath 'tooling\harness\operational\opencode-lsp-setup\Invoke-OpenCodeLspWorkstationSetup.ps1'
$canonicalShim = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin\opencode.cmd'
$wslPath = Join-Path $env:SystemRoot 'System32\wsl.exe'

foreach ($requiredPath in @($runnerPath, $wslPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required runtime-recovery entrypoint is missing: $requiredPath"
    }
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

$distributionProbe = Invoke-BoundedProcess -FilePath $wslPath -ArgumentList @('--list', '--quiet') -ProcessTimeoutSeconds 30
if ($distributionProbe.TimedOut) {
    throw 'WSL distribution discovery timed out after 30 seconds.'
}
if ($distributionProbe.ExitCode -ne 0) {
    throw "WSL distribution discovery failed. exit=$($distributionProbe.ExitCode) stderr=$($distributionProbe.Stderr)"
}
$distributions = @($distributionProbe.Stdout -split "[`r`n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Distribution -notin $distributions) {
    throw "WSL distribution '$Distribution' is not initialized."
}

$probeScript = @'
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
if ! command -v opencode >/dev/null 2>&1; then
  exit 44
fi
command -v opencode
opencode --version
'@
$runtimeProbe = Invoke-WslBash -Script $probeScript -TimeoutSeconds 30
if ($runtimeProbe.TimedOut) {
    throw 'OpenCode runtime probe timed out after 30 seconds.'
}

if ($runtimeProbe.ExitCode -eq 44) {
    Write-Host "OpenCode is absent in WSL '$Distribution'; starting bounded OpenCode-only installation."
    $installScript = @'
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
if ! command -v curl >/dev/null 2>&1; then
  exit 61
fi
if ! command -v timeout >/dev/null 2>&1; then
  exit 62
fi
if ! command -v opencode >/dev/null 2>&1; then
  timeout --signal=TERM --kill-after=10s __INSTALL_TIMEOUT__s bash -lc 'set -euo pipefail; curl --connect-timeout 15 --max-time __INSTALL_TIMEOUT__ -fsSL https://opencode.ai/install | bash'
fi
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
command -v opencode
opencode --version
'@.Replace('__INSTALL_TIMEOUT__', [string]$InstallTimeoutSeconds)

    $runtimeProbe = Invoke-WslBash -Script $installScript -TimeoutSeconds ($InstallTimeoutSeconds + 30)
    if ($runtimeProbe.TimedOut) {
        throw "OpenCode installation exceeded the Windows recovery timeout of $($InstallTimeoutSeconds + 30) seconds."
    }
    if ($runtimeProbe.ExitCode -eq 124 -or $runtimeProbe.ExitCode -eq 137) {
        throw "OpenCode installation exceeded the bounded WSL install timeout of $InstallTimeoutSeconds seconds."
    }
    if ($runtimeProbe.ExitCode -eq 61) {
        throw "OpenCode-only recovery requires curl inside WSL '$Distribution'; unrelated technician tools will not be installed as a side effect."
    }
    if ($runtimeProbe.ExitCode -eq 62) {
        throw "OpenCode-only recovery requires GNU timeout inside WSL '$Distribution' so network installation cannot hang indefinitely."
    }
}

if ($runtimeProbe.ExitCode -ne 0) {
    throw "OpenCode WSL recovery failed. exit=$($runtimeProbe.ExitCode) stdout=$($runtimeProbe.Stdout) stderr=$($runtimeProbe.Stderr)"
}

$runtimeLines = @($runtimeProbe.Stdout -split "[`r`n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($runtimeLines.Count -lt 2) {
    throw "OpenCode recovery did not return both command path and version. stdout=$($runtimeProbe.Stdout)"
}
$openCodePath = [string]$runtimeLines[$runtimeLines.Count - 2]
$openCodeVersion = [string]$runtimeLines[$runtimeLines.Count - 1]
if ($openCodePath -notmatch '^/[A-Za-z0-9._/+~-]+$') {
    throw "WSL returned an unsafe OpenCode command path: $openCodePath"
}
if ([string]::IsNullOrWhiteSpace($openCodeVersion)) {
    throw 'OpenCode recovery returned an empty version string.'
}

$shimDirectory = Split-Path -Parent $canonicalShim
$null = New-Item -ItemType Directory -Path $shimDirectory -Force
$shimLines = @(
    '@echo off',
    ('"{0}" -d "{1}" --exec "{2}" %*' -f $wslPath, $Distribution, $openCodePath),
    'exit /b %ERRORLEVEL%'
)
[System.IO.File]::WriteAllLines($canonicalShim, $shimLines, [System.Text.Encoding]::ASCII)
if (-not (Test-Path -LiteralPath $canonicalShim -PathType Leaf)) {
    throw "OpenCode recovery could not create the canonical AgentSwitchboard shim: $canonicalShim"
}

Write-Host "OPENCODE_RUNTIME_RECOVERY_WSL_PATH=$openCodePath"
Write-Host "OPENCODE_RUNTIME_RECOVERY_VERSION=$openCodeVersion"
Write-Host "OPENCODE_RUNTIME_RECOVERY_SHIM=$canonicalShim"
Write-Host 'Bounded OpenCode-only runtime recovery passed; re-entering the owning LSP Inspect gate.'

& pwsh -NoLogo -NoProfile -File $runnerPath -Mode Inspect -RepoPath $RepoPath -ModelId $ModelId
exit $LASTEXITCODE
