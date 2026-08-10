[CmdletBinding()]
param(
    [string]$RootPath,
    [Parameter(Mandatory=$true)][string]$BaseRef,
    [string]$ExpectedHead
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($BaseRef)) { throw 'BaseRef is required and must name the exact outgoing comparison base.' }
if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $r=@(& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $r.Count -eq 0) { throw 'Unable to resolve repository root.' }
    $RootPath=([string]$r[0]).Trim()
}
$baseLines=@(& git -C $RootPath rev-parse --verify "$BaseRef^{commit}" 2>&1)
if ($LASTEXITCODE -ne 0 -or $baseLines.Count -eq 0) { throw "BaseRef cannot be resolved to a commit: $BaseRef" }
$headLines=@(& git -C $RootPath rev-parse HEAD 2>&1)
if ($LASTEXITCODE -ne 0 -or $headLines.Count -eq 0) { throw 'Unable to resolve HEAD.' }
$head=([string]$headLines[0]).Trim()
$branchLines=@(& git -C $RootPath branch --show-current 2>&1)
if ($LASTEXITCODE -ne 0 -or $branchLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$branchLines[0])) { throw 'Attached branch required.' }
if ($ExpectedHead -and $head -ne $ExpectedHead) { throw "HEAD mismatch: expected $ExpectedHead got $head" }
$dirty=@(& git -C $RootPath status --porcelain=v1)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect working tree.' }
if ($dirty.Count -gt 0) { throw 'Pre-push gate requires a clean isolated harness worktree.' }
Push-Location -LiteralPath $RootPath
try {
    & (Join-Path $RootPath 'Test-OpenCodeLspHarness.cmd')
    if ($LASTEXITCODE -ne 0) { throw "OpenCode LSP harness failed: $LASTEXITCODE" }
    & pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-AgentDocumentationContract.ps1') -RootPath $RootPath
    if ($LASTEXITCODE -ne 0) { throw "Agent documentation contract failed: $LASTEXITCODE" }
    & git diff --check "$BaseRef...HEAD"
    if ($LASTEXITCODE -ne 0) { throw "Outgoing diff check failed: $LASTEXITCODE" }
}
finally { Pop-Location }
$after=([string](@(& git -C $RootPath rev-parse HEAD))[0]).Trim()
if ($after -ne $head) { throw 'HEAD moved during pre-push validation.' }
Write-Host "PASS: OpenCode LSP pre-push gate at $head against $BaseRef" -ForegroundColor Green
exit 0
