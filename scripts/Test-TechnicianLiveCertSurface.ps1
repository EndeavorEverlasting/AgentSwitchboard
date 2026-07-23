[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Name, [string]$Message) {
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("${Name}: ${Message}") }
}

function Read-RepoText([string]$RelativePath) {
    return Get-Content -LiteralPath (Join-Path $RootPath $RelativePath) -Raw
}

$baseRelative = 'tooling\profiles\windows\technician-live-cert'
$manifestPath = Join-Path $RootPath "$baseRelative\technician-live-cert.manifest.json"
Check (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'manifest/exists' "Manifest file missing at $manifestPath"

$manifest = $null
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        Check ($manifest.schema -eq 'agentswitchboard.technician-live-cert-manifest.v1') 'manifest/schema' 'Unexpected manifest schema'
        Check ($manifest.manifestVersion -eq 1) 'manifest/version' 'Manifest version must be 1'
        Check (($manifest.coreSequence -join ',') -eq 'P00,P01,P02,P03,P04,P05,P06,P07,P08') 'manifest/core-sequence' 'Core sequence must be P00 through P08 in order'

        Check (Test-Path -LiteralPath (Join-Path $RootPath $manifest.fullRunCmd) -PathType Leaf) 'manifest/fullRunCmd' "$($manifest.fullRunCmd) missing in root"
        Check (Test-Path -LiteralPath (Join-Path $RootPath $manifest.bootstrapCmd) -PathType Leaf) 'manifest/bootstrapCmd' "$($manifest.bootstrapCmd) missing in root"

        foreach ($stage in $manifest.stages) {
            $stageId = $stage.stageId
            Check (Test-Path -LiteralPath (Join-Path $RootPath $stage.cmd) -PathType Leaf) "stage/${stageId}/cmd" "CMD file $($stage.cmd) missing"
            Check (Test-Path -LiteralPath (Join-Path $RootPath "$baseRelative\$($stage.implementation)") -PathType Leaf) "stage/${stageId}/impl" "Implementation $($stage.implementation) missing"
            if ($stage.manualObservationRequired) {
                Check (-not [string]::IsNullOrWhiteSpace([string]$stage.manualObservationPrompt)) "stage/${stageId}/observation-prompt" 'Manual-observation stage lacks a fixed prompt'
            }
        }

        $stageIds = @($manifest.stages | ForEach-Object { $_.stageId })
        foreach ($repair in $manifest.repairs) {
            $repairId = $repair.repairId
            Check (Test-Path -LiteralPath (Join-Path $RootPath $repair.cmd) -PathType Leaf) "repair/${repairId}/cmd" "CMD file $($repair.cmd) missing"
            Check (Test-Path -LiteralPath (Join-Path $RootPath "$baseRelative\$($repair.implementation)") -PathType Leaf) "repair/${repairId}/impl" "Implementation $($repair.implementation) missing"
            foreach ($target in $repair.targetsStages) {
                Check ($stageIds -contains $target) "repair/${repairId}/target/${target}" "Unknown target stage $target"
            }
        }

        $p09 = @($manifest.stages | Where-Object stageId -eq 'P09')[0]
        Check ($p09.optional -eq $true) 'manifest/hermes-optional' 'P09 Hermes must remain optional'
        Check (-not ($manifest.coreSequence -contains 'P09')) 'manifest/hermes-outside-core' 'P09 must not be part of coreSequence'
    }
    catch {
        [void]$failures.Add("manifest/parse: $($_.Exception.Message)")
    }
}

foreach ($schemaName in @(
    'technician-live-cert-manifest.schema.json',
    'technician-live-cert-run.schema.json',
    'technician-live-cert-stage-result.schema.json'
)) {
    $schemaPath = Join-Path $RootPath "$baseRelative\schemas\$schemaName"
    Check (Test-Path -LiteralPath $schemaPath -PathType Leaf) "schema/$schemaName" 'Schema file missing'
    if (Test-Path -LiteralPath $schemaPath -PathType Leaf) {
        try { $null = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json; Check $true "schema/$schemaName/json" '' }
        catch { Check $false "schema/$schemaName/json" $_.Exception.Message }
    }
}

Check (Test-Path -LiteralPath (Join-Path $RootPath 'Open-TechnicianLiveCertEvidence.cmd') -PathType Leaf) 'cmd/open-evidence' 'Open-TechnicianLiveCertEvidence.cmd missing'
Check (Test-Path -LiteralPath (Join-Path $RootPath 'Install-TechnicianLiveCertShortcuts.cmd') -PathType Leaf) 'cmd/install-shortcuts' 'Install-TechnicianLiveCertShortcuts.cmd missing'

$gitignorePath = Join-Path $RootPath '.gitignore'
if (Test-Path -LiteralPath $gitignorePath) {
    $gitignoreText = Get-Content -LiteralPath $gitignorePath -Raw
    Check ($gitignoreText -match 'technician-live-cert/runs') 'gitignore/evidence' '.gitignore must exclude technician live-cert run evidence'
}

$cmdFiles = Get-ChildItem -Path $RootPath -Filter '*.cmd' | Where-Object { $_.Name -match 'Technician|LiveCert|Repair-Technician' }
foreach ($cmd in $cmdFiles) {
    $content = Get-Content -LiteralPath $cmd.FullName -Raw
    Check ($content -match 'exit /b %EXITCODE%' -or $content -match 'exit /b %RESULT%') "cmd/exit-code/$($cmd.Name)" "CMD $($cmd.Name) missing exit-code propagation"
}

