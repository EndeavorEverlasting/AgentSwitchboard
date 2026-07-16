[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Contract {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-GitChecked {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = @(& git -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function New-TestRepository {
    param([Parameter(Mandatory)][string]$Path)

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $output = @(& git -C $Path init -b main 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git init failed:`n$($output -join [Environment]::NewLine)"
    }

    Set-Content -LiteralPath (Join-Path $Path "README.md") -Value "fail-fast runtime fixture" -Encoding utf8NoBOM
    [void](Invoke-GitChecked -Repository $Path -Arguments @("add", "README.md"))
    [void](Invoke-GitChecked -Repository $Path -Arguments @(
        "-c", "user.name=AgentSwitchboard Tests",
        "-c", "user.email=agentswitchboard-tests@example.invalid",
        "commit", "-m", "test: initialize runtime fixture"
    ))
}

function Write-FakeCommands {
    param([Parameter(Mandatory)][string]$BinPath)

    New-Item -ItemType Directory -Path $BinPath -Force | Out-Null

    @'
@echo off
if /I "%~1"=="--version" (
  echo agy 1.1.2
  exit /b 0
)
>&2 echo Individual quota reached
exit /b 1
'@ | Set-Content -LiteralPath (Join-Path $BinPath "agy.cmd") -Encoding ascii

    @'
@echo off
echo goose 1.0
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $BinPath "goose.cmd") -Encoding ascii

    @'
@echo off
echo invoked>>"%FAKE_GNHF_MARKER%"
if /I "%FAKE_GNHF_MODE%"=="commit" (
  git switch -c gnhf/fallback-proof >nul 2>&1 || exit /b 41
  echo fallback-route-committed> routed-proof.txt
  git add routed-proof.txt >nul 2>&1 || exit /b 42
  git -c user.name="AgentSwitchboard Tests" -c user.email="agentswitchboard-tests@example.invalid" commit -m "test: prove fallback route" >nul 2>&1 || exit /b 43
)
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $BinPath "gnhf.cmd") -Encoding ascii
}

function Write-TestInstallState {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$GnhfPath
    )

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    [ordered]@{
        gnhf = [ordered]@{ commandPath = $GnhfPath }
        agents = [ordered]@{}
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $InstallRoot "state.json") -Encoding utf8NoBOM
}

function Invoke-ChildPowerShell {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $output = @(& pwsh -NoLogo -NoProfile -File $ScriptPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $timer.Stop()

    return [pscustomobject]@{
        ExitCode = $exitCode
        Elapsed = $timer.Elapsed
        Output = @($output)
        Text = ($output -join [Environment]::NewLine)
    }
}

$gnhfRoot = Split-Path -Parent $PSScriptRoot
$sprintScript = Join-Path $gnhfRoot "Start-GnhfSprint.ps1"
$routerScript = Join-Path $gnhfRoot "Start-AutoRoutedGnhfSprint.ps1"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agentswitchboard-fail-fast-{0}" -f [guid]::NewGuid().ToString("N"))
$oldPath = $env:Path
$oldStatusPath = $env:AGENTSWITCHBOARD_AGY_STATUS_PATH
$oldMarker = $env:FAKE_GNHF_MARKER
$oldMode = $env:FAKE_GNHF_MODE

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $binPath = Join-Path $tempRoot "bin"
    Write-FakeCommands -BinPath $binPath
    $env:Path = "$binPath;$oldPath"

    # Scenario 1: an AGY quota response that exits 1 must stop before GNHF.
    $directRepo = Join-Path $tempRoot "direct-repo"
    $directInstall = Join-Path $tempRoot "direct-install"
    $directMarker = Join-Path $tempRoot "direct-gnhf-invoked.txt"
    $directStatus = Join-Path $tempRoot "direct-agy-status.json"
    New-TestRepository -Path $directRepo
    Write-TestInstallState -InstallRoot $directInstall -GnhfPath (Join-Path $binPath "gnhf.cmd")
    $env:AGENTSWITCHBOARD_AGY_STATUS_PATH = $directStatus
    $env:FAKE_GNHF_MARKER = $directMarker
    $env:FAKE_GNHF_MODE = "marker-only"

    $directResult = Invoke-ChildPowerShell -ScriptPath $sprintScript -Arguments @(
        "-RepoPath", $directRepo,
        "-Agent", "pi",
        "-Prompt", "Do not mutate the runtime fixture.",
        "-Name", "fail-fast-direct",
        "-MaxIterations", "1",
        "-MaxTokens", "1",
        "-StopWhen", "The quota preflight stops before GNHF.",
        "-InstallRoot", $directInstall
    )

    Assert-Contract -Condition ($directResult.ExitCode -eq 75) -Message "Expected stable quota exit code 75, got $($directResult.ExitCode).`n$($directResult.Text)"
    Assert-Contract -Condition ($directResult.Elapsed.TotalSeconds -lt 15) -Message "Fail-fast exceeded 15 seconds: $($directResult.Elapsed)."
    Assert-Contract -Condition (-not (Test-Path -LiteralPath $directMarker)) -Message "GNHF was invoked during the failed AGY preflight."
    Assert-Contract -Condition (Test-Path -LiteralPath $directStatus -PathType Leaf) -Message "AGY status evidence was not written."

    $directStatusRecord = Get-Content -LiteralPath $directStatus -Raw | ConvertFrom-Json
    Assert-Contract -Condition ($directStatusRecord.classification -eq "quota-exhausted") -Message "Unexpected AGY classification: $($directStatusRecord.classification)."
    Assert-Contract -Condition ($directStatusRecord.exitCode -eq 75) -Message "AGY status did not preserve stable exit code 75."

    $directSummaryPath = Get-ChildItem -LiteralPath (Join-Path $directInstall "logs") -Filter launcher-summary.json -File -Recurse | Select-Object -First 1 -ExpandProperty FullName
    $directSummary = Get-Content -LiteralPath $directSummaryPath -Raw | ConvertFrom-Json
    Assert-Contract -Condition (-not $directSummary.gnhfInvoked) -Message "Launcher summary incorrectly reports a GNHF invocation."
    Assert-Contract -Condition ($directSummary.outcome -eq "agy-preflight-quota-exhausted") -Message "Unexpected direct outcome: $($directSummary.outcome)."
    Assert-Contract -Condition (@(Invoke-GitChecked -Repository $directRepo -Arguments @("branch", "--list", "gnhf/*")).Count -eq 0) -Message "The failed AGY preflight created a GNHF branch."
    Assert-Contract -Condition (@(Invoke-GitChecked -Repository $directRepo -Arguments @("worktree", "list", "--porcelain") | Where-Object { $_ -match '^worktree ' }).Count -eq 1) -Message "The failed AGY preflight created a GNHF worktree."

    # Scenario 2: the router may fall back only after the no-mutation gate.
    $routedRepo = Join-Path $tempRoot "routed-repo"
    $routedInstall = Join-Path $tempRoot "routed-install"
    $routedMarker = Join-Path $tempRoot "routed-gnhf-invoked.txt"
    $policyPath = Join-Path $tempRoot "runtime-policy.json"
    New-TestRepository -Path $routedRepo
    Write-TestInstallState -InstallRoot $routedInstall -GnhfPath (Join-Path $binPath "gnhf.cmd")

    $bridgeRoot = Join-Path $routedInstall "agy-pi-bridge"
    New-Item -ItemType Directory -Path $bridgeRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $bridgeRoot "Invoke-AgyPiBridge.ps1") -Value "# runtime fixture" -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $bridgeRoot "pi.cmd") -Value "@exit /b 0" -Encoding ascii

    [ordered]@{
        schemaVersion = 2
        selectionMode = "quota-preserving"
        costOrder = @("natural-free", "free")
        allowPaidFallback = $false
        fallbackPolicy = [ordered]@{
            allowedClassifications = @("quota-exhausted")
            requireNoMutation = $true
        }
        pricingPolicies = [ordered]@{}
        routes = @(
            [ordered]@{
                id = "agy-natural-free"
                enabled = $true
                costClass = "natural-free"
                priority = 1
                command = "agy"
                agentSpec = "pi"
                integration = "agy-pi-shim"
                gnhfCompatibility = "native"
                fallbackOn = @("quota-exhausted")
            },
            [ordered]@{
                id = "goose-free-provider"
                enabled = $true
                costClass = "free"
                priority = 1
                command = "goose"
                agentSpec = "codex"
                integration = "native"
                gnhfCompatibility = "capability-gated"
                probeArgs = @("--version")
                fallbackOn = @()
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $policyPath -Encoding utf8NoBOM

    $env:AGENTSWITCHBOARD_AGY_STATUS_PATH = $null
    $env:FAKE_GNHF_MARKER = $routedMarker
    $env:FAKE_GNHF_MODE = "commit"

    $routedResult = Invoke-ChildPowerShell -ScriptPath $routerScript -Arguments @(
        "-RepoPath", $routedRepo,
        "-Prompt", "Create the bounded fallback proof commit.",
        "-Name", "fail-fast-routed",
        "-MaxIterations", "1",
        "-MaxTokens", "1",
        "-StopWhen", "The fallback route creates one proof commit.",
        "-InstallRoot", $routedInstall,
        "-PolicyPath", $policyPath
    )

    Assert-Contract -Condition ($routedResult.ExitCode -eq 0) -Message "Expected routed fallback success, got $($routedResult.ExitCode).`n$($routedResult.Text)"
    Assert-Contract -Condition ($routedResult.Elapsed.TotalSeconds -lt 30) -Message "Routed fallback exceeded 30 seconds: $($routedResult.Elapsed)."
    Assert-Contract -Condition ($routedResult.Text -match 'AGY quota is exhausted and no mutation was observed') -Message "Router did not report the no-mutation fallback gate."
    Assert-Contract -Condition ($routedResult.Text -match 'Route completed successfully: goose-free-provider') -Message "Fallback route did not complete."
    Assert-Contract -Condition (Test-Path -LiteralPath $routedMarker -PathType Leaf) -Message "Fallback route never invoked GNHF."
    Assert-Contract -Condition (@(Get-Content -LiteralPath $routedMarker).Count -eq 1) -Message "GNHF was invoked more than once; the AGY route was not fail-fast."
    Assert-Contract -Condition ([int]((Invoke-GitChecked -Repository $routedRepo -Arguments @("rev-list", "--count", "main..gnhf/fallback-proof") | Select-Object -First 1).Trim()) -eq 1) -Message "Fallback success lacks a commit ahead of the base."

    Write-Host "PASS: GNHF fail-fast runtime and no-mutation fallback contracts"
}
finally {
    $env:Path = $oldPath
    $env:AGENTSWITCHBOARD_AGY_STATUS_PATH = $oldStatusPath
    $env:FAKE_GNHF_MARKER = $oldMarker
    $env:FAKE_GNHF_MODE = $oldMode

    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
    $resolvedSystemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
    $safeLeaf = Split-Path -Leaf $resolvedTempRoot
    if ($resolvedTempRoot.StartsWith($resolvedSystemTemp, [StringComparison]::OrdinalIgnoreCase) -and $safeLeaf.StartsWith("agentswitchboard-fail-fast-")) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    else {
        throw "Refusing to remove unexpected test path: $resolvedTempRoot"
    }
}
