[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputDirectory,
    [switch]$NoWrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

function ConvertTo-PowerShellSingleQuotedLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Get-BoundedVersion {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.FileName = $Path
        [void]$psi.ArgumentList.Add('--version')
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) {
            try { $process.Kill($true) } catch {}
            return $null
        }
        if ($process.ExitCode -ne 0) { return $null }
        $combined = (([string]$stdoutTask.GetAwaiter().GetResult(), [string]$stderrTask.GetAwaiter().GetResult()) -join "`n")
        $match = [regex]::Match($combined,'(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
        if ($match.Success) { return $match.Groups[1].Value }
    }
    catch { return $null }
    return $null
}

$required = @(
    'tooling/pi/harness/codebase-map.json',
    'tooling/pi/harness/pi-adapter.registry.json',
    'tooling/pi/harness/upstream-verification.json',
    'tooling/pi/harness/system-bootstrap.contract.json',
    'tooling/pi/harness/child-agent-invocation.contract.json',
    'tooling/pi/harness/artifact-registry.json',
    'tooling/pi/harness/workflows/task-intake.workflow.json',
    'tooling/pi/harness/workflows/opinion-fusion.workflow.json',
    'tooling/pi/harness/workflows/autovalidate.workflow.json',
    'tooling/pi/harness/schemas/pi-harness-contracts.schema.json',
    '.ai/skills/pi-fusion-orchestration/SKILL.md',
    'tooling/pi/Install-AgentSwitchboardPiSystem.ps1',
    'tooling/pi/Invoke-AgentSwitchboardPiChild.ps1',
    'Bootstrap-Pi-SystemWide.cmd',
    'tooling/pi/Test-PiWorkstationPrereqs.ps1',
    'tests/Test-PiWorkstationPrereqsContracts.ps1',
    'tests/test_pi_system_bootstrap.py',
    'scripts/Test-PiHarnessCompleteness.ps1',
    'tests/test_pi_harness_contracts.py',
    'tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1',
    'docs/harness/pi-operational-harness.md',
    'docs/harness/pi-system-bootstrap-and-child-agents.md'
)

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
$upstreamPath = Join-Path $RootPath 'tooling/pi/harness/upstream-verification.json'
$verification = $null
try { $verification = Get-Content -LiteralPath $upstreamPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch {}
$trackedVersion = if ($verification) { [string]$verification.version } else { $null }
$managedPath = if (-not [string]::IsNullOrWhiteSpace($trackedVersion) -and -not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) { Join-Path $env:ProgramFiles "AgentSwitchboard\agents\pi\$trackedVersion\pi.exe" } else { $null }
$managedVersion = Get-BoundedVersion -Path $managedPath
$managedReady = -not [string]::IsNullOrWhiteSpace($trackedVersion) -and $managedVersion -eq $trackedVersion
$pathPiCommand = Get-Command pi -ErrorAction SilentlyContinue
$pathPiPath = if ($pathPiCommand) { [string]$pathPiCommand.Source } else { $null }

$missing = @($componentResults | Where-Object { -not $_.exists -or -not $_.tracked })
$working = @(
    'Repository-native Pi system bootstrap, child-agent invocation contract, npm compatibility preflight, workflow maps, schemas, skill, validators, hook, CI, and operator guides are declared.'
    'The Windows runtime owner is versioned under Program Files and does not require npm or Node.js for the managed standalone Pi runtime.'
    'Machine bootstrap does not own provider authentication, Pi settings, project trust, sessions, models, or project resources.'
    'Child-agent execution uses one AgentSwitchboard mediation seam instead of pairwise agent configuration; writer children require isolated worktrees and one writer per mutation surface.'
    'Workflow selection, opinion fusion, and autovalidation remain contract-only until live provider/model evidence proves them.'
)
$broken = @()
if ($missing.Count -gt 0) { $broken += "$($missing.Count) required tracked component(s) are missing or untracked." }
if ($dirty) { $broken += 'The checkout is dirty; a write lane must preserve or isolate unrelated work.' }
$gaps = @(
    'A managed Pi Program Files installation is not proven unless the exact tracked version executes from the managed runtime path.'
    'Provider/model authentication, model response, project trust, endpoint privacy, and telemetry remain runtime proof.'
    'The child-agent adapter is implemented but a live delegated provider/model run must still prove agent_end, bounded result return, and useful delegated work.'
    'Persistent Pi RPC orchestration remains deliberately deferred until framing, cancellation, session isolation, and result-envelope behavior have dedicated executable tests.'
)

$status = if ($missing.Count -gt 0) { 'incomplete' } elseif ($managedReady) { 'runtime-ready-provider-unproved' } else { 'bootstrap-available-runtime-unproved' }
$managedPathExists = -not [string]::IsNullOrWhiteSpace($managedPath) -and (Test-Path -LiteralPath $managedPath -PathType Leaf)
$piState = if ($managedReady) { 'managed-exact' } elseif ($managedPathExists) { 'managed-version-drift-or-unverified' } elseif ($pathPiCommand) { 'path-present-unmanaged' } else { 'missing' }
$rootLiteral = ConvertTo-PowerShellSingleQuotedLiteral -Value $RootPath
$nextRelativePath = if ($missing.Count -gt 0) { 'scripts/Test-PiHarnessCompleteness.ps1' } else { 'tooling/pi/Install-AgentSwitchboardPiSystem.ps1' }
$nextScriptPath = Join-Path $RootPath $nextRelativePath
$nextScriptLiteral = ConvertTo-PowerShellSingleQuotedLiteral -Value $nextScriptPath
$nextCommand = if ($missing.Count -gt 0) {
    "pwsh -NoLogo -NoProfile -File $nextScriptLiteral -RootPath $rootLiteral"
}
elseif (-not $managedReady) {
    "pwsh -NoLogo -NoProfile -File $nextScriptLiteral -Mode Apply -RootPath $rootLiteral"
}
else {
    "pwsh -NoLogo -NoProfile -File $nextScriptLiteral -Mode Inspect -RootPath $rootLiteral"
}

$result = [ordered]@{
    schema = 'agentswitchboard.pi-harness-status.v2'
    status = $status
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    root = $RootPath
    branch = [string]$branch
    head = [string]$head
    dirty = $dirty
    pi = [ordered]@{ state = $piState; trackedVersion = $trackedVersion; managedPath = $managedPath; managedVersion = $managedVersion; pathResolution = $pathPiPath }
    components = $componentResults
    working = $working
    broken = $broken
    missing = @($missing | ForEach-Object { $_.path })
    gaps = $gaps
    proofCeiling = 'Read-only repository/runtime-presence status. It can execute only the managed pi.exe --version probe; provider/model response, child delivery, privacy, and project trust require separate live evidence.'
    nextCommand = $nextCommand
}

$readyCount = @($componentResults | Where-Object { $_.exists -and $_.tracked }).Count
Write-Host 'PI OPERATIONAL HARNESS' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $result.status)
Write-Host ("Branch: {0}" -f $result.branch)
Write-Host ("HEAD: {0}" -f $result.head)
Write-Host ("Pi: {0}" -f $result.pi.state)
Write-Host ("Managed Pi: {0}" -f $result.pi.managedPath)
Write-Host ("Managed version: {0}" -f $result.pi.managedVersion)
Write-Host ("Components: {0}/{1} ready" -f $readyCount, $componentResults.Count)
Write-Host ''
Write-Host 'Working:'
$working | ForEach-Object { Write-Host "- $_" }
Write-Host 'Broken or blocked:'
if ($broken.Count -eq 0) { Write-Host '- None at repository-contract level.' } else { $broken | ForEach-Object { Write-Host "- $_" } }
Write-Host 'Missing runtime proof:'
$gaps | ForEach-Object { Write-Host "- $_" }
Write-Host "Next: $nextCommand"

