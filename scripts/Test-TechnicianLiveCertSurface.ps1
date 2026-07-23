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

$manifestPath = Join-Path $RootPath 'tooling\profiles\windows\technician-live-cert\technician-live-cert.manifest.json'
Check (Test-Path -LiteralPath $manifestPath -PathType Leaf) "manifest/exists" "Manifest file missing at $manifestPath"

if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        Check ($manifest.manifestVersion -eq 1 -or $manifest.version -ne $null) "manifest/version" "Manifest missing version"

        # Check fullRunCmd and bootstrapCmd
        $fullRunCmdPath = Join-Path $RootPath $manifest.fullRunCmd
        Check (Test-Path -LiteralPath $fullRunCmdPath -PathType Leaf) "manifest/fullRunCmd" "$($manifest.fullRunCmd) missing in root"

        $bootstrapCmdPath = Join-Path $RootPath $manifest.bootstrapCmd
        Check (Test-Path -LiteralPath $bootstrapCmdPath -PathType Leaf) "manifest/bootstrapCmd" "$($manifest.bootstrapCmd) missing in root"

        # Check stages wiring
        foreach ($stage in $manifest.stages) {
            $stageId = $stage.stageId
            $cmdFile = Join-Path $RootPath $stage.cmd
            Check (Test-Path -LiteralPath $cmdFile -PathType Leaf) "stage/${stageId}/cmd" "CMD file $($stage.cmd) missing for stage ${stageId}"

            $implFile = Join-Path $RootPath "tooling\profiles\windows\technician-live-cert\$($stage.implementation)"
            Check (Test-Path -LiteralPath $implFile -PathType Leaf) "stage/${stageId}/impl" "Implementation $($stage.implementation) missing for stage ${stageId}"
        }

        # Check repairs wiring
        foreach ($repair in $manifest.repairs) {
            $repairId = $repair.repairId
            $cmdFile = Join-Path $RootPath $repair.cmd
            Check (Test-Path -LiteralPath $cmdFile -PathType Leaf) "repair/${repairId}/cmd" "CMD file $($repair.cmd) missing for repair ${repairId}"

            $implFile = Join-Path $RootPath "tooling\profiles\windows\technician-live-cert\$($repair.implementation)"
            Check (Test-Path -LiteralPath $implFile -PathType Leaf) "repair/${repairId}/impl" "Implementation $($repair.implementation) missing for repair ${repairId}"
        }
    } catch {
        [void]$failures.Add("manifest/parse: $($_.Exception.Message)")
    }
}

# Check helper CMDs: Open evidence and Install shortcuts
Check (Test-Path -LiteralPath (Join-Path $RootPath 'Open-TechnicianLiveCertEvidence.cmd') -PathType Leaf) "cmd/open-evidence" "Open-TechnicianLiveCertEvidence.cmd missing"
Check (Test-Path -LiteralPath (Join-Path $RootPath 'Install-TechnicianLiveCertShortcuts.cmd') -PathType Leaf) "cmd/install-shortcuts" "Install-TechnicianLiveCertShortcuts.cmd missing"

# Check .gitignore excludes runs
$gitignorePath = Join-Path $RootPath '.gitignore'
if (Test-Path -LiteralPath $gitignorePath) {
    $gitignoreText = Get-Content -LiteralPath $gitignorePath -Raw
    Check ($gitignoreText -match 'technician-live-cert/runs' -or $gitignoreText -match 'runs/' -or $gitignoreText -match '\*\.json') "gitignore/evidence" ".gitignore should exclude runtime evidence runs"
}

# Check CMD thin wrapper pattern and exit codes
$cmdFiles = Get-ChildItem -Path $RootPath -Filter "*.cmd" | Where-Object { $_.Name -match 'Technician|LiveCert|Repair-Technician' }
foreach ($cmd in $cmdFiles) {
    $content = Get-Content -LiteralPath $cmd.FullName -Raw
    Check ($content -match 'exit /b %EXITCODE%' -or $content -match 'exit /b %RESULT%') "cmd/exit-code/$($cmd.Name)" "CMD $($cmd.Name) missing standard exit code propagation"
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Technician Live-Cert Surface Validation Summary" -ForegroundColor White
Write-Host " Passes: $($passes.Count)" -ForegroundColor Green
Write-Host " Failures: $($failures.Count)" -ForegroundColor $(if ($failures.Count -eq 0) { 'Green' } else { 'Red' })
Write-Host "============================================================" -ForegroundColor Cyan

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "  FAIL: $_" -ForegroundColor Red }
    exit 1
}

exit 0
