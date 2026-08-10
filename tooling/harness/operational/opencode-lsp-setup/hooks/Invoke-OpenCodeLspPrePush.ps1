[CmdletBinding()]
param([string]$RootPath,[string]$BaseRef='origin/main',[string]$ExpectedHead)
Set-StrictMode -Version Latest; $ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($RootPath)) { $r=@(& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null); if ($LASTEXITCODE -ne 0 -or $r.Count -eq 0) { throw 'Unable to resolve repository root.' }; $RootPath=([string]$r[0]).Trim() }
$head=([string](@(& git -C $RootPath rev-parse HEAD))[0]).Trim(); if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve HEAD.' }
$branch=([string](@(& git -C $RootPath branch --show-current))[0]).Trim(); if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) { throw 'Attached branch required.' }
if ($ExpectedHead -and $head -ne $ExpectedHead) { throw "HEAD mismatch: expected $ExpectedHead got $head" }
$dirty=@(& git -C $RootPath status --porcelain=v1); if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect working tree.' }; if ($dirty.Count -gt 0) { throw 'Pre-push gate requires a clean isolated harness worktree.' }
Push-Location -LiteralPath $RootPath
try { & (Join-Path $RootPath 'Test-OpenCodeLspHarness.cmd'); if ($LASTEXITCODE -ne 0) { throw "OpenCode LSP harness failed: $LASTEXITCODE" }; & git diff --check "$BaseRef...HEAD"; if ($LASTEXITCODE -ne 0) { throw "Outgoing diff check failed: $LASTEXITCODE" } }
finally { Pop-Location }
$after=([string](@(& git -C $RootPath rev-parse HEAD))[0]).Trim(); if ($after -ne $head) { throw 'HEAD moved during pre-push validation.' }
Write-Host "PASS: OpenCode LSP pre-push gate at $head" -ForegroundColor Green
exit 0
