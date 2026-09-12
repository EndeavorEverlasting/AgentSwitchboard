[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Base)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
Push-Location $root
try {
  python tests/test_code_search_harness.py
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & pwsh -NoLogo -NoProfile -File scripts/Test-CodeSearchHarnessCompleteness.ps1
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  git diff --check "$Base...HEAD"
  exit $LASTEXITCODE
} finally { Pop-Location }
