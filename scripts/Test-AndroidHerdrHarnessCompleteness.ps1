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
Assert-True ($manifest.candidate.installationReviewDecision -eq 'BLOCKED') 'Installation review must remain BLOCKED.'
Assert-True ($manifest.candidate.nativeAndroidSourceBuildDecision -eq 'BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK') 'Native Android source-build route must remain blocked.'
Assert-True ($manifest.candidate.linuxMuslPrebuiltProbeDecision -eq 'EXECUTION_PROBE_APPROVED_NO_INSTALL') 'Prebuilt authority must remain no-install identity only.'
Assert-True ($manifest.candidate.boundedForegroundServerProbeDecision -eq 'BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL') 'Server-start authority must remain bounded foreground no-install only.'

$required = @(
 'tooling/profiles/android/harness/herdr/manifest.json',
 'tooling/profiles/android/harness/herdr/codebase-map.json',
 'tooling/profiles/android/harness/herdr/artifact-registry.json',
 'tooling/profiles/android/harness/herdr/workflows/workflow-specs.json',
 'tooling/profiles/android/harness/herdr/upstream-installation-source.json',
 'tooling/profiles/android/harness/herdr/upstream-runtime-compatibility.json',
 'tooling/profiles/android/harness/herdr/upstream-server-start-source.json',
 'tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh',
 'tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py',
 'tooling/profiles/android/harness/herdr/Probe-HerdrServerStart.py',
 'tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py',
 'tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py',
 'tooling/profiles/android/harness/herdr/Build-HerdrCompatibilityReview.py',
 'tooling/profiles/android/harness/herdr/Build-HerdrServerStartReview.py',
 'tooling/profiles/android/harness/herdr/operator-report.template.md',
 'tooling/profiles/android/harness/herdr/fixtures/herdr-not-installed.fixture.env',
 'tooling/profiles/android/harness/herdr/fixtures/herdr-prebuilt-exec-pass.fixture.env',
 'tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh',
 'tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh',
 '.ai/skills/android-herdr-migration/SKILL.md',
 'docs/harness/android-herdr-operational-harness.md',
 'docs/workstation/android-herdr-migration.md',
 'tests/test_android_herdr_migration.py',
 'tests/test_android_herdr_install_review.py',
 'tests/test_android_herdr_compatibility_review.py',
 'tests/test_android_herdr_server_start_review.py',
 'tests/test_android_herdr_status_state_isolation.py',
 'tests/test_android_herdr_harness_completeness.py',
 'scripts/Test-AndroidHerdrHarnessCompleteness.ps1',
 '.github/workflows/android-herdr-migration.yml',
 'Test-AgentSwitchboard-Android-Herdr.sh'
)
foreach($relative in $required){
 $path=Join-Path $RootPath $relative
 Assert-True (Test-Path -LiteralPath $path) "Missing component: $relative"
 & git -C $RootPath ls-files --error-unmatch -- $relative *> $null
 Assert-True ($LASTEXITCODE -eq 0) "Not tracked: $relative"
}

foreach($relative in @(
 'tooling/profiles/android/harness/herdr/manifest.json',
 'tooling/profiles/android/harness/herdr/codebase-map.json',
 'tooling/profiles/android/harness/herdr/artifact-registry.json',
 'tooling/profiles/android/harness/herdr/workflows/workflow-specs.json',
 'tooling/profiles/android/harness/herdr/upstream-installation-source.json',
 'tooling/profiles/android/harness/herdr/upstream-runtime-compatibility.json',
 'tooling/profiles/android/harness/herdr/upstream-server-start-source.json'
)){ $null=Get-Content -LiteralPath (Join-Path $RootPath $relative) -Raw | ConvertFrom-Json }

$serverSource=Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/upstream-server-start-source.json') -Raw | ConvertFrom-Json
Assert-True ($serverSource.source.releaseCommit -eq '346411fa21afd297f5ed3b3fa56f9e3fbf7654b7') 'Server source must use pinned v0.8.0 commit.'
Assert-True ($serverSource.probe.decision -eq 'BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL') 'Unexpected server-start decision.'
Assert-True (($serverSource.probe.launchCommand -join ' ') -eq 'herdr server') 'Server probe must use explicit foreground herdr server.'
Assert-True (($serverSource.probe.statusCommand -join ' ') -eq 'herdr status server --json') 'Unexpected server status command.'
Assert-True (($serverSource.probe.stopCommand -join ' ') -eq 'herdr server stop') 'Unexpected server stop command.'
Assert-True ($serverSource.migrationDecision -eq 'KEEP_TMUX') 'tmux must remain canonical.'

$serverProbe=Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/Probe-HerdrServerStart.py') -Raw
foreach($token in @('cargo install herdr','device_config put','max_phantom_processes','PREFIX/bin')){ Assert-True (-not $serverProbe.Contains($token)) "Server probe contains forbidden token: $token" }
foreach($token in @('[str(candidate),"server"]','"status","server","--json"','"server","stop"','HERDR_SOCKET_PATH','start_new_session=True','force_cleanup','XDG_CONFIG_HOME','XDG_STATE_HOME')){ Assert-True ($serverProbe.Contains($token)) "Server probe missing contract token: $token" }
$statusReporter=Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py') -Raw
foreach($token in @('--state-root','--prebuilt-evidence','bounded-server-start-review','Build-HerdrServerStartReview.py --write')){ Assert-True ($statusReporter.Contains($token)) "Status reporter missing token: $token" }

$python=Get-Command python -ErrorAction SilentlyContinue
if($null -ne $python){
 foreach($relative in @(
  'tests/test_android_herdr_migration.py',
  'tests/test_android_herdr_install_review.py',
  'tests/test_android_herdr_compatibility_review.py',
  'tests/test_android_herdr_server_start_review.py',
  'tests/test_android_herdr_status_state_isolation.py',
  'tests/test_android_herdr_harness_completeness.py'
 )){
  & $python.Source (Join-Path $RootPath $relative)
  Assert-True ($LASTEXITCODE -eq 0) "Python contract failed: $relative"
 }
 & $python.Source (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py') contract
 Assert-True ($LASTEXITCODE -eq 0) 'Prebuilt compatibility contract failed.'
 & $python.Source (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/Probe-HerdrServerStart.py') contract
 Assert-True ($LASTEXITCODE -eq 0) 'Server-start contract failed.'
}

$bash=Get-Command bash -ErrorAction SilentlyContinue
if($null -ne $bash){
 foreach($relative in @('Test-AgentSwitchboard-Android-Herdr.sh','tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh','tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh','tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh')){
  & $bash.Source -n (Join-Path $RootPath $relative)
  Assert-True ($LASTEXITCODE -eq 0) "Shell parse failed: $relative"
 }
}
Write-Host '[PASS] Android Herdr harness completeness' -ForegroundColor Green
