[CmdletBinding()]
param(
    [string]$StageId = 'P03',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Running P03-Verify-Commands stage in fresh PowerShell child processes...' -ForegroundColor Yellow

$commandShimRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin'
if (-not (Test-Path -LiteralPath $commandShimRoot -PathType Container)) {
    throw "AgentSwitchboard command-shim directory is missing: $commandShimRoot"
}

$probeScript = Join-Path $StageDir 'probe-command.ps1'
$probeContent = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CommandName,
    [Parameter(Mandatory)][string]$ShimRoot,
    [Parameter(Mandatory)][string]$OutputPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$result = [ordered]@{
    command = $CommandName
    source = $null
    shimDefinition = $null
    targetDistribution = if ($CommandName -in @('tmux', 'agy', 'opencode')) { 'Ubuntu' } else { $null }
    versionOutput = $null
    exitCode = 1
    passed = $false
    error = $null
}

try {
    $segments = @(
        $ShimRoot,
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $env:Path = $segments -join ';'

    $command = Get-Command $CommandName -ErrorAction Stop
    $result.source = $command.Source
    if ($command.Source -and $command.Source.EndsWith('.cmd', [System.StringComparison]::OrdinalIgnoreCase)) {
        $result.shimDefinition = (Get-Content -LiteralPath $command.Source -Raw).Trim()
    }

    $argument = if ($CommandName -eq 'tmux') { '-V' } else { '--version' }
    $output = (& $command.Source $argument 2>&1 | Out-String).Trim()
    $nativeExit = $LASTEXITCODE
    $result.versionOutput = $output
    $result.exitCode = $nativeExit
    $result.passed = ($nativeExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($output))
    if (-not $result.passed) {
        $result.error = "Version probe failed or returned empty output."
    }
}
catch {
    $result.exitCode = 127
    $result.error = $_.Exception.Message
}

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
if ($result.passed) { exit 0 }
exit $result.exitCode
'@
[System.IO.File]::WriteAllText($probeScript, $probeContent, [System.Text.UTF8Encoding]::new($false))

$pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
$results = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($commandName in @('wezterm', 'tmux', 'agy', 'opencode')) {
    $outputPath = Join-Path $StageDir "probe-$commandName.json"
    & $pwshPath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $probeScript -CommandName $commandName -ShimRoot $commandShimRoot -OutputPath $outputPath
    $probeExit = $LASTEXITCODE

    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        [void]$failures.Add("$commandName did not produce probe evidence")
        continue
    }

    $result = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
    [void]$results.Add($result)
    if ($probeExit -ne 0 -or -not $result.passed) {
        [void]$failures.Add("$commandName exit=$probeExit error=$($result.error)")
        Write-Host "FAIL $commandName: $($result.error)" -ForegroundColor Red
    } else {
        Write-Host "PASS $commandName -> $($result.source) :: $($result.versionOutput)" -ForegroundColor Green
    }
}

$summaryPath = Join-Path $StageDir 'commands-summary.json'
$results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM

if ($failures.Count -gt 0 -or $results.Count -ne 4) {
    throw "P03 command verification failed: $($failures -join '; '). Evidence: $summaryPath"
}

Write-Host 'P03-Verify-Commands passed all four fresh-PowerShell version probes.' -ForegroundColor Green
return 0
