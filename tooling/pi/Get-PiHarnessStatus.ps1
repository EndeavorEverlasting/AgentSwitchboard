[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputDirectory,
    [switch]$NoWrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$required = @(
    'tooling/pi/harness/codebase-map.json',
    'tooling/pi/harness/pi-adapter.registry.json',
    'tooling/pi/harness/upstream-verification.json',
    'tooling/pi/harness/artifact-registry.json',
    'tooling/pi/harness/workflows/task-intake.workflow.json',
    'tooling/pi/harness/workflows/opinion-fusion.workflow.json',
    'tooling/pi/harness/workflows/autovalidate.workflow.json',
    'tooling/pi/harness/schemas/pi-harness-contracts.schema.json',
    '.ai/skills/pi-fusion-orchestration/SKILL.md',
    '.pi/settings.json',
    'tooling/pi/Install-AgentSwitchboardPi.ps1',
    'tooling/pi/Start-AgentSwitchboardPi.ps1',
    'Install-AgentSwitchboardPi.cmd',
    'Start-AgentSwitchboardPi.cmd',
    'scripts/Test-PiHarnessCompleteness.ps1',
    'tests/test_pi_harness_contracts.py',
    'tests/test_pi_runtime_support.py',
    'tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1',
    'docs/harness/pi-operational-harness.md'
)

function Resolve-NativeCommand {
    param([Parameter(Mandatory)][string[]]$Names)
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command -and $command.Source -and $command.Source -notlike '*.ps1') {
            return $command.Source
        }
    }
    return $null
}

function Read-VersionProbe {
    param(
        [string]$Path,
        [string]$Pattern = '(?<!\d)(\d+\.\d+\.\d+)(?!\d)'
    )
    if (-not $Path) { return $null }
    try {
        $output = & $Path --version 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { return $null }
        $match = [regex]::Match($output, $Pattern)
        if (-not $match.Success) { return $null }
        return [pscustomobject]@{ version = $match.Groups[1].Value; raw = $output.Trim() }
    }
    catch { return $null }
}

$verificationPath = Join-Path $RootPath 'tooling/pi/harness/upstream-verification.json'
$verification = if (Test-Path -LiteralPath $verificationPath -PathType Leaf) {
    Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json
}
else { $null }

$componentResults = foreach ($relativePath in $required) {
    $path = Join-Path $RootPath $relativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $tracked = $false
    if ($exists) {
        $null = & git -C $RootPath ls-files --error-unmatch -- $relativePath 2>$null
        $tracked = $LASTEXITCODE -eq 0
    }
    [ordered]@{ path = $relativePath; exists = $exists; tracked = $tracked }
}

$branch = (& git -C $RootPath branch --show-current 2>$null | Select-Object -First 1)
$head = (& git -C $RootPath rev-parse HEAD 2>$null | Select-Object -First 1)
$dirty = [bool](& git -C $RootPath status --short 2>$null)
$nodePath = Resolve-NativeCommand -Names $(if ($IsWindows) { @('node.exe', 'node') } else { @('node') })
$npmPath = Resolve-NativeCommand -Names $(if ($IsWindows) { @('npm.cmd', 'npm.exe', 'npm') } else { @('npm') })
$piPath = Resolve-NativeCommand -Names $(if ($IsWindows) { @('pi.cmd', 'pi.exe', 'pi') } else { @('pi') })
$nodeProbe = Read-VersionProbe -Path $nodePath -Pattern 'v?(\d+\.\d+\.\d+)'
$npmProbe = Read-VersionProbe -Path $npmPath
$piProbe = Read-VersionProbe -Path $piPath

$missing = @($componentResults | Where-Object { -not $_.exists -or -not $_.tracked })
$broken = [System.Collections.Generic.List[string]]::new()
$working = [System.Collections.Generic.List[string]]::new()
$gaps = [System.Collections.Generic.List[string]]::new()

