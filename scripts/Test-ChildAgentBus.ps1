[CmdletBinding()]param([string]$RootPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RootPath)) { $RootPath = Split-Path -Parent $PSScriptRoot | Split-Path -Parent | Split-Path -Parent }
$bus = Join-Path $RootPath "tooling/harness/child-agent-bus"
foreach ($f in @("schemas/child-agent-request.schema.json","schemas/child-agent-result.schema.json","schemas/child-agent-error.schema.json","adapter-registry.json","artifact-registry.json","Invoke-AgentSwitchboardChild.ps1")) {
  if (-not (Test-Path -LiteralPath (Join-Path $bus $f))) { throw "Missing $f" }
  if ($f -like "*.json") { Get-Content -LiteralPath (Join-Path $bus $f) -Raw | ConvertFrom-Json | Out-Null }
}
# Fixture matrix
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("asb-child-bus-test-" + [guid]::NewGuid().ToString("N").Substring(0,8))
try {
  $null = New-Item -ItemType Directory -Path $tmp -Force
  $reqPath = Join-Path $tmp "req.json"
  $head = (& git -C $RootPath rev-parse HEAD 2>$null).Trim()
  $req = [ordered]@{ invocationId = [guid]::NewGuid().ToString(); lineage = @("root"); authority = "parent"; budgets = [ordered]@{ timeoutSeconds = 30; maxTokens = 1000 }; evidenceRoot = $tmp; repositoryPath = $RootPath; branch = "feat/test"; head = $head; promptPath = "README.md"; writeMode = "read-only" }
  $req | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reqPath -Encoding utf8
  & pwsh -NoLogo -NoProfile -File (Join-Path $bus "Invoke-AgentSwitchboardChild.ps1") -RequestPath $reqPath -AdapterId "missing-adapter" 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 2) { throw "adapter-absent should fail closed with code 2" }
  $req.writeMode = "writer-isolated"; $req.branch = "main"; $req | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reqPath -Encoding utf8
  & pwsh -NoLogo -NoProfile -File (Join-Path $bus "Invoke-AgentSwitchboardChild.ps1") -RequestPath $reqPath -AdapterId "missing-adapter" 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 2) { throw "adapter-absent still 2 even for writer" }
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "[PASS] Child-agent bus contracts"
