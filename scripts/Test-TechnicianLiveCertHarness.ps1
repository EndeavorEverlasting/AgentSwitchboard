[CmdletBinding()]
param(
    [string]$RootPath,
    [switch]$SkipChildValidators
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve harness validator directory. Supply -RootPath explicitly.'
    }
    $RootPath = Split-Path -Parent $PSScriptRoot
}
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$manifestRelative = 'tooling\profiles\windows\harness\technician-live-cert\manifest.json'
$manifestPath = Join-Path $RootPath $manifestRelative
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Technician live-cert harness manifest is missing: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.harnessId -ne 'agentswitchboard.technician-live-cert-harness.v1') {
    throw "Unexpected technician live-cert harness ID '$($manifest.harnessId)'."
}

$passes = New-Object 'System.Collections.Generic.List[string]'
$failures = New-Object 'System.Collections.Generic.List[string]'

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message
    )
    if ($Condition) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("${Name}: ${Message}")
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    $locationPushed = $false
    try {
        Push-Location -LiteralPath $WorkingDirectory
        $locationPushed = $true
        & $FilePath @ArgumentList
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            $exitCode = 0
        }
    }
    catch {
        Add-Result $false $Name "$FilePath failed from '$WorkingDirectory': $($_.Exception.Message)"
        return
    }
    finally {
        if ($locationPushed) {
            Pop-Location
        }
    }

    Add-Result ($exitCode -eq 0) $Name "$FilePath exited with $exitCode from '$WorkingDirectory'"
}

function Write-GitHubFailureAnnotation {
    param([Parameter(Mandatory)][string]$Message)

    if ($env:GITHUB_ACTIONS -ne 'true') {
        return
    }

    $encoded = $Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    Write-Host "::error title=Technician live-cert harness contract failure::$encoded"
}

foreach ($component in $manifest.components) {
    $relativePath = [string]$component.path
    $fullPath = Join-Path $RootPath $relativePath
    Add-Result (Test-Path -LiteralPath $fullPath -PathType Leaf) "component/$($component.id)/exists" "Missing $relativePath"

    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        $gitRelative = $relativePath.Replace('\', '/')
        & git -C $RootPath ls-files --error-unmatch -- $gitRelative *> $null
        $trackedExit = $LASTEXITCODE
        Add-Result ($trackedExit -eq 0) "component/$($component.id)/tracked" "$gitRelative is not tracked in the Git index"
    }
}

$jsonPaths = @(
    $manifestRelative,
    [string]$manifest.entrypoints.codebaseMap,
    [string]$manifest.entrypoints.artifactRegistry,
    [string]$manifest.entrypoints.maintenanceWorkflow,
    [string]$manifest.entrypoints.fieldFailureRepairWorkflow,
    [string]$manifest.entrypoints.schema,
    [string]$manifest.entrypoints.operatorCommandContract,
    [string]$manifest.entrypoints.operatorCommandFixture,
    [string]$manifest.entrypoints.operatorCommandContractSchema,
    [string]$manifest.entrypoints.operatorCommandFixtureSchema
)
foreach ($relativePath in $jsonPaths) {
    $fullPath = Join-Path $RootPath $relativePath
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        try {
            $null = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
            Add-Result $true "json/$relativePath" ''
        }
        catch {
            Add-Result $false "json/$relativePath" $_.Exception.Message
        }
    }
}

Add-Result ($manifest.generatedEvidence.tracked -eq $false) 'evidence/untracked' 'Generated evidence must remain untracked'
Add-Result ($manifest.implicitHookInstallationAllowed -eq $false) 'hooks/opt-in-only' 'Hook installation must remain opt-in'
Add-Result ($manifest.networkAllowedByValidators -eq $false) 'validators/no-network' 'Focused validators must remain offline'
Add-Result ($manifest.targetMutationAllowedByValidators -eq $false) 'validators/no-target-mutation' 'Focused validators must not mutate targets'

