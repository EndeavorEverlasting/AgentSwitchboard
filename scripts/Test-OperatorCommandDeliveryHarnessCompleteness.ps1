[CmdletBinding()]
param(
    [string]$CandidatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'tooling/profiles/windows/harness/operator-command-delivery/codebase-map.json',
    'tooling/profiles/windows/harness/operator-command-delivery/artifact-registry.json',
    'tooling/profiles/windows/harness/operator-command-delivery/workflows/verify-command-delivery.workflow.json',
    'tooling/profiles/windows/harness/operator-command-delivery/workflows/handle-command-delivery-failure.workflow.json',
    'tooling/profiles/windows/harness/operator-command-delivery/fixtures/valid-powershell-command.fixture.ps1',
    'tooling/profiles/windows/harness/operator-command-delivery/fixtures/invalid-corrupted-command.fixture.txt',
    'tooling/profiles/windows/harness/operator-command-delivery/fixtures/child-launch-access-denied.fixture.json',
    'tooling/profiles/windows/harness/operator-command-delivery/operator-report.template.md',
    'tooling/profiles/windows/harness/operator-command-delivery/hooks/pre-push.ps1',
    '.ai/skills/operator-command-delivery/SKILL.md',
    'docs/harness/operator-command-delivery.md',
    'scripts/Test-OperatorChildExecutableLaunch.ps1',
    'tests/test_operator_command_delivery_harness.py',
    '.github/workflows/operator-command-delivery-harness.yml'
)

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure([string]$Message) { [void]$failures.Add($Message) }

function Test-OperatorPowerShellText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Label,
        [switch]$RequireFixtureSemantics
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        Add-Failure "$Label has PowerShell parse errors: $($parseErrors[0].Message)"
        return
    }

    if ($Text -match '\$env\\:') { Add-Failure "$Label contains escaped PowerShell environment-variable colon" }
    if ($Text -match '(?m)^\s*PS\s+[A-Za-z]:\\') { Add-Failure "$Label contains a PowerShell prompt marker" }
    if ($Text -match '(?m)^\s*>>') { Add-Failure "$Label contains a continuation prompt marker" }
    if ($Text -match '(?m)^\s*\+\s+(CategoryInfo|FullyQualifiedErrorId)') { Add-Failure "$Label contains transcript decoration" }
    if ($Text -match 'contents/[^\s"'']+\?ref=') { Add-Failure "$Label uses interpolated content query-string retrieval" }

    $exitNodes = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true))
    if ($exitNodes.Count -gt 0) { Add-Failure "$Label contains a PowerShell exit statement that can close the interactive parent shell" }

    if ($RequireFixtureSemantics) {
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        $ghCommands = @($commands | Where-Object { $_.GetCommandName() -eq 'gh' })
        $resolveCommand = @($ghCommands | Where-Object { $_.Extent.Text -match 'repos/EndeavorEverlasting/AgentSwitchboard/commits/' }) | Select-Object -First 1
        $contentCommand = @($ghCommands | Where-Object { $_.Extent.Text -match 'repos/EndeavorEverlasting/AgentSwitchboard/contents/Open-AgentSwitchboard-Tmux\.ps1' }) | Select-Object -First 1
        $childCommand = @($commands | Where-Object { $_.GetCommandName() -eq 'cmd.exe' }) | Select-Object -First 1
        if (-not $resolveCommand) { Add-Failure "$Label is missing executable commit-resolution command" }
        if (-not $contentCommand) { Add-Failure "$Label is missing executable exact-file retrieval command" }
        if ($contentCommand -and $contentCommand.Extent.Text -notmatch 'ref=\$resolved') { Add-Failure "$Label file retrieval is not bound to resolved commit" }
        if (-not $childCommand) { Add-Failure "$Label is missing executable child command" }
        if ($resolveCommand -and $contentCommand -and $resolveCommand.Extent.StartOffset -ge $contentCommand.Extent.StartOffset) { Add-Failure "$Label retrieves content before resolving the commit" }
        if ($contentCommand -and $childCommand -and $contentCommand.Extent.StartOffset -ge $childCommand.Extent.StartOffset) { Add-Failure "$Label launches child before exact file retrieval" }
        if ($Text -notmatch '\$childExit\s*=\s*\$LASTEXITCODE') { Add-Failure "$Label does not capture child exit code" }
        if ($Text -notmatch 'CHILD_EXIT_CODE=') { Add-Failure "$Label does not print child exit code" }
        if ($Text -notmatch 'ARTIFACT=') { Add-Failure "$Label does not print artifact path" }
    }
}

