[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$FailureMessage = ""
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("$Name`: $FailureMessage")
    }
}

function Get-RequiredText {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$failures.Add("required-file/$RelativePath`: file is missing")
        return $null
    }

    return Get-Content -LiteralPath $path -Raw
}

# Required files
$readmePath = "tooling/gnhf/README.md"
$adrPath = "docs/architecture/asb-firstmate-runtime-boundary.md"

Add-Result `
    -Passed (Test-Path -LiteralPath (Join-Path $RootPath $readmePath) -PathType Leaf) `
    -Name "required-file/README" `
    -FailureMessage "tooling/gnhf/README.md is missing"

Add-Result `
    -Passed (Test-Path -LiteralPath (Join-Path $RootPath $adrPath) -PathType Leaf) `
    -Name "required-file/ADR" `
    -FailureMessage "docs/architecture/asb-firstmate-runtime-boundary.md is missing"

$readmeText = Get-RequiredText $readmePath
$adrText = Get-RequiredText $adrPath

if ($null -ne $readmeText) {
    # Check for explicit NARROW ownership section
    Add-Result `
        -Passed ($readmeText -match '(?i)##\s*Ownership\s+boundary') `
        -Name "ownership/section-header" `
        -FailureMessage "README must contain '## Ownership boundary' section"

    # Check for NARROW boundary language
    Add-Result `
        -Passed ($readmeText -match '(?i)\bNARROW\s+boundary\b') `
        -Name "ownership/narrow-keyword" `
        -FailureMessage "README must explicitly state 'NARROW boundary'"

    # Check for Windows-first bounded single-agent/fleet launcher identity
    Add-Result `
        -Passed ($readmeText -match '(?i)Windows-first\s+bounded\s+single-agent') `
        -Name "ownership/windows-single-agent" `
        -FailureMessage "README must state 'Windows-first bounded single-agent' identity"

    # Check for FirstMate canonical crew runtime reference
    Add-Result `
        -Passed ($readmeText -match '(?i)FirstMate.*canonical.*crew\s+runtime') `
        -Name "ownership/firstmate-reference" `
        -FailureMessage "README must reference FirstMate as canonical crew runtime"

    # Check for ADR citation
    Add-Result `
        -Passed ($readmeText -match 'ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME') `
        -Name "ownership/adr-cite" `
        -FailureMessage "README must cite ADR ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME"

    Add-Result `
        -Passed ($readmeText -match 'docs/architecture/asb-firstmate-runtime-boundary\.md') `
        -Name "ownership/adr-path" `
        -FailureMessage "README must reference ADR path docs/architecture/asb-firstmate-runtime-boundary.md"

    # Check for explicit forbid multi-crew control plane language
    Add-Result `
        -Passed ($readmeText -match '(?i)must\s+not\s+expand.*multi-crew.*control\s+plane') `
        -Name "ownership/forbid-multi-crew" `
        -FailureMessage "README must forbid expanding into multi-crew control plane"

    # Check for competing with FirstMate language
    Add-Result `
        -Passed ($readmeText -match '(?i)competing\s+with\s+FirstMate') `
        -Name "ownership/competing-firstmate" `
        -FailureMessage "README must state boundary prevents competing with FirstMate"

    # Negative check: ensure no crew orchestration claims
    Add-Result `
        -Passed ($readmeText -notmatch '(?i)GNHF.*(?:crew|multi-agent)\s+(?:orchestration|supervision|control\s+plane)') `
        -Name "ownership/no-crew-claims" `
        -FailureMessage "README must not claim GNHF is a crew orchestration platform"
}

if ($null -ne $adrText) {
    # Verify ADR exists and contains the ownership matrix
    Add-Result `
        -Passed ($adrText -match 'FirstMate.*canonical live crew runtime') `
        -Name "adr/firstmate-canonical" `
        -FailureMessage "ADR must establish FirstMate as canonical crew runtime"

    Add-Result `
        -Passed ($adrText -match '(?i)tooling/gnhf.*NARROW') `
        -Name "adr/gnhf-narrow" `
        -FailureMessage "ADR must contain GNHF NARROW disposition"

    Add-Result `
        -Passed ($adrText -match '(?i)Windows-first\s+bounded\s+single-agent') `
        -Name "adr/gnhf-identity" `
        -FailureMessage "ADR must define GNHF as Windows-first bounded single-agent launcher"
}

# Summary
Write-Host ""
Write-Host "GNHF Narrow Ownership Contract Validation"
Write-Host "=========================================="
Write-Host ""

if ($passes.Count -gt 0) {
    Write-Host "PASSED ($($passes.Count)):"
    foreach ($pass in $passes | Sort-Object) {
        Write-Host "  ✓ $pass" -ForegroundColor Green
    }
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "FAILED ($($failures.Count)):" -ForegroundColor Red
    foreach ($failure in $failures | Sort-Object) {
        Write-Host "  ✗ $failure" -ForegroundColor Red
    }
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "All checks passed." -ForegroundColor Green
exit 0