$operatorContract = Get-Content -LiteralPath (Join-Path $RootPath $manifest.entrypoints.operatorCommandContract) -Raw | ConvertFrom-Json
Add-Result ($operatorContract.contractId -eq 'agentswitchboard.operator-command-envelope.v1') 'operator-command/contract-id' 'Unexpected operator-command contract'
Add-Result ($operatorContract.generatedEvidence.tracked -eq $false) 'operator-command/evidence-untracked' 'Operator-command reports must remain untracked'
$ruleIds = @($operatorContract.rules | ForEach-Object { [string]$_.id })
foreach ($requiredRule in @(
    'duplicate-powershell-prompt',
    'powershell-prompt-prefix',
    'cmd-prompt-prefix',
    'continuation-prompt',
    'powershell-error-location',
    'powershell-error-metadata',
    'powershell-error-header',
    'instruction-prose-in-command-block'
)) {
    Add-Result ($requiredRule -in $ruleIds) "operator-command/rule/$requiredRule" "Missing rule $requiredRule"
}

$fixtureText = Get-Content -LiteralPath (Join-Path $RootPath $manifest.entrypoints.operatorCommandFixture) -Raw
Add-Result (-not $fixtureText.Contains('pa_rperez26')) 'operator-command/fixture/no-private-user' 'Fixture contains an operator username'
Add-Result (-not $fixtureText.Contains('Northwell')) 'operator-command/fixture/no-private-org' 'Fixture contains private organization evidence'
Add-Result ($fixtureText.Contains('bad-duplicated-powershell-prompt')) 'operator-command/fixture/duplicated-prompt' 'Duplicated prompt fixture is missing'
Add-Result ($fixtureText.Contains('Get-Process : A positional parameter')) 'operator-command/fixture/get-process-alias' 'Get-Process prompt-contamination symptom fixture is missing'

$operatorGuide = Get-Content -LiteralPath (Join-Path $RootPath $manifest.entrypoints.operatorGuide) -Raw
foreach ($token in @(
    'Windows PowerShell 5.1',
    'PowerShell 7',
    'git --no-pager',
    'PSScriptRoot',
    'string/string',
    'proof ceiling',
    'exact operator command',
    'operator-command envelope',
    'shell prompt',
    'CandidatePath'
)) {
    Add-Result ($operatorGuide.Contains($token)) "operator-guide/$token" "Operator guide missing '$token'"
}

$skill = Get-Content -LiteralPath (Join-Path $RootPath $manifest.entrypoints.skill) -Raw
foreach ($token in @(
    'tooling/profiles/windows/harness/technician-live-cert/manifest.json',
    'scripts/Test-TechnicianLiveCertHarness.ps1',
    'scripts/Test-OperatorCommandEnvelope.ps1',
    '.ai/skills/operator-command-envelope/SKILL.md',
    'Windows PowerShell 5.1',
    'PowerShell 7'
)) {
    Add-Result ($skill.Contains($token)) "skill/$token" "Live-cert skill missing '$token'"
}

$operatorSkill = Get-Content -LiteralPath (Join-Path $RootPath $manifest.entrypoints.operatorCommandSkill) -Raw
foreach ($token in @(
    'Name the shell outside the code fence',
    'Begin at the first executable character',
    'Never include a PowerShell prompt',
    'Never mix stdout, stderr, stack traces',
    'Test-OperatorCommandEnvelope.ps1 -CandidatePath',
    'owner, dependency, expected artifact, and completion gate'
)) {
    Add-Result ($operatorSkill.Contains($token)) "operator-command-skill/$token" "Operator-command skill missing '$token'"
}

