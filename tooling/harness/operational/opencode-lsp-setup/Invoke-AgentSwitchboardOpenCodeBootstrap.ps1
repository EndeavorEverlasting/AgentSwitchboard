[CmdletBinding()]
param(
    [ValidateSet('Recover','ResolveOnly')][string]$Mode = 'Recover',
    [string]$ModelId = 'opencode/nemotron-3-ultra-free',
    [string]$Distribution = 'Ubuntu',
    [ValidateRange(30, 900)][int]$InstallTimeoutSeconds = 180,
    [ValidateRange(5, 120)][int]$NetworkTimeoutSeconds = 30,
    [ValidateRange(30, 300)][int]$CheckoutTimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

$repository = 'EndeavorEverlasting/AgentSwitchboard'
$canonicalUrl = 'https://github.com/EndeavorEverlasting/AgentSwitchboard.git'
$canonicalOriginPattern = '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/|git://github\.com/)EndeavorEverlasting/AgentSwitchboard(?:\.git)?/?$'
$rawBase = 'https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard'
$relativeRoot = 'tooling/harness/operational/opencode-lsp-setup'
$callerLocation = [string](Get-Location).Path
$runId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0,8))
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard-bootstrap-$runId"
$gitPath = $null
$pwshPath = $null

function Stop-Bootstrap {
    param([Parameter(Mandatory)][string]$Code, [Parameter(Mandatory)][string]$Message)
    throw ([InvalidOperationException]::new("$Code|$Message"))
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [ValidateRange(1, 1800)][int]$ProcessTimeoutSeconds = 60
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
        Stdout = ([string]$stdoutTask.GetAwaiter().GetResult()).Trim()
        Stderr = ([string]$stderrTask.GetAwaiter().GetResult()).Trim()
    }
}