$commonText = Read-RepoText "$baseRelative\TechnicianLiveCert.Common.psm1"
foreach ($token in @('active-run.json', 'Set-TechnicianLiveCertActiveRun', 'Get-TechnicianLiveCertActiveRunId', 'Clear-TechnicianLiveCertActiveRun', 'Assert-TechnicianLiveCertRunIdentity')) {
    Check ($commonText.Contains($token)) "common/$token" "Common module missing $token"
}

$dispatcherText = Read-RepoText "$baseRelative\Invoke-TechnicianLiveCertStage.ps1"
foreach ($token in @('-Verb RunAs', '$OriginSid', 'Same-user elevation failed', 'Get-TechnicianLiveCertActiveRunId')) {
    Check ($dispatcherText.Contains($token)) "dispatcher/$token" "Stage dispatcher missing $token"
}
Check (-not $dispatcherText.Contains('-ForegroundColor (if')) 'dispatcher/no-if-command' 'Dispatcher contains invalid executable if-expression argument'

$unsupportedImports = @()
Get-ChildItem -LiteralPath (Join-Path $RootPath $baseRelative) -File -Recurse | Where-Object Extension -in @('.ps1', '.psm1') | ForEach-Object {
    if ((Get-Content -LiteralPath $_.FullName -Raw).Contains('Import-Module -LiteralPath')) {
        $unsupportedImports += $_.FullName
    }
}
Check ($unsupportedImports.Count -eq 0) 'powershell/import-module-path' "Unsupported Import-Module -LiteralPath found: $($unsupportedImports -join ', ')"

$p00 = Read-RepoText "$baseRelative\stages\P00-Preflight.ps1"
foreach ($token in @('wsl.exe', "'Ubuntu'", 'evidenceWritable', 'accountSid', 'TECHNICIAN_LIVE_CERT_CI_SURFACE')) {
    Check ($p00.Contains($token)) "p00/$token" "P00 missing required contract token $token"
}

$p03 = Read-RepoText "$baseRelative\stages\P03-Verify-Commands.ps1"
foreach ($token in @("'wezterm'", "'tmux'", "'agy'", "'opencode'", "'-V'", "'--version'", 'pwsh.exe', 'P03 command verification failed')) {
    Check ($p03.Contains($token)) "p03/$token" "P03 missing required probe token $token"
}

foreach ($stageFile in @('P04-Launch-Shell.ps1', 'P05-Launch-AGY.ps1', 'P06-Launch-OpenCode.ps1')) {
    $text = Read-RepoText "$baseRelative\stages\$stageFile"
    Check ($text.Contains('$proc.ExitCode -ne 0')) "launch/$stageFile/exit-gate" 'Launch stage must gate nonzero child exit'
    Check ($text.Contains('throw')) "launch/$stageFile/throw" 'Launch stage must fail instead of warning-only'
}

$p07 = Read-RepoText "$baseRelative\stages\P07-Repeatability.ps1"
foreach ($token in @("@('setup', 'shell', 'shell', 'agy', 'opencode')", 'devSessionCount', 'agyWindowCount', 'openCodeWindowCount', 'repositoryClean', 'weztermConfigHashBefore', 'tmuxConfigHashBefore')) {
    Check ($p07.Contains($token)) "p07/$token" "P07 missing repeatability invariant $token"
}

$p08 = Read-RepoText "$baseRelative\stages\P08-Finalize.ps1"
Check ($p08.Contains('$requiredPredecessors')) 'p08/predecessor-gate' 'P08 must verify all prior core stages'
Check ($p08.Contains('P08 cannot finalize')) 'p08/fail-incomplete' 'P08 must fail incomplete core runs'

$shimRepair = Read-RepoText "$baseRelative\stages\Repair-Technician-Command-Shims.ps1"
Check ($shimRepair.Contains('Setup-TechnicianAgentSwitchboard.ps1')) 'repair/shims/canonical-setup' 'Shim repair must reuse canonical setup'
foreach ($token in @("'wezterm'", "'tmux'", "'agy'", "'opencode'")) {
    Check ($shimRepair.Contains($token)) "repair/shims/$token" "Shim repair missing $token"
}

$bootstrap = Read-RepoText 'AgentSwitchboard-Technician-Bootstrap.cmd'
Check ($bootstrap.Contains('EXPECTED_PARENT_SHA256=')) 'bootstrap/hash-pin' 'First-machine bootstrap must pin parent SHA-256'
Check ($bootstrap.Contains('Get-FileHash -Algorithm SHA256')) 'bootstrap/hash-verify' 'First-machine bootstrap must verify SHA-256'
Check ($bootstrap.Contains('Run-Technician-LiveCert.cmd')) 'bootstrap/full-run' 'Bootstrap must hand off to full live-cert CMD'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Technician Live-Cert Surface Validation Summary' -ForegroundColor White
Write-Host " Passes: $($passes.Count)" -ForegroundColor Green
Write-Host " Failures: $($failures.Count)" -ForegroundColor $(if ($failures.Count -eq 0) { 'Green' } else { 'Red' })
Write-Host '============================================================' -ForegroundColor Cyan

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "  FAIL: $_" -ForegroundColor Red }
    exit 1
}
exit 0
