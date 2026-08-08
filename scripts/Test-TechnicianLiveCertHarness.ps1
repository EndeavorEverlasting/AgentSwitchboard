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

function Write-GitHubFailureAnnotation {
    param([Parameter(Mandatory)][string]$Message)

    if ($env:GITHUB_ACTIONS -ne 'true') {
        return
    }

    $encoded = $Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    Write-Host "::error title=Technician live-cert harness contract failure::$encoded"
}

$gitPath = $null
if ($env:OS -eq 'Windows_NT') {
    $toolchainValidator = Join-Path $RootPath ([string]$manifest.entrypoints.toolchainPreflightValidator)
    try {
        $toolchainResult = & $toolchainValidator -PassThru
        $gitPath = [string]$toolchainResult.selectedGit
        Add-Result ($toolchainResult.status -eq 'passed' -and -not [string]::IsNullOrWhiteSpace($gitPath)) 'toolchain/git-launch' 'Windows could not prove a concrete Git executable launch.'
    }
    catch {
        Add-Result $false 'toolchain/git-launch' $_.Exception.Message
    }
}
else {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) { $gitPath = $git.Source }
    Add-Result (-not [string]::IsNullOrWhiteSpace($gitPath)) 'toolchain/git-discovery-nonwindows' 'git is unavailable on the non-Windows validation host.'
}

$toolchainText = Get-Content -LiteralPath (Join-Path $RootPath ([string]$manifest.entrypoints.toolchainPreflightValidator)) -Raw
foreach ($token in @(
    'Get-Command git.exe -All',
    'System.Diagnostics.ProcessStartInfo',
    '$psi.UseShellExecute = $false',
    '$process.WaitForExit($TimeoutSeconds * 1000)',
    "`$psi.Arguments = '--version'",
    'windows-toolchain-launch-preflight.json',
    'windows-toolchain-launch-preflight.md'
)) {
    Add-Result ($toolchainText.Contains($token)) "toolchain-contract/$token" "Toolchain preflight missing '$token'"
}

foreach ($component in $manifest.components) {
    $relativePath = [string]$component.path
    $fullPath = Join-Path $RootPath $relativePath
    Add-Result (Test-Path -LiteralPath $fullPath -PathType Leaf) "component/$($component.id)/exists" "Missing $relativePath"

    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        if ($gitPath) {
            & $gitPath -C $RootPath ls-files --error-unmatch -- $relativePath *> $null
            $trackedExit = $LASTEXITCODE
            Add-Result ($trackedExit -eq 0) "component/$($component.id)/tracked" "$relativePath is not tracked in the Git index"
        }
        else {
            Add-Result $false "component/$($component.id)/tracked" 'Git launch/discovery prerequisite is unavailable.'
        }
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
Add-Result ('git-executable-launch-blocked' -in @($manifest.knownFailureGuards.id)) 'guards/git-executable-launch-blocked' 'Manifest must register the executable launch failure guard.'
Add-Result ('status-reporter-parse-and-execution' -in @($manifest.knownFailureGuards.id)) 'guards/status-reporter-parse-and-execution' 'Manifest must register the status reporter parser/execution guard.'

$operatorGuide = Get-Content -LiteralPath (Join-Path $RootPath $manifest.entrypoints.operatorGuide) -Raw
foreach ($token in @(
    'Windows PowerShell 5.1',
    'PowerShell 7',
    'git --no-pager',
    'PSScriptRoot',
    'string/string',
    'proof ceiling',
    'exact operator command',
    'Test-Technician-Toolchain-Preflight.cmd',
    'PATH or `Get-Command`'
)) {
    Add-Result ($operatorGuide.Contains($token)) "operator-guide/$token" "Operator guide missing '$token'"
}

$skill = Get-Content -LiteralPath (Join-Path $RootPath $manifest.entrypoints.skill) -Raw
foreach ($token in @(
    'tooling/profiles/windows/harness/technician-live-cert/manifest.json',
    'scripts/Test-TechnicianLiveCertHarness.ps1',
    'Windows PowerShell 5.1',
    'PowerShell 7',
    'Test-Technician-Toolchain-Preflight.cmd',
    'PATH`, `where`, or `Get-Command`'
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
    'python -m unittest tests.test_windows_toolchain_launch_harness',
    'scripts/Test-WindowsToolchainLaunch.ps1',
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
    $fullPath = Join-Path $RootPath $relativePath
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$tokens, [ref]$parseErrors)
    $parseMessages = @($parseErrors | ForEach-Object { $_.Message })
    Add-Result ($parseMessages.Count -eq 0) "entrypoint/$relativePath/powershell-parse" ($parseMessages -join '; ')

    $text = Get-Content -LiteralPath $fullPath -Raw
    $strictIndex = $text.IndexOf('Set-StrictMode')
    $parameterSurface = if ($strictIndex -gt 0) { $text.Substring(0, $strictIndex) } else { $text }
    Add-Result (-not $parameterSurface.Contains('$PSScriptRoot)')) "entrypoint/$relativePath/no-psscriptroot-default" 'PSScriptRoot must be resolved in the script body'
}

$statusReporterPath = Join-Path $RootPath ([string]$manifest.entrypoints.statusReporter)
$statusOutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("AgentSwitchboard-technician-live-cert-status-{0}" -f [guid]::NewGuid().ToString('N'))
try {
    $statusResult = & $statusReporterPath -RootPath $RootPath -OutputRoot $statusOutputRoot -PassThru
    Add-Result ($null -ne $statusResult) 'status-reporter/result' 'Status reporter returned no result.'
    if ($null -ne $statusResult) {
        Add-Result ($statusResult.status -eq 'READY_FOR_VALIDATION') 'status-reporter/ready' "Status reporter returned '$($statusResult.status)'."
    }
    Add-Result (Test-Path -LiteralPath (Join-Path $statusOutputRoot 'technician-live-cert-harness-status.json') -PathType Leaf) 'status-reporter/json-artifact' 'Status reporter did not generate its JSON artifact.'
    Add-Result (Test-Path -LiteralPath (Join-Path $statusOutputRoot 'technician-live-cert-harness-status.md') -PathType Leaf) 'status-reporter/markdown-artifact' 'Status reporter did not generate its English Markdown artifact.'
}
catch {
    Add-Result $false 'status-reporter/execution' $_.Exception.Message
}
finally {
    Remove-Item -LiteralPath $statusOutputRoot -Recurse -Force -ErrorAction SilentlyContinue
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
        Invoke-Checked $python.Source @('-m', 'unittest', 'tests.test_windows_toolchain_launch_harness') 'child/python-toolchain-launch'
        Invoke-Checked $python.Source @('-m', 'unittest', 'tests.test_technician_live_cert_surface') 'child/python-surface'
    } else {
        Add-Result $false 'child/python' 'python is unavailable'
    }
}

if ($gitPath) {
    & $gitPath -C $RootPath --no-pager diff --check
    Add-Result ($LASTEXITCODE -eq 0) 'git/diff-check' "git diff --check exited with $LASTEXITCODE"
}
else {
    Add-Result $false 'git/diff-check' 'Git launch/discovery prerequisite is unavailable.'
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Technician Live-Cert Harness Validation Summary' -ForegroundColor White
Write-Host " PowerShell: $($PSVersionTable.PSVersion)"
Write-Host " Git: $(if($gitPath){$gitPath}else{'UNAVAILABLE'})"
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