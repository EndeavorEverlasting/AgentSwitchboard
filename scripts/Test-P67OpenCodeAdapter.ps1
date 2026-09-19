[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([Parameter(Mandatory)][bool]$Passed, [Parameter(Mandatory)][string]$Name, [string]$FailureMessage = '')
    if ($Passed) { [void]$passes.Add($Name) } else { [void]$failures.Add("${Name}: $FailureMessage") }
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $RootPath $RelativePath
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    catch { [void]$failures.Add("json/${RelativePath}: $($_.Exception.Message)"); return $null }
}

$adapterDir = Join-Path $RootPath 'tooling/evals/p67-opencode-adapter'
$probeScript = Join-Path $adapterDir 'Get-P67OpenCodeAdapterStatus.ps1'
$capabilityContract = Join-Path $adapterDir 'capability-contract.v1.json'
$fixturesDir = Join-Path $adapterDir 'fixtures'

$required = @(
    'tooling/evals/p67-opencode-adapter/Get-P67OpenCodeAdapterStatus.ps1',
    'tooling/evals/p67-opencode-adapter/capability-contract.v1.json',
    'tooling/evals/p67-opencode-adapter/fixtures/readiness-ready.json',
    'tooling/evals/p67-opencode-adapter/fixtures/readiness-blocked-not-found.json',
    'tooling/evals/p67-opencode-adapter/fixtures/readiness-blocked-identity.json',
    'tooling/evals/p67-opencode-adapter/fixtures/readiness-evaluative-rejected.json',
    'tests/test_p67_opencode_adapter.py',
    'scripts/Test-P67OpenCodeAdapter.ps1'
)
foreach ($relative in $required) {
    Add-Result (Test-Path -LiteralPath (Join-Path $RootPath $relative) -PathType Leaf) "required-file/$relative" 'missing required ADP-01 component'
}

$contract = Read-JsonFile 'tooling/evals/p67-opencode-adapter/capability-contract.v1.json'
if ($null -ne $contract) {
    Add-Result ($contract.schema_version -eq 'p67-opencode-capability-contract/v1') 'contract/schema-version' 'unexpected schema version'

    Add-Result ($null -ne $contract.required_capabilities) 'contract/required-capabilities' 'required capabilities missing'
    if ($null -ne $contract.required_capabilities) {
        $caps = $contract.required_capabilities
        Add-Result ($null -ne $caps.noninteractive_execution) 'contract/capability/noninteractive' 'noninteractive execution capability missing'
        Add-Result ($null -ne $caps.explicit_identity) 'contract/capability/identity' 'explicit identity capability missing'
        Add-Result ($null -ne $caps.isolated_config) 'contract/capability/config' 'isolated config capability missing'
        Add-Result ($null -ne $caps.instrumentation_feasibility) 'contract/capability/instrumentation' 'instrumentation capability missing'
        Add-Result ($null -ne $caps.auth_readiness) 'contract/capability/auth' 'auth readiness capability missing'
    }

    Add-Result ($null -ne $contract.blocker_codes) 'contract/blocker-codes' 'blocker codes missing'
    if ($null -ne $contract.blocker_codes) {
        $blockers = @($contract.blocker_codes)
        Add-Result ($blockers -contains 'OPENCODE_NOT_FOUND') 'contract/blocker/not-found' 'OPENCODE_NOT_FOUND blocker missing'
        Add-Result ($blockers -contains 'OPENCODE_AUTH_UNAVAILABLE') 'contract/blocker/auth' 'OPENCODE_AUTH_UNAVAILABLE blocker missing'
        Add-Result ($blockers -contains 'OPENCODE_IDENTITY_OPAQUE') 'contract/blocker/identity' 'OPENCODE_IDENTITY_OPAQUE blocker missing'
    }

    Add-Result ($null -ne $contract.alignment_with_triage_contract) 'contract/triage-alignment' 'Triage contract alignment missing'
    if ($null -ne $contract.alignment_with_triage_contract) {
        $reused = @($contract.alignment_with_triage_contract.invalid_run_codes_reused)
        Add-Result ($reused -contains 'RUNTIME_UNAVAILABLE') 'contract/triage-alignment/runtime-unavailable' 'RUNTIME_UNAVAILABLE not aligned with Triage'
    }

    Add-Result ($null -ne $contract.forbidden_mutations) 'contract/forbidden-mutations' 'forbidden mutations missing'
    if ($null -ne $contract.forbidden_mutations) {
        $forbidden = @($contract.forbidden_mutations) -join ' '
        Add-Result ($forbidden -match 'credential') 'contract/forbidden/credential' 'credential mutation not forbidden'
        Add-Result ($forbidden -match 'prompt|response') 'contract/forbidden/prompt-response' 'prompt/response persistence not forbidden'
        Add-Result ($forbidden -match 'config') 'contract/forbidden/config' 'global config mutation not forbidden'
    }

    Add-Result ($null -ne $contract.readiness_status_schema) 'contract/status-schema' 'readiness status schema missing'
    if ($null -ne $contract.readiness_status_schema) {
        $statusSchema = $contract.readiness_status_schema
        Add-Result ($statusSchema.schema_version -eq 'p67-opencode-readiness-status/v1') 'contract/status-schema/version' 'unexpected status schema version'

        Add-Result ($null -ne $statusSchema.forbidden_fields) 'contract/status-schema/forbidden-fields' 'forbidden fields not defined'
        if ($null -ne $statusSchema.forbidden_fields) {
            $forbiddenFields = @($statusSchema.forbidden_fields)
            Add-Result ($forbiddenFields -contains 'api_key') 'contract/status-schema/forbidden/api-key' 'api_key not forbidden'
            Add-Result ($forbiddenFields -contains 'token') 'contract/status-schema/forbidden/token' 'token not forbidden'
            Add-Result ($forbiddenFields -contains 'secret') 'contract/status-schema/forbidden/secret' 'secret not forbidden'
            Add-Result ($forbiddenFields -contains 'password') 'contract/status-schema/forbidden/password' 'password not forbidden'
        }
    }

    Add-Result ($contract.proof_boundary -match 'Capability verification only') 'contract/proof-boundary' 'proof boundary not explicit'
}