foreach ($relative in $required) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Failure "missing tracked harness component: $relative" }
}

$codebasePath = Join-Path $repoRoot 'tooling/profiles/windows/harness/operator-command-delivery/codebase-map.json'
$artifactPath = Join-Path $repoRoot 'tooling/profiles/windows/harness/operator-command-delivery/artifact-registry.json'
$verifyPath = Join-Path $repoRoot 'tooling/profiles/windows/harness/operator-command-delivery/workflows/verify-command-delivery.workflow.json'
$failurePath = Join-Path $repoRoot 'tooling/profiles/windows/harness/operator-command-delivery/workflows/handle-command-delivery-failure.workflow.json'
$blockedPath = Join-Path $repoRoot 'tooling/profiles/windows/harness/operator-command-delivery/fixtures/child-launch-access-denied.fixture.json'

$codebase = $null
$artifacts = $null
$verify = $null
$failure = $null
$blocked = $null
foreach ($item in @(
    @{ Path = $codebasePath; Name = 'codebase map'; Target = 'codebase' },
    @{ Path = $artifactPath; Name = 'artifact registry'; Target = 'artifacts' },
    @{ Path = $verifyPath; Name = 'verification workflow'; Target = 'verify' },
    @{ Path = $failurePath; Name = 'failure workflow'; Target = 'failure' },
    @{ Path = $blockedPath; Name = 'blocked fixture'; Target = 'blocked' }
)) {
    if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) { continue }
    try {
        $value = Get-Content -LiteralPath $item.Path -Raw | ConvertFrom-Json
        Set-Variable -Name $item.Target -Value $value -Scope Local
    }
    catch { Add-Failure "invalid JSON in $($item.Name): $($_.Exception.Message)" }
}

if ($codebase) {
    if ($codebase.harnessId -ne 'agentswitchboard.operator-command-delivery-harness.v1') { Add-Failure 'codebase map harnessId mismatch' }
    if ($codebase.status -ne 'tracked-contract') { Add-Failure 'codebase map status mismatch' }
    foreach ($property in $codebase.entrypoints.PSObject.Properties) {
        $relative = [string]$property.Value
        if ($relative -and -not (Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)) {
            Add-Failure "codebase map entrypoint is disconnected: $($property.Name) -> $relative"
        }
    }
}

$artifactIds = @()
if ($artifacts) {
    if ($artifacts.harnessId -ne 'agentswitchboard.operator-command-delivery-harness.v1') { Add-Failure 'artifact registry harnessId mismatch' }
    if ($artifacts.tracked -ne $false) { Add-Failure 'artifact registry must keep generated evidence untracked' }
    if ($artifacts.sensitivity -ne 'local-operational') { Add-Failure 'artifact registry sensitivity mismatch' }
    $artifactIds = @($artifacts.artifacts | ForEach-Object { [string]$_.artifactId })
    foreach ($requiredArtifact in @('operator-command-delivery-report','operator-command-delivery-result','child-executable-launch-result','downstream-runtime-artifact')) {
        if ($requiredArtifact -notin $artifactIds) { Add-Failure "artifact registry missing artifact: $requiredArtifact" }
    }
    $childArtifact = @($artifacts.artifacts | Where-Object { $_.artifactId -eq 'child-executable-launch-result' }) | Select-Object -First 1
    if (-not $childArtifact -or $childArtifact.producer -ne 'scripts/Test-OperatorChildExecutableLaunch.ps1') { Add-Failure 'child launch artifact producer is disconnected from concrete probe' }
    if ('childExecutableLaunchArtifacts' -notin @($artifacts.requiredResultFields)) { Add-Failure 'artifact registry missing command-result child launch linkage' }
}

