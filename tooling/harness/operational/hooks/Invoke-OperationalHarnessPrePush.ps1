[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))),
    [string]$BaseRef
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $RootPath = (Resolve-Path -LiteralPath $RootPath).Path
}
catch {
    Write-Error "Repository root could not be resolved: $RootPath"
    exit 2
}

$validator = Join-Path $RootPath 'scripts/Test-OperationalHarness.ps1'
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    Write-Error "Operational harness validator is missing: $validator"
    exit 3
}

& pwsh -NoLogo -NoProfile -File $validator -RootPath $RootPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ([string]::IsNullOrWhiteSpace($BaseRef)) {
    $upstreamRaw = & git -C $RootPath rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    $gitRc = $LASTEXITCODE
    if ($gitRc -ne 0 -or -not $upstreamRaw) {
        Write-Error 'No upstream branch is configured. Re-run with -BaseRef <exact-base-ref>; stacked branches must name their real base explicitly.'
        exit 4
    }
    $BaseRef = ($upstreamRaw -join '').Trim()
}

$baseShaRaw = & git -C $RootPath rev-parse --verify "$BaseRef^{commit}" 2>$null
$gitRc = $LASTEXITCODE
if ($gitRc -ne 0 -or -not $baseShaRaw) {
    Write-Error "Base ref could not be resolved to a commit: $BaseRef"
    exit 5
}
$baseSha = ($baseShaRaw -join '').Trim()

$headRaw = & git -C $RootPath rev-parse HEAD 2>$null
$gitRc = $LASTEXITCODE
if ($gitRc -ne 0 -or -not $headRaw) {
    Write-Error 'HEAD could not be resolved.'
    exit 6
}
$headSha = ($headRaw -join '').Trim()

& git -C $RootPath diff --check "$baseSha...$headSha"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[PASS] operational pre-push gate base=$BaseRef base_sha=$baseSha head=$headSha"
exit 0