$readyFixture = Read-JsonFile 'tooling/evals/p67-opencode-adapter/fixtures/readiness-ready.json'
if ($null -ne $readyFixture) {
    Add-Result ($readyFixture.schema_version -eq 'p67-opencode-readiness-status/v1') 'fixture/ready/schema' 'unexpected schema'
    Add-Result ($readyFixture.status -eq 'READY') 'fixture/ready/status' 'status not READY'
    Add-Result ($readyFixture.opencode_found -eq $true) 'fixture/ready/found' 'opencode_found not true'
    Add-Result ($null -ne $readyFixture.opencode_version) 'fixture/ready/version' 'version missing'
    Add-Result ($null -eq $readyFixture.blocker) 'fixture/ready/no-blocker' 'blocker should be null for READY status'
}

$blockedFixture = Read-JsonFile 'tooling/evals/p67-opencode-adapter/fixtures/readiness-blocked-not-found.json'
if ($null -ne $blockedFixture) {
    Add-Result ($blockedFixture.status -eq 'BLOCKED') 'fixture/blocked/status' 'status not BLOCKED'
    Add-Result ($blockedFixture.opencode_found -eq $false) 'fixture/blocked/not-found' 'opencode_found should be false'
    Add-Result ($null -ne $blockedFixture.blocker) 'fixture/blocked/has-blocker' 'blocker missing'
    if ($null -ne $blockedFixture.blocker) {
        Add-Result ($blockedFixture.blocker.code -eq 'OPENCODE_NOT_FOUND') 'fixture/blocked/blocker-code' 'unexpected blocker code'
        Add-Result ($blockedFixture.blocker.message.Length -gt 10) 'fixture/blocked/blocker-message' 'blocker message too short'
    }
}

$identityBlockedFixture = Read-JsonFile 'tooling/evals/p67-opencode-adapter/fixtures/readiness-blocked-identity.json'
if ($null -ne $identityBlockedFixture) {
    Add-Result ($identityBlockedFixture.status -eq 'BLOCKED') 'fixture/identity-blocked/status' 'status not BLOCKED'
    Add-Result ($null -ne $identityBlockedFixture.blocker) 'fixture/identity-blocked/has-blocker' 'blocker missing'
    if ($null -ne $identityBlockedFixture.blocker) {
        Add-Result ($identityBlockedFixture.blocker.code -eq 'OPENCODE_IDENTITY_OPAQUE') 'fixture/identity-blocked/code' 'unexpected blocker code'
    }
}

