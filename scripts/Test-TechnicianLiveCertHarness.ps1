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
    } else {
        [void]$failures.Add("${Name}: ${Message}")
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$Name
    )
    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
    Add-Result ($exitCode -eq 0) $Name "$FilePath exited with $exitCode"
}

foreach ($component in $manifest.components) {
    $relativePath = [string]$component.path
    $fullPath = Join-Path $RootPath $relativePath
    Add-Result (Test-Path -LiteralPath $fullPath -PathType Leaf) "component/$($component.id)/exists" "Missing $relativePath"

    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        & git -C $RootPath ls-files --error-unmatch -- $relativePath *> $null
        $trackedExit = $LASTEXITCODE
        Add-Result ($trackedExit -eq 0) "component/$($component.id)/tracked" "$relativePath is not tracked in the Git index"
    }
}

$jsonPaths = @(
    $manifestRelative,
    [string]$manifest.entrypoints.codebaseMap,
    [string]$manifest.entrypoints.artifactRegistry,
    [string]$manifest.entrypoints.maintenanceWorkflow,
    [string]$manifest.entrypoints.fieldFailureRepairWorkflow,
    [string]$manifest.entrypoints.schema
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

$operatorGuide = Get-Content -LiteralPath (Join-Path $RootPath $manifest.entrypoints.operatorGuide) -Raw
foreach ($token in @(
    'Windows PowerShell 5.1',
    'PowerShell 7',
    'git --no-pager',
    'PSScriptRoot',
    'string/string',
    'proof ceiling',
    'exact operator command'
)) {
    Add-Result ($operatorGuide.Contains($token)) "operator-guide/$token" "Operator guide missing '$token'"
}

$skill = Get-Content -LiteralPath (Join-Path $RootPath $manifest.entrypoints.skill) -Raw
foreach ($token in @(
    'tooling/profiles/windows/harness/technician-live-cert/manifest.json',
    'scripts/Test-TechnicianLiveCertHarness.ps1',
    'Windows PowerShell 5.1',
    'PowerShell 7'
)) {
    Add-Result ($skill.Contains($token)) "skill/$token" "Live-cert skill missing '$token'"
}

$workflowText = Get-Content -LiteralPath (Join-Path $RootPath $manifest.entrypoints.ciWorkflow) -Raw
foreach ($token in @(
    'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TechnicianLiveCertSurface.ps1',
    'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TechnicianLiveCertHarness.ps1',
    'pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertSurface.ps1',
    'pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertHarness.ps1',
    'python -m unittest tests.test_technician_live_cert_harness',
    'git --no-pager diff --check'
)) {
    Add-Result ($workflowText.Contains($token)) "ci/$token" "CI workflow missing '$token'"
}

$entrypointScripts = @(
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
    $surfaceValidator = Join-Path $RootPath $manifest.entrypoints.surfaceValidator
    $currentPowerShell = (Get-Process -Id $PID).Path
    Invoke-Checked $currentPowerShell @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $surfaceValidator,
        '-RootPath',
        $RootPath
    ) 'child/surface-validator'

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        Invoke-Checked $python.Source @('-m', 'unittest', 'tests.test_technician_live_cert_harness') 'child/python-harness'
        Invoke-Checked $python.Source @('-m', 'unittest', 'tests.test_technician_live_cert_surface') 'child/python-surface'
    } else {
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
    $failures | ForEach-Object { Write-Host "  FAIL: $_" -ForegroundColor Red }
    exit 1
}
exit 0