function Invoke-GitLines {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $result = Invoke-BoundedProcess -FilePath $gitPath -ArgumentList $Arguments -ProcessTimeoutSeconds $NetworkTimeoutSeconds
    if ($result.TimedOut) {
        Stop-Bootstrap 'BOOTSTRAP_GIT_TIMEOUT' "git $($Arguments -join ' ') exceeded the bounded $NetworkTimeoutSeconds-second Git-operation window."
    }
    if ($result.ExitCode -ne 0) {
        Stop-Bootstrap 'BOOTSTRAP_GIT_FAILED' "git $($Arguments -join ' ') failed while resolving canonical repository state."
    }
    return @($result.Stdout -split "[`r`n]+" | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Save-BoundedRemoteFile {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination
    )

    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds($NetworkTimeoutSeconds)
    try {
        $bytes = $client.GetByteArrayAsync($Uri).GetAwaiter().GetResult()
        [IO.File]::WriteAllBytes($Destination, $bytes)
    }
    catch [System.Threading.Tasks.TaskCanceledException] {
        Stop-Bootstrap 'BOOTSTRAP_STAGE_DOWNLOAD_TIMEOUT' "Exact-head bootstrap staging exceeded the bounded $NetworkTimeoutSeconds-second download window."
    }
    catch {
        Stop-Bootstrap 'BOOTSTRAP_STAGE_DOWNLOAD_FAILED' 'Unable to stage the exact-head AgentSwitchboard checkout resolver.'
    }
    finally {
        $client.Dispose()
    }
}

try {
    if ($env:OS -ne 'Windows_NT') {
        Stop-Bootstrap 'BOOTSTRAP_WINDOWS_REQUIRED' 'The AgentSwitchboard OpenCode recovery bootstrap is Windows-only.'
    }
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Stop-Bootstrap 'BOOTSTRAP_POWERSHELL7_REQUIRED' 'The AgentSwitchboard OpenCode recovery bootstrap requires PowerShell 7.'
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Stop-Bootstrap 'BOOTSTRAP_LOCALAPPDATA_REQUIRED' 'LOCALAPPDATA is required for canonical AgentSwitchboard checkout and evidence state.'
    }
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        Stop-Bootstrap 'BOOTSTRAP_GIT_NOT_FOUND' 'Git is required to resolve or acquire AgentSwitchboard from any working directory.'
    }
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCommand) {
        Stop-Bootstrap 'BOOTSTRAP_POWERSHELL7_NOT_FOUND' 'PowerShell 7 executable is required for bounded checkout/runtime dispatch.'
    }
    $gitPath = [string]$gitCommand.Source
    $pwshPath = [string]$pwshCommand.Source

    $symrefLines = @(Invoke-GitLines -Arguments @('ls-remote','--symref',$canonicalUrl,'HEAD'))
    $defaultBranch = $null
    foreach ($line in $symrefLines) {
        $match = [regex]::Match([string]$line, '^ref:\s+refs/heads/(?<branch>[^\s]+)\s+HEAD$')
        if ($match.Success) {
            $defaultBranch = $match.Groups['branch'].Value
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
        Stop-Bootstrap 'BOOTSTRAP_DEFAULT_BRANCH_NOT_FOUND' 'GitHub did not return the AgentSwitchboard default-branch symref.'
    }

    $headLines = @(Invoke-GitLines -Arguments @('ls-remote',$canonicalUrl,"refs/heads/$defaultBranch"))
    if ($headLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$headLines[0])) {
        Stop-Bootstrap 'BOOTSTRAP_DEFAULT_HEAD_NOT_FOUND' 'GitHub did not return the current AgentSwitchboard default-branch head.'
    }
    $expectedHead = (([string]$headLines[0]) -split '\s+')[0].Trim().ToLowerInvariant()
    if ($expectedHead -notmatch '^[0-9a-f]{40}$') {
        Stop-Bootstrap 'BOOTSTRAP_DEFAULT_HEAD_INVALID' 'The resolved AgentSwitchboard default-branch head was not a full commit SHA.'
    }

    $null = New-Item -ItemType Directory -Path $stageRoot -Force
    $resolverPath = Join-Path $stageRoot 'Resolve-AgentSwitchboardCheckout.ps1'
    $resolverUri = "$rawBase/$expectedHead/$relativeRoot/Resolve-AgentSwitchboardCheckout.ps1"
    Save-BoundedRemoteFile -Uri $resolverUri -Destination $resolverPath
    if (-not (Test-Path -LiteralPath $resolverPath -PathType Leaf)) {
        Stop-Bootstrap 'BOOTSTRAP_STAGE_FILE_MISSING' 'Exact-head bootstrap staging did not create Resolve-AgentSwitchboardCheckout.ps1.'
    }

    Write-Host "BOOTSTRAP_CALLER_LOCATION=$callerLocation"
    Write-Host "BOOTSTRAP_DEFAULT_BRANCH=$defaultBranch"
    Write-Host "BOOTSTRAP_EXPECTED_HEAD=$expectedHead"

    $resolutionResult = Invoke-BoundedProcess -FilePath $pwshPath -ArgumentList @(
        '-NoLogo','-NoProfile','-File',$resolverPath,
        '-ExpectedBranch',$defaultBranch,
        '-ExpectedHead',$expectedHead,
        '-AllowRemoteBranchAdvance'
    ) -ProcessTimeoutSeconds $CheckoutTimeoutSeconds
    if ($resolutionResult.TimedOut) {
        Stop-Bootstrap 'BOOTSTRAP_CHECKOUT_RECOVERY_TIMEOUT' "Exact-head checkout recovery exceeded the bounded $CheckoutTimeoutSeconds-second window."
    }
    if ($resolutionResult.ExitCode -ne 0) {
        Stop-Bootstrap 'BOOTSTRAP_CHECKOUT_RECOVERY_FAILED' "Exact-head checkout recovery returned exit code $($resolutionResult.ExitCode)."
    }
    $resolutionLines = @($resolutionResult.Stdout -split "[`r`n]+" | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($resolutionLines.Count -eq 0) {
        Stop-Bootstrap 'BOOTSTRAP_CHECKOUT_RECEIPT_EMPTY' 'Checkout recovery returned no machine-readable resolution object.'
    }
    $resolutionLine = [string]$resolutionLines[-1]

    try { $resolution = $resolutionLine | ConvertFrom-Json -ErrorAction Stop }
    catch { Stop-Bootstrap 'BOOTSTRAP_CHECKOUT_RECEIPT_INVALID' 'Checkout recovery returned an invalid machine-readable resolution object.' }
    $resolved = [string]$resolution.resolvedWorktreePath
    if ([string]::IsNullOrWhiteSpace($resolved) -or -not (Test-Path -LiteralPath $resolved -PathType Container)) {
        Stop-Bootstrap 'BOOTSTRAP_RESOLVED_ROOT_MISSING' 'Checkout recovery did not return a reachable AgentSwitchboard worktree.'
    }

    $rootLines = @(Invoke-GitLines -Arguments @('-C',$resolved,'rev-parse','--show-toplevel'))
    if ($rootLines.Count -eq 0) {
        Stop-Bootstrap 'BOOTSTRAP_ROOT_VERIFICATION_FAILED' 'Resolved worktree failed git rev-parse --show-toplevel.'
    }
    $verifiedRoot = ([string]$rootLines[0]).Trim()
    $originLines = @(Invoke-GitLines -Arguments @('-C',$verifiedRoot,'remote','get-url','origin'))
    if ($originLines.Count -eq 0) {
        Stop-Bootstrap 'BOOTSTRAP_ORIGIN_VERIFICATION_FAILED' 'Resolved worktree did not expose an origin remote.'
    }
    $origin = ([string]$originLines[0]).Trim()
    if ($origin -notmatch $canonicalOriginPattern) {
        Stop-Bootstrap 'BOOTSTRAP_WRONG_REPOSITORY' "Resolved worktree origin is not $repository."
    }
    $actualHeadLines = @(Invoke-GitLines -Arguments @('-C',$verifiedRoot,'rev-parse','HEAD'))
    if ($actualHeadLines.Count -eq 0) {
        Stop-Bootstrap 'BOOTSTRAP_HEAD_VERIFICATION_FAILED' 'Resolved AgentSwitchboard worktree HEAD could not be read.'
    }
    $actualHead = ([string]$actualHeadLines[0]).Trim().ToLowerInvariant()
    if ($actualHead -ne $expectedHead) {
        Stop-Bootstrap 'BOOTSTRAP_HEAD_MISMATCH' "Resolved AgentSwitchboard worktree is at $actualHead, not selected default-head snapshot $expectedHead."
    }
    $dirtyLines = @(Invoke-GitLines -Arguments @('-C',$verifiedRoot,'status','--porcelain=v1'))
    if ($dirtyLines.Count -gt 0) {
        Stop-Bootstrap 'BOOTSTRAP_WORKTREE_NOT_CLEAN' 'Resolved exact-head AgentSwitchboard worktree is not clean; it was preserved and not rewritten.'
    }

    Set-Location -LiteralPath $verifiedRoot
    Write-Host "BOOTSTRAP_RESOLVED_ROOT=$verifiedRoot"
    Write-Host "BOOTSTRAP_VERIFIED_ORIGIN=$origin"
    Write-Host "BOOTSTRAP_VERIFIED_HEAD=$actualHead"
    Write-Host "BOOTSTRAP_ACTIVE_LOCATION=$([string](Get-Location).Path)"

    if ($Mode -ne 'ResolveOnly') {
        $runtimeRecovery = Join-Path $verifiedRoot "$relativeRoot/Recover-OpenCodeRuntime.ps1"
        if (-not (Test-Path -LiteralPath $runtimeRecovery -PathType Leaf)) {
            Stop-Bootstrap 'BOOTSTRAP_RUNTIME_ROUTER_MISSING' 'The verified exact-head worktree is missing Recover-OpenCodeRuntime.ps1.'
        }
        $runtimeTimeout = $InstallTimeoutSeconds + 300
        $runtimeResult = Invoke-BoundedProcess -FilePath $pwshPath -ArgumentList @(
            '-NoLogo','-NoProfile','-File',$runtimeRecovery,
            '-RepoPath',$verifiedRoot,
            '-ModelId',$ModelId,
            '-Distribution',$Distribution,
            '-InstallTimeoutSeconds',[string]$InstallTimeoutSeconds
        ) -ProcessTimeoutSeconds $runtimeTimeout
        if (-not [string]::IsNullOrWhiteSpace($runtimeResult.Stdout)) { Write-Host $runtimeResult.Stdout }
        if (-not [string]::IsNullOrWhiteSpace($runtimeResult.Stderr)) { Write-Warning $runtimeResult.Stderr }
        if ($runtimeResult.TimedOut) {
            Stop-Bootstrap 'BOOTSTRAP_RUNTIME_RECOVERY_TIMEOUT' "Focused OpenCode runtime recovery exceeded the bounded $runtimeTimeout-second parent window."
        }
        if ($runtimeResult.ExitCode -ne 0) {
            Stop-Bootstrap 'BOOTSTRAP_RUNTIME_RECOVERY_FAILED' "Focused OpenCode runtime recovery returned exit code $($runtimeResult.ExitCode) after canonical root verification."
        }
    }

    $global:LASTEXITCODE = 0
}
catch {
    $raw = [string]$_.Exception.Message
    if ($raw -match '^([A-Z0-9_]+)\|(.*)$') {
        Write-Host "BOOTSTRAP_FAILURE_CODE=$($Matches[1])"
        Write-Host "BOOTSTRAP_FAILURE_MESSAGE=$($Matches[2])"
    }
    else {
        Write-Host 'BOOTSTRAP_FAILURE_CODE=BOOTSTRAP_UNEXPECTED_FAILURE'
        Write-Host 'BOOTSTRAP_FAILURE_MESSAGE=The cwd-independent AgentSwitchboard bootstrap failed before dispatch.'
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
