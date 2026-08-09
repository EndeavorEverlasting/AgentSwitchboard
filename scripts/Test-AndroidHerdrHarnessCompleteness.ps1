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
Assert-True ($manifest.candidate.installationReviewDecision -eq 'BLOCKED') 'Current source-bound install review must remain BLOCKED.'
Assert-True ($manifest.candidate.nativeAndroidSourceBuildDecision -eq 'BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK') 'Native Android source-build route must remain blocked at the pinned source.'
Assert-True ($manifest.candidate.linuxMuslPrebuiltProbeDecision -eq 'EXECUTION_PROBE_APPROVED_NO_INSTALL') 'Prebuilt authority must remain no-install identity probe only.'

$required = @(
    'tooling/profiles/android/harness/herdr/manifest.json',
    'tooling/profiles/android/harness/herdr/codebase-map.json',
    'tooling/profiles/android/harness/herdr/artifact-registry.json',
    'tooling/profiles/android/harness/herdr/workflows/workflow-specs.json',
    'tooling/profiles/android/harness/herdr/upstream-installation-source.json',
    'tooling/profiles/android/harness/herdr/upstream-runtime-compatibility.json',
    'tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh',
    'tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py',
    'tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py',
    'tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py',
    'tooling/profiles/android/harness/herdr/Build-HerdrCompatibilityReview.py',
    'tooling/profiles/android/harness/herdr/operator-report.template.md',
    'tooling/profiles/android/harness/herdr/fixtures/herdr-not-installed.fixture.env',
    'tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh',
    'tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh',
    '.ai/skills/android-herdr-migration/SKILL.md',
    'docs/harness/android-herdr-operational-harness.md',
    'docs/workstation/android-herdr-migration.md',
    'tests/test_android_herdr_migration.py',
    'tests/test_android_herdr_install_review.py',
    'tests/test_android_herdr_compatibility_review.py',
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
    'tooling/profiles/android/harness/herdr/upstream-runtime-compatibility.json'
)){
    $null=Get-Content -LiteralPath (Join-Path $RootPath $relative) -Raw | ConvertFrom-Json
}

$install = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/upstream-installation-source.json') -Raw | ConvertFrom-Json
Assert-True ($install.source.releaseTag -eq 'v0.8.0') 'Unexpected pinned Herdr release.'
Assert-True ($install.androidTermuxSupport -eq 'not-stated') 'Android/Termux support must remain explicitly unproved.'
Assert-True ($install.candidate.decision -eq 'BLOCKED') 'Source-bound candidate decision must be BLOCKED.'
Assert-True ([string]::IsNullOrEmpty([string]$install.candidate.installCommand)) 'BLOCKED review must not contain an install command.'

$compat = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/upstream-runtime-compatibility.json') -Raw | ConvertFrom-Json
Assert-True ($compat.source.releaseCommit -eq '346411fa21afd297f5ed3b3fa56f9e3fbf7654b7') 'Compatibility source must be pinned to the reviewed v0.8.0 commit.'
Assert-True ($compat.compatibility.nativeAndroidSourceBuild.decision -eq 'BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK') 'Native Android route must remain blocked.'
Assert-True ($compat.compatibility.linuxMuslPrebuiltOnTermux.buildTarget -eq 'aarch64-unknown-linux-musl') 'Unexpected prebuilt target.'
Assert-True ($compat.reviewDecision -eq 'EXECUTION_PROBE_APPROVED_NO_INSTALL') 'Only the no-install execution probe may be approved.'
Assert-True ($compat.migrationDecision -eq 'KEEP_TMUX') 'tmux must remain the migration decision.'

$probe=Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh') -Raw
foreach($token in @('device_config put','max_phantom_processes','cargo install herdr')){ Assert-True (-not $probe.Contains($token)) "Probe contains forbidden token: $token" }
$prebuiltProbe=Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py') -Raw
foreach($token in @('cargo install herdr','device_config put','max_phantom_processes','PREFIX/bin')){ Assert-True (-not $prebuiltProbe.Contains($token)) "Prebuilt probe contains forbidden token: $token" }
Assert-True ($prebuiltProbe.Contains('[str(candidate), "--version"]')) 'Prebuilt probe must execute only the pinned binary identity command.'
Assert-True ($prebuiltProbe.Contains('XDG_STATE_HOME')) 'Prebuilt evidence writer must honor the artifact registry XDG state-root contract.'
$compatBuilder=Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/Build-HerdrCompatibilityReview.py') -Raw
Assert-True ($compatBuilder.Contains('XDG_STATE_HOME')) 'Compatibility review builder must honor the artifact registry XDG state-root contract.'
$statusReporter=Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py') -Raw
Assert-True ($statusReporter.Contains('--state-root')) 'Status reporter must support isolated validator state roots.'
Assert-True ($statusReporter.Contains('XDG_STATE_HOME')) 'Status reporter must honor the artifact registry XDG state-root contract.'

$python=Get-Command python -ErrorAction SilentlyContinue
if($null -ne $python){
    foreach($relative in @(
        'tests/test_android_herdr_migration.py',
        'tests/test_android_herdr_install_review.py',
        'tests/test_android_herdr_compatibility_review.py',
        'tests/test_android_herdr_status_state_isolation.py',
        'tests/test_android_herdr_harness_completeness.py'
    )){
        & $python.Source (Join-Path $RootPath $relative)
        Assert-True ($LASTEXITCODE -eq 0) "Python contract failed: $relative"
    }
    & $python.Source (Join-Path $RootPath 'tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py') contract
    Assert-True ($LASTEXITCODE -eq 0) 'Prebuilt compatibility contract failed.'
}

$bash=Get-Command bash -ErrorAction SilentlyContinue
if($null -ne $bash){
    foreach($relative in @(
        'Test-AgentSwitchboard-Android-Herdr.sh',
        'tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh',
        'tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh',
        'tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh'
    )){
        & $bash.Source -n (Join-Path $RootPath $relative)
        Assert-True ($LASTEXITCODE -eq 0) "Shell parse failed: $relative"
    }
}

Write-Host '[PASS] Android Herdr harness completeness' -ForegroundColor Green
