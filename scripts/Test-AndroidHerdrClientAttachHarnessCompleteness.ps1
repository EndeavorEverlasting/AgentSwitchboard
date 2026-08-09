param([string]$RootPath=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop'
function Assert-True([bool]$Condition,[string]$Message){ if(-not $Condition){ throw $Message } }
$base=Join-Path $RootPath 'tooling/profiles/android/harness/herdr/client-attach'
$required=@(
'.ai/skills/android-herdr-client-attach/SKILL.md',
'.github/workflows/android-herdr-client-attach.yml',
'docs/harness/android-herdr-client-attach-harness.md',
'scripts/Test-AndroidHerdrClientAttachHarnessCompleteness.ps1',
'tests/test_android_herdr_client_attach_harness.py',
'tooling/profiles/android/harness/herdr/client-attach/manifest.json',
'tooling/profiles/android/harness/herdr/client-attach/codebase-map.json',
'tooling/profiles/android/harness/herdr/client-attach/workflow-specs.json',
'tooling/profiles/android/harness/herdr/client-attach/artifact-registry.json',
'tooling/profiles/android/harness/herdr/client-attach/upstream-client-attach-source.json',
'tooling/profiles/android/harness/herdr/client-attach/Build-HerdrClientAttachReview.py',
'tooling/profiles/android/harness/herdr/client-attach/Probe-HerdrClientAttach.py',
'tooling/profiles/android/harness/herdr/client-attach/operator-report.template.md',
'tooling/profiles/android/harness/herdr/client-attach/fixtures/herdr-server-start-pass.fixture.env',
'tooling/profiles/android/harness/herdr/client-attach/hooks/Invoke-HerdrClientAttachHarnessPreCommit.sh',
'tooling/profiles/android/harness/herdr/client-attach/hooks/Invoke-HerdrClientAttachHarnessPrePush.sh'
)
foreach($p in $required){ Assert-True (Test-Path -LiteralPath (Join-Path $RootPath $p)) "Missing client-attach harness file: $p" }
$manifest=Get-Content -Raw -LiteralPath (Join-Path $base 'manifest.json') | ConvertFrom-Json
Assert-True ($manifest.canonicalMultiplexer -eq 'tmux') 'tmux must remain canonical'
Assert-True ($manifest.currentGate -eq 'source-bound-client-attach-review') 'unexpected current gate'
$source=Get-Content -Raw -LiteralPath (Join-Path $base 'upstream-client-attach-source.json') | ConvertFrom-Json
Assert-True ($source.reviewDecision -eq 'BOUNDED_CLIENT_PROTOCOL_OBSERVER_PROBE_APPROVED_NO_INSTALL') 'observer decision mismatch'
Assert-True ($source.fullAppTuiDecision -eq 'BLOCKED_AUTODETECT_DAEMON_RACE') 'full-app TUI must remain blocked'
& python (Join-Path $RootPath 'tests/test_android_herdr_client_attach_harness.py')
if($LASTEXITCODE -ne 0){ throw "Python client-attach completeness failed: $LASTEXITCODE" }
& python (Join-Path $base 'Probe-HerdrClientAttach.py') contract
if($LASTEXITCODE -ne 0){ throw "Client-attach probe contract failed: $LASTEXITCODE" }
Write-Host '[PASS] Android Herdr client-attach PowerShell completeness'