$evaluativeFixture = Read-JsonFile 'tooling/evals/p67-opencode-adapter/fixtures/readiness-evaluative-rejected.json'
if ($null -ne $evaluativeFixture) {
    $fixtureJson = $evaluativeFixture | ConvertTo-Json -Depth 10
    Add-Result ($fixtureJson -match 'FORBIDDEN_FIELD') 'fixture/evaluative/forbidden-marker' 'fixture should contain FORBIDDEN_FIELD markers'
    Add-Result ($fixtureJson -match 'api_key') 'fixture/evaluative/api-key' 'fixture should contain forbidden api_key field'
}

if (Test-Path -LiteralPath $probeScript -PathType Leaf) {
    $probeContent = Get-Content -LiteralPath $probeScript -Raw

    Add-Result ($probeContent -match 'Read-only probe') 'probe/read-only-claim' 'probe does not declare read-only nature'
    Add-Result ($probeContent -match 'ADP-01') 'probe/adp-01-marker' 'probe does not reference ADP-01'
    Add-Result ($probeContent -notmatch 'Set-Content.*global|Remove-Item.*-Recurse') 'probe/no-destructive-ops' 'probe contains potentially destructive operations'

    Add-Result ($probeContent -match 'OPENCODE_NOT_FOUND') 'probe/blocker/not-found' 'OPENCODE_NOT_FOUND blocker not implemented'
    Add-Result ($probeContent -match 'OPENCODE_AUTH_UNAVAILABLE') 'probe/blocker/auth' 'OPENCODE_AUTH_UNAVAILABLE blocker not implemented'
    Add-Result ($probeContent -match 'OPENCODE_IDENTITY_OPAQUE') 'probe/blocker/identity' 'OPENCODE_IDENTITY_OPAQUE blocker not implemented'

    Add-Result ($probeContent -match 'p67-opencode-readiness-status/v1') 'probe/status-schema' 'probe does not output correct schema version'

    Add-Result ($probeContent -match 'noninteractive_execution') 'probe/capability/noninteractive' 'probe does not check noninteractive capability'
    Add-Result ($probeContent -match 'explicit_identity') 'probe/capability/identity' 'probe does not check identity capability'
    Add-Result ($probeContent -match 'isolated_config') 'probe/capability/config' 'probe does not check config capability'
    Add-Result ($probeContent -match 'instrumentation_feasibility') 'probe/capability/instrumentation' 'probe does not check instrumentation capability'
    Add-Result ($probeContent -match 'auth_readiness') 'probe/capability/auth' 'probe does not check auth capability'

    try {
        $tempOutput = [System.IO.Path]::GetTempFileName()
        $probeResult = & pwsh -NoLogo -NoProfile -File $probeScript -OutputPath $tempOutput -ErrorAction Stop
        $probeExitCode = $LASTEXITCODE

        Add-Result ($probeExitCode -eq 0) 'probe/execution/exit-code' "probe exited with non-zero code: $probeExitCode"

        if (Test-Path -LiteralPath $tempOutput -PathType Leaf) {
            $status = Get-Content -LiteralPath $tempOutput -Raw | ConvertFrom-Json

            Add-Result ($status.schema_version -eq 'p67-opencode-readiness-status/v1') 'probe/execution/schema' 'probe output has incorrect schema'
            Add-Result ($status.status -in @('READY','BLOCKED')) 'probe/execution/status' 'probe status not READY or BLOCKED'
            Add-Result ($null -ne $status.opencode_found) 'probe/execution/found' 'opencode_found missing'
            Add-Result ($null -ne $status.capabilities_verified) 'probe/execution/capabilities' 'capabilities_verified missing'
            Add-Result ($null -ne $status.probe_timestamp_utc) 'probe/execution/timestamp' 'timestamp missing'

            if ($status.status -eq 'BLOCKED') {
                Add-Result ($null -ne $status.blocker) 'probe/execution/blocker' 'BLOCKED status must have blocker'
                if ($null -ne $status.blocker) {
                    Add-Result ($null -ne $status.blocker.code) 'probe/execution/blocker-code' 'blocker code missing'
                    Add-Result ($null -ne $status.blocker.message) 'probe/execution/blocker-message' 'blocker message missing'
                }
            }

            $statusJson = $status | ConvertTo-Json -Depth 10
            $credentialPattern = '(api[_-]?key|token|secret|password).*[:=]\s*[a-zA-Z0-9+/]{10,}'
            Add-Result ($statusJson -notmatch $credentialPattern) 'probe/execution/no-credentials' 'probe output may contain credentials'

            Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue
        }
    } catch {
        [void]$failures.Add("probe/execution/crash: $($_.Exception.Message)")
    }
}