if ($missing.Count -gt 0) { [void]$broken.Add("$($missing.Count) required tracked component(s) are missing or untracked.") }
if ($dirty) { [void]$broken.Add('The checkout is dirty; a write lane must preserve or isolate unrelated work.') }

$expectedPi = if ($verification) { [version]([string]$verification.version) } else { $null }
$minimumNode = if ($verification) { [version]([string]$verification.minimumNodeVersion) } else { $null }
$nodeReady = $nodeProbe -and ([version]$nodeProbe.version -ge $minimumNode)
$piReady = $piProbe -and ([version]$piProbe.version -eq $expectedPi)

if ($missing.Count -eq 0) {
    [void]$working.Add('Repository-native Pi installer, launcher, project settings, maps, workflows, artifact contracts, schemas, skill, validator, hook, CI, and operator guide are declared.')
    [void]$working.Add('The exact upstream package and version are pinned, and lifecycle scripts are disabled during installation.')
    [void]$working.Add('Project-local settings load repository skills after explicit Pi project trust and disable install telemetry.')
    [void]$working.Add('The launcher disables telemetry and version checks by default, stores sessions outside the repository, and never bypasses project trust.')
}
if ($nodeReady) { [void]$working.Add("Node.js $($nodeProbe.version) satisfies the minimum $minimumNode requirement.") }
elseif (-not $nodePath) { [void]$broken.Add("Node.js $minimumNode or newer is required and was not found.") }
elseif (-not $nodeProbe) { [void]$broken.Add("Node.js was found at '$nodePath' but its version could not be verified.") }
else { [void]$broken.Add("Node.js $($nodeProbe.version) is below the required $minimumNode version.") }

if (-not $npmPath) { [void]$broken.Add('npm was not found; the pinned Pi package cannot be installed.') }
elseif (-not $npmProbe) { [void]$broken.Add("npm was found at '$npmPath' but its version could not be verified.") }
else { [void]$working.Add("npm $($npmProbe.version) is available at $npmPath.") }

if ($piReady) { [void]$working.Add("Pi $($piProbe.version) matches the pinned version at $piPath.") }
elseif (-not $piPath) { [void]$gaps.Add("Pi $expectedPi is not installed. Run the repository installer.") }
elseif (-not $piProbe) { [void]$broken.Add("Pi was found at '$piPath' but its version could not be verified.") }
else { [void]$gaps.Add("Pi $($piProbe.version) is installed, but the repository requires $expectedPi. Run the repository installer to repair it.") }

foreach ($gap in @(
    'Provider login and exact model availability remain runtime proof.',
    'The Pi CLI is free, but provider/model access may require a subscription, API key, or local/custom provider.',
    'Endpoint privacy, telemetry behavior beyond configured controls, and observed outbound connections remain runtime proof.',
    'Opinion fusion and autovalidation remain contract-only until their execution adapters and live evidence are implemented.'
)) { [void]$gaps.Add($gap) }

$status = if ($missing.Count -gt 0) { 'incomplete' }
elseif (-not $nodeReady -or -not $npmProbe) { 'blocked' }
elseif ($piReady) { 'runtime-ready-provider-unproved' }
else { 'installable' }

$nextCommand = switch ($status) {
    'runtime-ready-provider-unproved' { 'pwsh -NoLogo -NoProfile -File tooling/pi/Start-AgentSwitchboardPi.ps1' }
    'installable' { 'pwsh -NoLogo -NoProfile -File tooling/pi/Install-AgentSwitchboardPi.ps1 -Mode Install' }
    default { 'pwsh -NoLogo -NoProfile -File scripts/Test-PiHarnessCompleteness.ps1' }
}

