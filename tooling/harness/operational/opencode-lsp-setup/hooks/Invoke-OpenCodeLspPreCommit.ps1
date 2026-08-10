[CmdletBinding()]
param([string]$RootPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $r=@(& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $r.Count -eq 0) { throw 'Unable to resolve repository root.' }
    $RootPath=([string]$r[0]).Trim()
}
$changed=@(& git -C $RootPath diff --cached --name-only --diff-filter=ACMRD)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect staged files.' }
$relevant=@($changed | Where-Object { $_ -match '^(SKILLS\.md$|TRIGGERS\.md$|tooling/harness/operational/workflow-registry\.json$|tooling/harness/operational/opencode-lsp-setup/|scripts/Test-OpenCodeLspHarness\.ps1$|tests/test_opencode_lsp_harness\.py$|Test-OpenCodeLspHarness\.cmd$|docs/harness/opencode-lsp-workstation-setup\.md$|\.ai/skills/opencode-lsp-workstation-setup/|\.github/workflows/opencode-lsp-harness\.yml$|tooling/harness/operational/manifest\.json$)' })
if ($relevant.Count -eq 0) { Write-Host 'SKIP: no staged OpenCode LSP harness paths.'; exit 0 }
Push-Location -LiteralPath $RootPath
try {
    & (Join-Path $RootPath 'Test-OpenCodeLspHarness.cmd')
    if ($LASTEXITCODE -ne 0) { throw "OpenCode LSP harness failed: $LASTEXITCODE" }
    & pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-AgentDocumentationContract.ps1') -RootPath $RootPath
    if ($LASTEXITCODE -ne 0) { throw "Agent documentation contract failed: $LASTEXITCODE" }
    & git diff --cached --check
    if ($LASTEXITCODE -ne 0) { throw "Staged diff check failed: $LASTEXITCODE" }
}
finally { Pop-Location }
Write-Host 'PASS: OpenCode LSP pre-commit gate.' -ForegroundColor Green
exit 0