$contractJson = $contract | ConvertTo-Json -Depth 10 -Compress
foreach ($evaluative in @('useful','first_green','after_fixed_point','correct','effectiveness')) {
    Add-Result ($contractJson -notmatch $evaluative) "contract/no-evaluative/$evaluative" "contract should not contain evaluative field: $evaluative"
}

$newConfigScript = Join-Path $adapterDir 'New-P67AdapterConfig.ps1'
$invokeScript = Join-Path $adapterDir 'Invoke-P67OpenCodeAdapter.ps1'
$normalizerModule = Join-Path $adapterDir 'ConvertTo-NeutralCapture.psm1'

Add-Result (Test-Path -LiteralPath $newConfigScript -PathType Leaf) 'adp02/new-config-exists' 'New-P67AdapterConfig.ps1 missing'
Add-Result (Test-Path -LiteralPath $invokeScript -PathType Leaf) 'adp02/invoke-exists' 'Invoke-P67OpenCodeAdapter.ps1 missing'
Add-Result (Test-Path -LiteralPath $normalizerModule -PathType Leaf) 'adp02/normalizer-exists' 'ConvertTo-NeutralCapture.psm1 missing'

if (Test-Path -LiteralPath $newConfigScript -PathType Leaf) {
    $configContent = Get-Content -LiteralPath $newConfigScript -Raw

    Add-Result ($configContent -match 'ADP-02') 'adp02/new-config/adp-marker' 'config script does not reference ADP-02'
    Add-Result ($configContent -match 'compute-authority-agent-adapter/v1') 'adp02/new-config/schema' 'config script does not reference correct schema'
    Add-Result ($configContent -match 'Invoke-P67OpenCodeAdapter\.ps1') 'adp02/new-config/invoke-ref' 'config script does not reference Invoke script'
    Add-Result ($configContent -notmatch 'api[_-]?key.*[:=]\s*[a-zA-Z0-9]{10,}') 'adp02/new-config/no-credential-values' 'config script may contain credential values'
}

if (Test-Path -LiteralPath $invokeScript -PathType Leaf) {
    $invokeContent = Get-Content -LiteralPath $invokeScript -Raw

    Add-Result ($invokeContent -match 'ADP-02') 'adp02/invoke/adp-marker' 'invoke script does not reference ADP-02'
    Add-Result ($invokeContent -match '\[Parameter\(Mandatory\)\]') 'adp02/invoke/mandatory-params' 'invoke script missing mandatory parameters'
    Add-Result ($invokeContent -match '\$Workspace') 'adp02/invoke/workspace-param' 'invoke script missing Workspace parameter'
    Add-Result ($invokeContent -match '\$Task') 'adp02/invoke/task-param' 'invoke script missing Task parameter'
    Add-Result ($invokeContent -match '\$Prompt') 'adp02/invoke/prompt-param' 'invoke script missing Prompt parameter'
    Add-Result ($invokeContent -match '\$Result') 'adp02/invoke/result-param' 'invoke script missing Result parameter'

    Add-Result ($invokeContent -notmatch 'Invoke-Expression|iex') 'adp02/invoke/no-shell-composition' 'invoke script contains shell composition'

    Add-Result ($invokeContent -match 'INVALID') 'adp02/invoke/invalid-status' 'invoke script does not emit INVALID status'
    Add-Result ($invokeContent -match 'timeout') 'adp02/invoke/timeout-handling' 'invoke script does not handle timeouts'
    Add-Result ($invokeContent -match 'CAPTURE_EVALUATIVE_REJECTED') 'adp02/invoke/evaluative-check' 'invoke script does not check for evaluative fields'

    Add-Result ($invokeContent -match 'compute-authority-provider-capture/v2') 'adp02/invoke/capture-schema' 'invoke script does not reference capture contract v2'

    Add-Result ($invokeContent -notmatch 'raw_transcript|full_conversation|model_text.*Set-Content') 'adp02/invoke/no-raw-persistence' 'invoke script may persist raw provider output'
}