$result = [ordered]@{
    schema = 'agentswitchboard.pi-harness-status.v2'
    status = $status
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    root = $RootPath
    branch = [string]$branch
    head = [string]$head
    dirty = $dirty
    upstream = if ($verification) { [ordered]@{ package = $verification.package; version = $verification.version; minimumNodeVersion = $verification.minimumNodeVersion; verifiedAt = $verification.verifiedAt } } else { $null }
    node = [ordered]@{ state = if ($nodeReady) { 'ready' } elseif ($nodePath) { 'unready' } else { 'missing' }; path = $nodePath; version = if ($nodeProbe) { $nodeProbe.version } else { $null } }
    npm = [ordered]@{ state = if ($npmProbe) { 'ready' } elseif ($npmPath) { 'unready' } else { 'missing' }; path = $npmPath; version = if ($npmProbe) { $npmProbe.version } else { $null } }
    pi = [ordered]@{ state = if ($piReady) { 'ready' } elseif ($piPath) { 'version-mismatch-or-unverified' } else { 'missing' }; path = $piPath; version = if ($piProbe) { $piProbe.version } else { $null } }
    components = $componentResults
    working = $working
    broken = $broken
    missing = @($missing | ForEach-Object { $_.path })
    gaps = $gaps
    proofCeiling = 'Read-only repository component, Node/npm readiness, and Pi exact-version status. No provider login, model response, extension execution, endpoint privacy, or code-delivery proof.'
    nextCommand = $nextCommand
}

$readyCount = @($componentResults | Where-Object { $_.exists -and $_.tracked }).Count
Write-Host 'PI OPERATIONAL HARNESS' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $result.status)
Write-Host ("Branch: {0}" -f $result.branch)
Write-Host ("HEAD: {0}" -f $result.head)
Write-Host ("Node: {0} {1}" -f $result.node.state, $result.node.version)
Write-Host ("npm: {0} {1}" -f $result.npm.state, $result.npm.version)
Write-Host ("Pi: {0} {1}" -f $result.pi.state, $result.pi.version)
Write-Host ("Components: {0}/{1} ready" -f $readyCount, $componentResults.Count)
Write-Host ''
Write-Host 'Working:'
$working | ForEach-Object { Write-Host "- $_" }
Write-Host 'Broken or blocked:'
if ($broken.Count -eq 0) { Write-Host '- None at the observed readiness level.' } else { $broken | ForEach-Object { Write-Host "- $_" } }
Write-Host 'Missing runtime proof:'
$gaps | ForEach-Object { Write-Host "- $_" }
Write-Host "Next: $nextCommand"

if (-not $NoWrite) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/PiHarness/status'
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $jsonPath = Join-Path $OutputDirectory 'pi-harness-status.json'
    $mdPath = Join-Path $OutputDirectory 'pi-harness-status.md'
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM

    $markdown = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @(
        '# Pi Operational Harness Status',
        '',
        ("- Status: {0}" -f $result.status),
        ("- Branch: {0}" -f $result.branch),
        ("- HEAD: {0}" -f $result.head),
        ("- Node: {0} {1}" -f $result.node.state, $result.node.version),
        ("- npm: {0} {1}" -f $result.npm.state, $result.npm.version),
        ("- Pi: {0} {1}" -f $result.pi.state, $result.pi.version),
        ("- Ready components: {0}/{1}" -f $readyCount, $componentResults.Count),
        '',
        '## Working'
    )) { [void]$markdown.Add($line) }
    foreach ($line in $working) { [void]$markdown.Add("- $line") }
    [void]$markdown.Add('')
    [void]$markdown.Add('## Broken or blocked')
    if ($broken.Count -eq 0) { [void]$markdown.Add('- None at the observed readiness level.') }
    else { foreach ($line in $broken) { [void]$markdown.Add("- $line") } }
    [void]$markdown.Add('')
    [void]$markdown.Add('## Missing runtime proof')
    foreach ($line in $gaps) { [void]$markdown.Add("- $line") }
    foreach ($line in @('', '## Proof ceiling', $result.proofCeiling, '', '## Next command', '```powershell', $nextCommand, '```')) {
        [void]$markdown.Add($line)
    }
    $markdown | Set-Content -LiteralPath $mdPath -Encoding utf8
    Write-Host "JSON: $jsonPath"
    Write-Host "Report: $mdPath"
}

if ($missing.Count -gt 0) { exit 1 }
exit 0
