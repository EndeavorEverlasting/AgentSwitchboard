[CmdletBinding()]
param(
    [string]$RootPath = (Join-Path $PSScriptRoot "..")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Check {
    param([bool]$Condition, [string]$Name, [string]$Message)
    if ($Condition) { [void]$passes.Add($Name) } else { [void]$failures.Add("$Name`: $Message") }
}

$files = @(
    "Gnhf.Process.ps1",
    "Gnhf.Capability.ps1",
    "Start-ProviderRoutedGnhfSprint.ps1",
    "Install-ProviderRoutedGnhf.ps1"
)
foreach ($relative in $files) {
    $path = Join-Path $RootPath $relative
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$relative" "file missing"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        Check ($errors.Count -eq 0) "parse/$relative" (($errors | ForEach-Object Message) -join "; ")
    }
}

$schemaPath = Join-Path $RootPath "..\..\.ai\harness\schemas\gnhf-runtime-capability.schema.json"
Check (Test-Path -LiteralPath $schemaPath -PathType Leaf) "schema/gnhf-runtime-capability" "capability schema missing"
if (Test-Path -LiteralPath $schemaPath -PathType Leaf) {
    try {
        $null = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        Check $true "schema/json-parse" "ok"
    }
    catch {
        Check $false "schema/json-parse" $_.Exception.Message
    }
}

$processText = Get-Content -LiteralPath (Join-Path $RootPath "Gnhf.Process.ps1") -Raw
Check ($processText.Contains('EndsWith(".ps1"')) "dispatch/ps1-detected" "PowerShell shims are not detected"
Check ($processText.Contains('"-NonInteractive"')) "dispatch/pwsh-noninteractive" "pwsh dispatch is not noninteractive"
Check ($processText.Contains('EndsWith(".cmd"')) "dispatch/cmd-detected" "CMD shims are not detected"
Check ($processText.Contains('WaitForExit(5000)')) "dispatch/bounded-post-kill" "timeout cleanup can block indefinitely"
Check ($processText.Contains('function Resolve-OpenCodeNativeExecutable')) "opencode/native-resolve" "native OpenCode resolver missing"
Check ($processText.Contains('function Set-GnhfOpenCodeNativePathOverride')) "opencode/gnhf-path-pin" "GNHF agentPathOverride pin missing"
Check ($processText.Contains('function Test-OpenCodeServeReady')) "opencode/serve-preflight" "OpenCode serve preflight missing"
Check ($processText.Contains('/global/health')) "opencode/health-endpoint" "serve health probe missing"

$launcherText = Get-Content -LiteralPath (Join-Path $RootPath "Start-ProviderRoutedGnhfSprint.ps1") -Raw
Check ($launcherText.Contains('Set-Location -LiteralPath $RepoPath')) "launcher/directory-first" "repository is not entered before runtime logic"
Check ($launcherText.Contains('gnhf-runtime-capability.json')) "launcher/capability-document" "launcher does not consume installed capability document"
Check (-not $launcherText.Contains('GNHF 0.1.42 or newer is required')) "launcher/no-hardcoded-042" "launcher still hardcodes unpublished 0.1.42"
Check ($launcherText.Contains('@("run", "--model", $Model, "--format", "json", $markerPrompt)')) "launcher/opencode-explicit-model" "OpenCode preflight does not require the exact provider/model"
Check ($launcherText.Contains('OPENCODE_CONFIG_CONTENT')) "launcher/opencode-model-pin" "GNHF spawn does not pin the model through OpenCode config"
Check ($launcherText.Contains('if ($evidence.gnhfModelFlag)')) "launcher/optional-gnhf-model-flag" "launcher always passes unsupported GNHF --model"
Check ($launcherText.Contains('Resolve-OpenCodeNativeExecutable')) "launcher/native-opencode" "launcher does not resolve native OpenCode exe"
Check ($launcherText.Contains('Test-OpenCodeServeReady')) "launcher/serve-preflight" "launcher does not preflight opencode serve"
Check ($launcherText.Contains('Set-GnhfOpenCodeNativePathOverride')) "launcher/gnhf-path-override" "launcher does not pin GNHF agentPathOverride"
Check ($launcherText.Contains('$evidence.sprintInvoked = $true')) "launcher/invocation-evidence" "GNHF invocation state is not recorded"
Check ($launcherText.Contains('Process exit zero is not delivery proof')) "launcher/commit-proof" "exit code can be mistaken for delivery"
Check ($launcherText.Contains('DeepSeek provider probe failed; GNHF was not started')) "launcher/provider-fail-fast" "provider failure can fall through into GNHF retries"
Check (-not $launcherText.Contains('DEEPSEEK_API_KEY')) "launcher/no-secret" "provider key handling is embedded"
Check (-not $launcherText.Contains('"--push"')) "launcher/no-push" "unattended provider route enables push"

