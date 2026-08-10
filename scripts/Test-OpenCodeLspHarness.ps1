[CmdletBinding()]
param([string]$RootPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RootPath)) { $RootPath = Split-Path -Parent $PSScriptRoot }
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path
$required = @(
 'tooling/harness/operational/opencode-lsp-setup/manifest.json',
 'tooling/harness/operational/opencode-lsp-setup/codebase-map.json',
 'tooling/harness/operational/opencode-lsp-setup/workflows.json',
 'tooling/harness/operational/opencode-lsp-setup/artifact-registry.json',
 'tooling/harness/operational/opencode-lsp-setup/operator-report.template.md',
 'tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1',
 'tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPreCommit.ps1',
 'tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPrePush.ps1',
 '.ai/skills/opencode-lsp-workstation-setup/SKILL.md',
 'docs/harness/opencode-lsp-workstation-setup.md',
 'tests/test_opencode_lsp_harness.py',
 'scripts/Test-OpenCodeLspHarness.ps1',
 'Test-OpenCodeLspHarness.cmd',
 '.github/workflows/opencode-lsp-harness.yml'
)
$failures = [Collections.Generic.List[string]]::new()
foreach ($p in $required) { if (-not (Test-Path -LiteralPath (Join-Path $RootPath $p) -PathType Leaf)) { [void]$failures.Add("missing:$p") } }
foreach ($p in @('manifest.json','codebase-map.json','workflows.json','artifact-registry.json')) {
 try { $null = Get-Content -LiteralPath (Join-Path $RootPath "tooling/harness/operational/opencode-lsp-setup/$p") -Raw | ConvertFrom-Json }
 catch { [void]$failures.Add("invalid-json:$p") }
}
foreach ($p in @('tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1','tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPreCommit.ps1','tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPrePush.ps1','scripts/Test-OpenCodeLspHarness.ps1')) {
 $tokens=$null; $errors=$null; [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $RootPath $p),[ref]$tokens,[ref]$errors)
 if ($errors.Count -gt 0) { [void]$failures.Add("powershell-parse:$p:$($errors[0].Message)") }
}
$manifest = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/manifest.json') -Raw
if (-not $manifest.Contains('opencode-lsp-setup/manifest.json')) { [void]$failures.Add('generic-operational-manifest-route-missing') }
$runner = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1') -Raw
foreach ($token in @('OPENCODE_CONFIG','opencode/nemotron-3-ultra-free','OPENCODE_V2_LSP_UNAVAILABLE','existing','LOCALAPPDATA','lsp=$true','free trial','WRONG_REPOSITORY')) { if (-not $runner.Contains($token)) { [void]$failures.Add("runner-contract:$token") } }
foreach ($forbidden in @('git reset','git clean','git stash','push --force','apiKey','password=')) { if ($runner.ToLowerInvariant().Contains($forbidden.ToLowerInvariant())) { [void]$failures.Add("forbidden-token:$forbidden") } }
if ($failures.Count -gt 0) { Write-Host 'OPENCODE LSP HARNESS: FAIL' -ForegroundColor Red; $failures | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }; exit 1 }
Write-Host "OPENCODE LSP HARNESS: PASS ($($required.Count) required files)" -ForegroundColor Green
exit 0