if (-not $NoWrite) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/PiHarness/status' }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $jsonPath = Join-Path $OutputDirectory 'pi-harness-status.json'
    $mdPath = Join-Path $OutputDirectory 'pi-harness-status.md'
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    $markdown = @(
        '# Pi Operational Harness Status','',
        ("- Status: {0}" -f $result.status),
        ("- Branch: {0}" -f $result.branch),
        ("- HEAD: {0}" -f $result.head),
        ("- Pi: {0}" -f $result.pi.state),
        ("- Managed path: {0}" -f $result.pi.managedPath),
        ("- Managed version: {0}" -f $result.pi.managedVersion),
        ("- Ready components: {0}/{1}" -f $readyCount, $componentResults.Count),'',
        '## Working'
    ) + @($working | ForEach-Object { "- $_" }) + @('', '## Broken or blocked') + $(if ($broken.Count -eq 0) { @('- None at repository-contract level.') } else { @($broken | ForEach-Object { "- $_" }) }) + @('', '## Missing runtime proof') + @($gaps | ForEach-Object { "- $_" }) + @('', '## Proof ceiling', $result.proofCeiling, '', '## Next command', '```powershell', $nextCommand, '```')
    $markdown | Set-Content -LiteralPath $mdPath -Encoding utf8
    Write-Host "JSON: $jsonPath"
    Write-Host "Report: $mdPath"
}

if ($missing.Count -gt 0) { exit 1 }
exit 0