$installerText = Get-Content -LiteralPath (Join-Path $RootPath "Install-ProviderRoutedGnhf.ps1") -Raw
Check ($installerText.Contains('Set-Location -LiteralPath $RepoRoot')) "installer/directory-first" "installer does not enter AgentSwitchboard first"
Check ($installerText.Contains('Gnhf.Capability.ps1')) "installer/capability-module" "installer does not load capability module"
Check ($installerText.Contains('Select-GnhfDistributionPlan')) "installer/distribution-plan" "installer lacks distribution planning"
Check ($installerText.Contains('Promote-ProviderRouteLaunchers')) "installer/atomic-promote" "installer lacks staged launcher promotion"
Check ($installerText.Contains('gnhf-runtime-capability.json')) "installer/capability-artifact" "installer does not emit capability artifact"
Check (-not $installerText.Contains('RequiredGnhfVersion = "0.1.42"')) "installer/no-hardcoded-042" "installer still defaults to unpublished 0.1.42"
Check (-not $installerText.Contains('throw "GNHF repair completed but --model is still unavailable."')) "installer/no-mandatory-model-flag" "installer still requires fictional GNHF --model"

. (Join-Path $RootPath "Gnhf.Capability.ps1")

$fixtureRoot = Join-Path $RootPath "fixtures\capability"
$npmOk = Get-Content -LiteralPath (Join-Path $fixtureRoot "npm-latest-0.1.41.json") -Raw | ConvertFrom-Json
$npmUnpublished = Get-Content -LiteralPath (Join-Path $fixtureRoot "npm-requested-0.1.42-unpublished.json") -Raw | ConvertFrom-Json
$installedNoModel = Get-Content -LiteralPath (Join-Path $fixtureRoot "installed-gnhf-no-model-flag.json") -Raw | ConvertFrom-Json

$npmFacts = [hashtable]@{
    npmDistTags = $npmOk.npmDistTags
    npmLatest = $npmOk.npmLatest
    npmPublishedVersions = @($npmOk.npmPublishedVersions)
    querySucceeded = $true
    queryError = $null
}
$installedFacts = [hashtable]@{
    commandPath = $installedNoModel.commandPath
    version = $installedNoModel.version
    versionOutput = $installedNoModel.versionOutput
    helpText = $installedNoModel.helpText
}

$runtime = Get-GnhfInstalledRuntimeFacts -Injected $installedFacts
Check ($runtime.cliFlags.model -eq $false) "fixture/no-model-flag" "fixture incorrectly reports --model"
Check ($runtime.cliFlags.worktree -eq $true) "fixture/worktree-flag" "fixture missing --worktree"

$matrixReady = Test-ProviderRouteCapabilityMatrix -InstalledRuntime $runtime -LaunchersPresent $true -OpenCodeModelSelectionAvailable $true
Check ($matrixReady.ready) "capability/matrix-ready-without-model" "published GNHF without --model should satisfy provider-route matrix when OpenCode owns model selection"
Check ($matrixReady.observed.'gnhf.cli.model'.state -eq "absent") "capability/model-optional" "gnhf.cli.model must remain optional"

$matrixLaunchersMissing = Test-ProviderRouteCapabilityMatrix -InstalledRuntime $runtime -LaunchersPresent $false -OpenCodeModelSelectionAvailable $true
Check ($matrixLaunchersMissing.launcherRepairRequired) "capability/launcher-repair" "missing launchers should require launcher repair"
Check (-not $matrixLaunchersMissing.runtimeRepairRequired) "capability/no-runtime-repair-for-launchers" "missing launchers must not force npm runtime repair"

$keepPlan = Select-GnhfDistributionPlan -NpmFacts (Get-GnhfNpmDistributionFacts -Injected $npmFacts) -InstalledRuntime $runtime -CapabilityMatrix $matrixReady
Check ($keepPlan.installFromNpm -eq $false) "distribution/keep-installed" "ready runtime should not reinstall from npm"
Check ($keepPlan.selectedSource -eq "installed-existing" -or $keepPlan.action -eq "refresh-launchers") "distribution/refresh-launchers" "ready runtime should refresh launchers only"

$blockedPlan = Select-GnhfDistributionPlan `
    -NpmFacts (Get-GnhfNpmDistributionFacts -Injected $npmFacts) `
    -InstalledRuntime $runtime `
    -CapabilityMatrix $matrixReady `
    -RequestedNpmVersion $npmUnpublished.requestedNpmVersion
Check ($blockedPlan.action -eq "blocked") "distribution/unpublished-blocked" "unpublished requested version was not blocked"
Check ($blockedPlan.failureClass -eq "BLOCKED_DISTRIBUTION_UNAVAILABLE") "distribution/unpublished-class" "unpublished version failure class incorrect"