foreach ($workflowPair in @(@{ Name = 'verification'; Value = $verify }, @{ Name = 'failure'; Value = $failure })) {
    $workflow = $workflowPair.Value
    if (-not $workflow) { continue }
    if ($workflow.schema -ne 'agentswitchboard.operator-command-delivery-workflow.v1') { Add-Failure "$($workflowPair.Name) workflow schema mismatch" }
    $orders = @($workflow.steps | ForEach-Object { [int]$_.order })
    if ($orders.Count -eq 0 -or (($orders -join ',') -ne ((1..$orders.Count) -join ','))) { Add-Failure "$($workflowPair.Name) workflow step order is not contiguous from 1" }
    foreach ($step in @($workflow.steps)) {
        if ([string]::IsNullOrWhiteSpace([string]$step.action) -or [string]::IsNullOrWhiteSpace([string]$step.gate)) { Add-Failure "$($workflowPair.Name) workflow has a step without action/gate" }
    }
}
if ($verify) {
    foreach ($artifactId in @($verify.artifacts)) {
        if ($artifactId -notin $artifactIds) { Add-Failure "verification workflow references unregistered artifact: $artifactId" }
    }
    $verifyText = $verify | ConvertTo-Json -Depth 12
    foreach ($token in @('child-executable-launch','UseShellExecute=false','Access is denied','ref=<resolvedCommit>')) {
        if (-not $verifyText.Contains($token)) { Add-Failure "verification workflow missing rule: $token" }
    }
}
if ($failure) {
    $failureText = $failure | ConvertTo-Json -Depth 12
    foreach ($token in @('child-executable-launch','Access is denied','downstream artifact')) {
        if (-not $failureText.Contains($token)) { Add-Failure "failure workflow missing rule: $token" }
    }
}

$validPath = Join-Path $repoRoot 'tooling/profiles/windows/harness/operator-command-delivery/fixtures/valid-powershell-command.fixture.ps1'
$invalidPath = Join-Path $repoRoot 'tooling/profiles/windows/harness/operator-command-delivery/fixtures/invalid-corrupted-command.fixture.txt'
if (Test-Path -LiteralPath $validPath -PathType Leaf) {
    Test-OperatorPowerShellText -Text (Get-Content -LiteralPath $validPath -Raw) -Label 'valid fixture' -RequireFixtureSemantics
}
if (Test-Path -LiteralPath $invalidPath -PathType Leaf) {
    $invalid = Get-Content -LiteralPath $invalidPath -Raw
    if ($invalid -notmatch '\$env\\:TEMP') { Add-Failure 'negative fixture no longer contains escaped TEMP regression' }
    if ($invalid -notmatch '\$env\\:LOCALAPPDATA') { Add-Failure 'negative fixture no longer contains escaped LOCALAPPDATA regression' }
    if ($invalid -notmatch '(?m)^PS\s+[A-Za-z]:\\') { Add-Failure 'negative fixture no longer contains prompt contamination regression' }
    if ($invalid -notmatch 'contents/[^\s"'']+\?ref=') { Add-Failure 'negative fixture no longer contains query-string retrieval regression' }
    if ($invalid -notmatch '(?m);\s*exit\s+\$LASTEXITCODE') { Add-Failure 'negative fixture no longer contains inline top-level exit regression' }
}
if ($blocked) {
    if ($blocked.startError -ne 'Access is denied.') { Add-Failure 'blocked-launch fixture no longer preserves Access is denied regression' }
    if ($blocked.observedWrapperExitCode -ne 5) { Add-Failure 'blocked-launch fixture no longer preserves wrapper exit code 5' }
    if ($blocked.downstreamArtifactProduced -ne $false) { Add-Failure 'blocked-launch fixture must preserve absent downstream artifact' }
    if ($blocked.expectedClassification -ne 'child-executable-launch-blocked') { Add-Failure 'blocked-launch fixture classification changed' }
    if ($blocked.expectedRuntimeProof -ne $false) { Add-Failure 'blocked-launch fixture may not claim runtime proof' }
}