if (Test-Path -LiteralPath $normalizerModule -PathType Leaf) {
    $normalizerContent = Get-Content -LiteralPath $normalizerModule -Raw

    Add-Result ($normalizerContent -match 'ADP-02') 'adp02/normalizer/adp-marker' 'normalizer does not reference ADP-02'
    Add-Result ($normalizerContent -match 'CAPTURE_EVALUATIVE_REJECTED') 'adp02/normalizer/evaluative-rule' 'normalizer does not reference evaluative rejection rule'

    Add-Result ($normalizerContent -match 'Test-CaptureFieldAllowed') 'adp02/normalizer/field-allowed-func' 'normalizer missing Test-CaptureFieldAllowed'
    Add-Result ($normalizerContent -match 'Test-CaptureObjectValid') 'adp02/normalizer/object-valid-func' 'normalizer missing Test-CaptureObjectValid'

    Add-Result ($normalizerContent -match 'ForbiddenEvaluativeFields') 'adp02/normalizer/evaluative-list' 'normalizer missing evaluative fields list'
    Add-Result ($normalizerContent -match 'ForbiddenPrivacyFields') 'adp02/normalizer/privacy-list' 'normalizer missing privacy fields list'
    Add-Result ($normalizerContent -match 'ForbiddenCredentialFields') 'adp02/normalizer/credential-list' 'normalizer missing credential fields list'

    foreach ($evaluative in @('useful','first_green','after_fixed_point','correct','effectiveness')) {
        Add-Result ($normalizerContent -match $evaluative) "adp02/normalizer/evaluative/$evaluative" "normalizer missing evaluative field: $evaluative"
    }

    foreach ($privacy in @('raw_prompt','raw_response','transcript','full_conversation')) {
        Add-Result ($normalizerContent -match $privacy) "adp02/normalizer/privacy/$privacy" "normalizer missing privacy field: $privacy"
    }

    Add-Result ($normalizerContent -match 'compute-authority-provider-capture/v2') 'adp02/normalizer/capture-schema' 'normalizer does not reference capture contract v2'
}

$adp03FixturesDir = Join-Path $adapterDir 'fixtures/adp03'
$syntheticInteropScript = Join-Path $RootPath 'scripts/Invoke-P67OpenCodeAdapterSyntheticInterop.ps1'

Add-Result (Test-Path -LiteralPath $adp03FixturesDir -PathType Container) 'adp03/fixtures-dir-exists' 'ADP-03 fixtures directory missing'
Add-Result (Test-Path -LiteralPath $syntheticInteropScript -PathType Leaf) 'adp03/runner-exists' 'ADP-03 synthetic interop runner missing'

if (Test-Path -LiteralPath $adp03FixturesDir -PathType Container) {
    $requiredFixtures = @(
        'synthetic-01-happy-path-valid.json',
        'synthetic-02-validation-nonzero.json',
        'synthetic-03-timeout-fail-closed.json',
        'synthetic-04-missing-result-fail-closed.json',
        'synthetic-05-parallel-subagent-lane.json',
        'synthetic-06-privacy-rejected.json',
        'synthetic-07-evaluative-rejected.json',
        'synthetic-08-invalid-workspace.json'
    )

    foreach ($fixtureName in $requiredFixtures) {
        $fixturePath = Join-Path $adp03FixturesDir $fixtureName
        Add-Result (Test-Path -LiteralPath $fixturePath -PathType Leaf) "adp03/fixture/$fixtureName" "fixture missing"

        if (Test-Path -LiteralPath $fixturePath -PathType Leaf) {
            try {
                $fixture = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json
                Add-Result ($fixture.schema_version -eq 'compute-authority-provider-capture/v2') "adp03/fixture/$fixtureName/schema" 'incorrect schema version'
                Add-Result ($fixture.run_status -in @('VALID','INVALID')) "adp03/fixture/$fixtureName/status" 'invalid run_status'
                Add-Result ($null -ne $fixture.provider_identity) "adp03/fixture/$fixtureName/identity" 'provider_identity missing'
                Add-Result ($null -ne $fixture.task_id) "adp03/fixture/$fixtureName/task-id" 'task_id missing'
                Add-Result ($fixture.task_id -match 'SYNTHETIC') "adp03/fixture/$fixtureName/synthetic-marker" 'fixture must have SYNTHETIC marker'
            } catch {
                [void]$failures.Add("adp03/fixture/$fixtureName/parse-error: $($_.Exception.Message)")
            }
        }
    }
}

