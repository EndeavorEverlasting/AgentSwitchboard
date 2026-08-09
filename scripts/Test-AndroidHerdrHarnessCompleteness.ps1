[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){ throw $Message } }
$manifestPath = Join-Path $RootPath 'tooling/profiles/android/harness/herdr/manifest.json'
Assert-True (Test-Path -LiteralPath $manifestPath) "Missing manifest: $manifestPath"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Assert-True ($manifest.harnessId -eq 'agentswitchboard.android-herdr-migration-probe.v1') 'Unexpected Herdr harnessId.'
Assert-True ($manifest.status -eq 'experimental-unproved') 'Herdr status must remain experimental-unproved.'
Assert-True ($manifest.currentRuntime.multiplexer -eq 'tmux') 'tmux must remain canonical.'
$required = @('tooling/profiles/android/harness/herdr/manifest.json','tooling/profiles/android/harness/herdr/codebase-map.json','tooling/profiles/android/harness/herdr/artifact-registry.json','tooling/profiles/android/harness/herdr/workflows/workflow-specs.json','tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh','tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py','tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py','tooling/profiles/android/harness/herdr/operator-report.template.md','tooling/profiles/android/harness/herdr/fixtures/herdr-not-installed.fixture.env','tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh','tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh','.ai/skills/android-herdr-migration/SKILL.md','docs/harness/android-herdr-operational-harness.md','docs/workstation/android-herdr-migration.md','tests/test_android_herdr_migration.py','tests/test_android_herdr_harness_completeness.py','scripts/Test-AndroidHerdrHarnessCompleteness.ps1','.github/workflows/android-herdr-migration.yml','Test-AgentSwitchboard-Android-Herdr.sh')
foreach($relative in $required){ $path=Join-Path $RootPath $relative; Assert-True (Test-Path -LiteralPath $path) "Missing component: $relative"; & git -C $RootPath ls-files --error-unmatch -- $relative *> $null; Assert-True ($LASTEXITCODE -eq 0) "Not tracked: $relative" }
foreach($relative in @('tooling/profiles/android/harness/herdr/manifest.json','tooling/profiles/android/harness/herdr/codebase-map.json','tooling/profiles/android/harness/herdr/artifact-registry.json','tooling/profiles/android/harness/herdr/workflows/workflow-specs.json')){ $null=Get-Content -LiteralPath (Join-Path $RootPath $relative) -Raw | ConvertFrom-Json }
$probe=Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh') -Raw
foreach($token in @('device_config put','max_phantom_processes','cargo install herdr')){ Assert-True (-not $probe.Contains($token)) "Probe contains forbidden token: $token" }
$skill=Get-Content -LiteralPath (Join-Path $RootPath '.ai/skills/android-herdr-migration/SKILL.md') -Raw
foreach($token in @('KEEP_TMUX_HERDR_NOT_INSTALLED','Build-HerdrInstallReview.py --write','canonical Android multiplexer','same-device evidence')){ Assert-True ($skill.Contains($token)) "Skill missing token: $token" }
$python=Get-Command python -ErrorAction SilentlyContinue
if($null -ne $python){ & $python.Source (Join-Path $RootPath 'tests/test_android_herdr_migration.py'); Assert-True ($LASTEXITCODE -eq 0) 'Migration contracts failed.'; & $python.Source (Join-Path $RootPath 'tests/test_android_herdr_harness_completeness.py'); Assert-True ($LASTEXITCODE -eq 0) 'Completeness contracts failed.' }
$bash=Get-Command bash -ErrorAction SilentlyContinue
if($null -ne $bash){ foreach($relative in @('Test-AgentSwitchboard-Android-Herdr.sh','tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh','tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh','tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh')){ & $bash.Source -n (Join-Path $RootPath $relative); Assert-True ($LASTEXITCODE -eq 0) "Shell parse failed: $relative" } }
Write-Host '[PASS] Android Herdr harness completeness' -ForegroundColor Green