$workflowText = Get-Content -LiteralPath (Join-Path $RootPath $manifest.entrypoints.ciWorkflow) -Raw
foreach ($token in @(
    'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Test-OperatorCommandEnvelope.ps1',
    'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TechnicianLiveCertSurface.ps1',
    'Validate harness in Windows PowerShell 5.1 from external working directory',
    'pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1',
    'pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertSurface.ps1',
    'Validate harness in PowerShell 7 from external working directory',
    'Push-Location -LiteralPath $env:RUNNER_TEMP',
    '-RootPath $root',
    'python -m unittest tests.test_operator_command_envelope',
    'python -m unittest tests.test_technician_live_cert_harness',
    'git --no-pager diff --check',
    'operator-command-envelope-report'
)) {
    Add-Result ($workflowText.Contains($token)) "ci/$token" "CI workflow missing '$token'"
}

$entrypointScripts = @(
    'scripts\Test-OperatorCommandEnvelope.ps1',
    'scripts\Test-TechnicianLiveCertSurface.ps1',
    'scripts\Test-TechnicianLiveCertHarness.ps1',
    'tooling\profiles\windows\Get-TechnicianLiveCertHarnessStatus.ps1',
    'tooling\profiles\windows\hooks\Invoke-TechnicianLiveCertPreCommit.ps1'
)
foreach ($relativePath in $entrypointScripts) {
    $text = Get-Content -LiteralPath (Join-Path $RootPath $relativePath) -Raw
    $strictIndex = $text.IndexOf('Set-StrictMode')
    $parameterSurface = if ($strictIndex -gt 0) { $text.Substring(0, $strictIndex) } else { $text }
    Add-Result (-not $parameterSurface.Contains('$PSScriptRoot)')) "entrypoint/$relativePath/no-psscriptroot-default" 'PSScriptRoot must be resolved in the script body'
}

if (-not $SkipChildValidators) {
    $currentPowerShell = (Get-Process -Id $PID).Path

    $operatorValidator = Join-Path $RootPath $manifest.entrypoints.operatorCommandValidator
    Invoke-Checked -FilePath $currentPowerShell -ArgumentList @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $operatorValidator,
        '-RootPath',
        $RootPath,
        '-NoReport'
    ) -Name 'child/operator-command-validator' -WorkingDirectory $RootPath

    $surfaceValidator = Join-Path $RootPath $manifest.entrypoints.surfaceValidator
    Invoke-Checked -FilePath $currentPowerShell -ArgumentList @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $surfaceValidator,
        '-RootPath',
        $RootPath
    ) -Name 'child/surface-validator' -WorkingDirectory $RootPath

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        Invoke-Checked -FilePath $python.Source -ArgumentList @('-m', 'unittest', 'tests.test_operator_command_envelope') -Name 'child/python-operator-command' -WorkingDirectory $RootPath
        Invoke-Checked -FilePath $python.Source -ArgumentList @('-m', 'unittest', 'tests.test_technician_live_cert_harness') -Name 'child/python-harness' -WorkingDirectory $RootPath
        Invoke-Checked -FilePath $python.Source -ArgumentList @('-m', 'unittest', 'tests.test_technician_live_cert_surface') -Name 'child/python-surface' -WorkingDirectory $RootPath
    }
    else {
        Add-Result $false 'child/python' 'python is unavailable'
    }
}

& git -C $RootPath --no-pager diff --check
Add-Result ($LASTEXITCODE -eq 0) 'git/diff-check' "git diff --check exited with $LASTEXITCODE"

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Technician Live-Cert Harness Validation Summary' -ForegroundColor White
Write-Host " PowerShell: $($PSVersionTable.PSVersion)"
Write-Host " Passes: $($passes.Count)" -ForegroundColor Green
$statusColor = if ($failures.Count -eq 0) { 'Green' } else { 'Red' }
Write-Host " Failures: $($failures.Count)" -ForegroundColor $statusColor
Write-Host '============================================================' -ForegroundColor Cyan

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "  FAIL: $failure" -ForegroundColor Red
        Write-GitHubFailureAnnotation -Message $failure
    }
    exit 1
}
exit 0