$sourceDiff = Get-Content -LiteralPath (Join-Path $fixtureRoot "source-version-differs-from-registry.json") -Raw | ConvertFrom-Json
Check ($sourceDiff.npmLatest -ne $sourceDiff.upstreamSourceVersion) "fixture/source-registry-divergence" "source/registry divergence fixture invalid"

$doc = New-GnhfRuntimeCapabilityDocument `
    -InstallRoot "C:\fixture\fleet" `
    -NpmFacts (Get-GnhfNpmDistributionFacts -Injected $npmFacts) `
    -InstalledRuntime $runtime `
    -CapabilityMatrix $matrixReady `
    -DistributionPlan $keepPlan
Check ($doc.schema -eq "agentswitchboard.gnhf-runtime-capability.v1") "capability/document-schema" "capability document schema mismatch"
Check ($doc.modelSelection.authority -eq "opencode") "capability/model-authority" "model authority must be opencode"
Check ($doc.ready -eq $true) "capability/document-ready" "ready matrix did not produce ready document"

# Failed-install rollback: capability document must not claim ready after simulated failure path.
$failedDoc = New-GnhfRuntimeCapabilityDocument `
    -InstallRoot "C:\fixture\fleet" `
    -NpmFacts (Get-GnhfNpmDistributionFacts -Injected $npmFacts) `
    -InstalledRuntime $runtime `
    -CapabilityMatrix $matrixLaunchersMissing `
    -DistributionPlan ([pscustomobject]@{ selectedSource = "none"; selectedPackageSpec = $null }) `
    -FailureClass "BLOCKED_RUNTIME_CAPABILITY" `
    -RollbackInstructions "restore backup"
Check ($failedDoc.ready -eq $false) "rollback/failed-not-ready" "failed install document claims ready"
Check ($failedDoc.failureClass -eq "BLOCKED_RUNTIME_CAPABILITY") "rollback/failure-class" "failed install missing failure class"

# Provider-preflight fail-fast and no-GNHF-on-failure are enforced by launcher contract text above.
# Zero-exit/no-commit rejection is enforced by launcher commit-proof contract text above.

$temp = Join-Path ([IO.Path]::GetTempPath()) ("agentswitchboard-shim-contract-{0}" -f [guid]::NewGuid().ToString("N"))
try {
    [void](New-Item -ItemType Directory -Path $temp -Force)
    $shim = Join-Path $temp "fake-opencode.ps1"
    @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Remaining)
Write-Output "WINDOWS_SHIM_OK:$($Remaining -join ',')"
exit 0
'@ | Set-Content -LiteralPath $shim -Encoding utf8NoBOM

    . (Join-Path $RootPath "Gnhf.Process.ps1")
    $probe = Invoke-GnhfBoundedCommand -FilePath $shim -ArgumentList @("--version") -WorkingDirectory $temp -TimeoutSeconds 10
    Check ($probe.exitCode -eq 0) "runtime/ps1-shim-exits" "PowerShell shim exit code was $($probe.exitCode)"
    Check ($probe.dispatch -eq "pwsh-file") "runtime/ps1-shim-dispatch" "dispatch was $($probe.dispatch)"
    Check ($probe.output -match 'WINDOWS_SHIM_OK:--version') "runtime/ps1-shim-output" "shim output missing: $($probe.output)"

    # Synthetic install: launchers promote even when runtime is already capability-ready.
    $fleet = Join-Path $temp "fleet"
    [void](New-Item -ItemType Directory -Path $fleet -Force)
    & (Join-Path $RootPath "Install-ProviderRoutedGnhf.ps1") `
        -Apply `
        -InstallRoot $fleet `
        -InjectedNpmFacts $npmFacts `
        -InjectedInstalledRuntime $installedFacts
    Check (Test-Path -LiteralPath (Join-Path $fleet "Start-ProviderRoutedGnhfSprint.ps1") -PathType Leaf) "install/launcher-promoted" "launcher was not promoted"
    Check (Test-Path -LiteralPath (Join-Path $fleet "gnhf-runtime-capability.json") -PathType Leaf) "install/capability-written" "capability document missing"
    $written = Get-Content -LiteralPath (Join-Path $fleet "gnhf-runtime-capability.json") -Raw | ConvertFrom-Json
    Check ($written.ready -eq $true) "install/capability-ready" "synthetic install did not mark ready"
    Check ($written.modelSelection.gnhfCliModelFlag -eq $false) "install/no-model-flag-claim" "capability incorrectly claims GNHF --model"
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

Write-Host "PROVIDER-ROUTED GNHF CONTRACTS" -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