if (Test-Path -LiteralPath $syntheticInteropScript -PathType Leaf) {
    $runnerContent = Get-Content -LiteralPath $syntheticInteropScript -Raw

    Add-Result ($runnerContent -match 'ADP-03') 'adp03/runner/adp-marker' 'runner does not reference ADP-03'
    Add-Result ($runnerContent -match 'synthetic interoperability') 'adp03/runner/interop-claim' 'runner does not claim synthetic interoperability'
    Add-Result ($runnerContent -match 'no live OpenCode') 'adp03/runner/no-live-provider' 'runner does not document no-live-provider constraint'
    Add-Result ($runnerContent -match 'asb-p67-adp03-synthetic-interop-receipt') 'adp03/runner/receipt-schema' 'runner does not define receipt schema'
    Add-Result ($runnerContent -match 'SYNTHETIC_INTEROPERABILITY') 'adp03/runner/proof-level' 'runner does not declare SYNTHETIC_INTEROPERABILITY proof level'

    try {
        $tempReceipt = [System.IO.Path]::GetTempFileName()
        $runnerResult = & pwsh -NoLogo -NoProfile -File $syntheticInteropScript -OutputPath $tempReceipt -ErrorAction Stop
        $runnerExitCode = $LASTEXITCODE

        Add-Result ($runnerExitCode -eq 0) 'adp03/runner/execution/exit-code' "runner exited with non-zero code: $runnerExitCode"

        if (Test-Path -LiteralPath $tempReceipt -PathType Leaf) {
            $receipt = Get-Content -LiteralPath $tempReceipt -Raw | ConvertFrom-Json

            Add-Result ($receipt.schema_version -match 'asb-p67-adp03-synthetic-interop-receipt') 'adp03/runner/execution/receipt-schema' 'receipt has incorrect schema'
            Add-Result ($null -ne $receipt.test_run_summary) 'adp03/runner/execution/summary' 'receipt missing test_run_summary'
            Add-Result ($receipt.proof_level -eq 'SYNTHETIC_INTEROPERABILITY') 'adp03/runner/execution/proof-level' 'receipt has incorrect proof level'
            Add-Result ($null -ne $receipt.adp03_paths_covered) 'adp03/runner/execution/paths-covered' 'receipt missing adp03_paths_covered'

            if ($null -ne $receipt.adp03_paths_covered) {
                $pathsCovered = @($receipt.adp03_paths_covered)
                Add-Result ($pathsCovered -contains 'happy_path_valid_capture_v2') 'adp03/runner/execution/path/happy' 'happy path not covered'
                Add-Result ($pathsCovered -contains 'timeout_fail_closed') 'adp03/runner/execution/path/timeout' 'timeout path not covered'
                Add-Result ($pathsCovered -contains 'privacy_rejection') 'adp03/runner/execution/path/privacy' 'privacy path not covered'
                Add-Result ($pathsCovered -contains 'evaluative_rejection') 'adp03/runner/execution/path/evaluative' 'evaluative path not covered'
            }

            if ($null -ne $receipt.test_run_summary) {
                Add-Result ($receipt.test_run_summary.total_tests -ge 8) 'adp03/runner/execution/test-count' 'insufficient test coverage (expected >= 8)'
                Add-Result ($receipt.test_run_summary.success -eq $true) 'adp03/runner/execution/success' 'synthetic interop tests did not pass'
            }

            Remove-Item -LiteralPath $tempReceipt -Force -ErrorAction SilentlyContinue
        }
    } catch {
        [void]$failures.Add("adp03/runner/execution/crash: $($_.Exception.Message)")
    }
}

Write-Host "`nP67 OpenCode Adapter (ADP-01 + ADP-02 + ADP-03) Contract Tests" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Passes: $($passes.Count)" -ForegroundColor Green
if ($failures.Count -gt 0) {
    Write-Host "Failures: $($failures.Count)" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
} else {
    Write-Host "All tests passed!" -ForegroundColor Green
}

exit $(if ($failures.Count -eq 0) { 0 } else { 1 })