if (-not [string]::IsNullOrWhiteSpace($CandidatePath)) {
    $candidateFull = [IO.Path]::GetFullPath($CandidatePath)
    if (-not (Test-Path -LiteralPath $candidateFull -PathType Leaf)) { Add-Failure "candidate command file does not exist: $candidateFull" }
    else { Test-OperatorPowerShellText -Text (Get-Content -LiteralPath $candidateFull -Raw) -Label 'candidate command' }
}

$probePath = Join-Path $repoRoot 'scripts/Test-OperatorChildExecutableLaunch.ps1'
if (Test-Path -LiteralPath $probePath -PathType Leaf) {
    $probe = Get-Content -LiteralPath $probePath -Raw
    foreach ($token in @('ProcessStartInfo','UseShellExecute = $false','RedirectStandardOutput = $true','RedirectStandardError = $true','WaitForExit','child-executable-launch-result.json','child-executable-launch-blocked','STATUS=','ARTIFACT=','$env:LOCALAPPDATA')) {
        if (-not $probe.Contains($token)) { Add-Failure "child executable probe missing token: $token" }
    }
    if ($probe -match '\bStart-Process\b') { Add-Failure 'child executable probe may not hide launch semantics behind Start-Process' }
}

$skillPath = Join-Path $repoRoot '.ai/skills/operator-command-delivery/SKILL.md'
if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
    $skill = Get-Content -LiteralPath $skillPath -Raw
    foreach ($token in @('version: 1.1.0','Test-OperatorChildExecutableLaunch.ps1','where','Get-Command','child-executable-launch','-CandidatePath')) {
        if (-not $skill.Contains($token)) { Add-Failure "skill missing required rule: $token" }
    }
}
foreach ($routing in @('SKILLS.md','TRIGGERS.md')) {
    $routingPath = Join-Path $repoRoot $routing
    if (-not (Test-Path -LiteralPath $routingPath -PathType Leaf)) { Add-Failure "missing routing surface: $routing" }
    elseif (-not (Get-Content -LiteralPath $routingPath -Raw).Contains('operator-command-delivery')) { Add-Failure "$routing does not route operator-command-delivery" }
}

$reportPath = Join-Path $repoRoot 'tooling/profiles/windows/harness/operator-command-delivery/operator-report.template.md'
if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
    $report = Get-Content -LiteralPath $reportPath -Raw
    foreach ($token in @('{{STATUS}}','{{RESOLVED_COMMIT}}','{{CHILD_EXECUTABLE}}','{{CHILD_LAUNCH_RESULT}}','{{CHILD_START_ERROR}}','{{CHILD_LAUNCH_ARTIFACT}}','{{CHILD_EXIT_CODE}}','{{DOWNSTREAM_ARTIFACT}}','{{PROOF_CEILING}}','{{NEXT_COMMAND}}')) {
        if (-not $report.Contains($token)) { Add-Failure "operator report missing placeholder: $token" }
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'Operator Command Delivery Harness: FAIL' -ForegroundColor Red
    foreach ($failureMessage in $failures) { Write-Host "- $failureMessage" -ForegroundColor Red }
    exit 1
}

Write-Host "Operator Command Delivery Harness: PASS ($($required.Count)/$($required.Count) components)" -ForegroundColor Green
Write-Host 'Guarded regressions: escaped env-var colon, prompt contamination, exact-commit file binding, query-string retrieval, any interactive exit statement, disconnected harness references, and present-but-unlaunchable child executable.'
if ($CandidatePath) { Write-Host "Candidate command validated: $([IO.Path]::GetFullPath($CandidatePath))" }
exit 0
