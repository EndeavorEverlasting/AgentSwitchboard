[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$required=@(
 'CODE_SEARCH.md',
 'tooling/code-search/harness/manifest.json',
 'tooling/code-search/harness/codebase-map.json',
 'tooling/code-search/harness/provider-registry.json',
 'tooling/code-search/harness/workflow-registry.json',
 'tooling/code-search/harness/artifact-registry.json',
 'tooling/code-search/harness/validator-registry.json',
 'tooling/code-search/harness/schemas/code-search-harness.schema.json',
 'tooling/code-search/Select-CodeSearchProvider.py',
 'tooling/code-search/Search-Codebase.py',
 'tooling/code-search/Get-CodeSearchHarnessStatus.py',
 '.ai/skills/code-search-indexing/SKILL.md',
 'docs/harness/code-search-indexing-harness.md',
 'docs/reports/code-search-indexing-status.md',
 'tests/test_code_search_harness.py',
 '.github/workflows/code-search-harness.yml'
)
$missing=@($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_)) })
if ($missing.Count) { $missing | ForEach-Object { Write-Error "Missing: $_" }; exit 1 }
foreach($p in Get-ChildItem (Join-Path $root 'tooling/code-search/harness') -Recurse -Filter *.json) {
  try { Get-Content $p.FullName -Raw | ConvertFrom-Json | Out-Null } catch { Write-Error "Invalid JSON: $($p.FullName): $_"; exit 1 }
}
foreach($relative in $required) {
  $tracked=& git -C $root ls-files --error-unmatch -- $relative 2>$null
  if ($LASTEXITCODE -ne 0) { Write-Error "Not tracked: $relative"; exit 1 }
}
Write-Host '[PASS] CODE_SEARCH_HARNESS_COMPLETENESS'
