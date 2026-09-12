[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RequestPath,
  [string]$AdapterId = "pi"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$req = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
if (-not $req.invocationId) { throw "missing invocationId" }
$adapterReg = Get-Content -LiteralPath (Join-Path $PSScriptRoot "adapter-registry.json") -Raw | ConvertFrom-Json
$found = @($adapterReg.adapters | Where-Object { $_.adapterId -eq $AdapterId })
if ($found.Count -eq 0) {
  $err = [ordered]@{ invocationId = $req.invocationId; code = "adapter-absent"; message = "Adapter $AdapterId not registered" }
  $err | ConvertTo-Json -Depth 4 | Write-Host
  exit 2
}
# Fail closed on dirty worktree, default branch, base SHA mismatch, budget
$head = (& git rev-parse HEAD 2>$null).Trim()
if ($req.head -ne $head) { $err = [ordered]@{ invocationId = $req.invocationId; code = "base-sha-mismatch"; message = "base SHA mismatch" }; $err | ConvertTo-Json -Depth 4 | Write-Host; exit 3 }
if ($req.branch -eq "main" -and $req.writeMode -eq "writer-isolated") { $err = [ordered]@{ invocationId = $req.invocationId; code = "default-branch-write"; message = "writer on default branch blocked" }; $err | ConvertTo-Json -Depth 4 | Write-Host; exit 4 }
$dirty = (& git status --porcelain 2>$null | Where-Object { $_ })
if ($dirty -and $req.writeMode -eq "writer-isolated") { $err = [ordered]@{ invocationId = $req.invocationId; code = "dirty-worktree"; message = "dirty worktree blocked" }; $err | ConvertTo-Json -Depth 4 | Write-Host; exit 5 }
Write-Host "DISPATCH_OK $($req.invocationId) via $AdapterId"
exit 0
