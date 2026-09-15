from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASQ = ROOT / "Invoke-Asq017AdminBoxLiveFloor.ps1"
TEST = ROOT / "tests" / "test_firstmate_windows_wsl_prerequisite_gate.py"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


asq = ASQ.read_text(encoding="utf-8")

asq = replace_once(
    asq,
    "    [switch]$SkipProtectedControl,\n    [switch]$SkipGitRefresh,\n    [switch]$ContractOnly\n)",
    "    [switch]$SkipProtectedControl,\n    [switch]$SkipGitRefresh,\n    [string]$QuiescenceStatePath,\n    [switch]$ContractOnly\n)",
    "parameter seam",
)

status_fn = """function Write-Asq017Status {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)
    Write-Host ('{0}={1}' -f $Key, $Value)
}
"""

quiescence_fns = r'''function Write-Asq017Status {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)
    Write-Host ('{0}={1}' -f $Key, $Value)
}

function Get-Asq017Sha256Text {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($sha.ComputeHash($bytes))).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Asq017ProofRelevanceFingerprint {
    # HEAD itself is deliberately excluded. Only behavior/proof inputs belong here,
    # so documentation/ledger/tip-cite movement cannot reopen an unchanged proof.
    $relativePaths = @(
        'Invoke-Asq017AdminBoxLiveFloor.ps1',
        'Invoke-FmWsl12AdminBoxLiveProof.ps1',
        'Invoke-FirstMatePhysicalFloorContinuation.ps1',
        'Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1',
        'Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1',
        'tooling\firstmate\harness\integration-contract.json',
        'tooling\firstmate\harness\upstream-pin.json'
    )
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in $relativePaths) {
        $fullPath = Join-Path $Root $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            return $null
        }
        $normalized = $relativePath.Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        [void]$entries.Add(('{0}={1}' -f $normalized, $hash))
    }
    [void]$entries.Add(('wslDistribution={0}' -f $WslDistribution))
    [void]$entries.Add(('prerequisiteTimeoutSeconds={0}' -f $PrerequisiteTimeoutSeconds))
    [void]$entries.Add(('skipProtectedControl={0}' -f [bool]$SkipProtectedControl))
    return Get-Asq017Sha256Text -Text ($entries -join "`n")
}

function Get-Asq017QuiescenceStatePath {
    if (-not [string]::IsNullOrWhiteSpace($QuiescenceStatePath)) {
        return [System.IO.Path]::GetFullPath($QuiescenceStatePath)
    }
    $rootIdentity = [System.IO.Path]::GetFullPath($Root).ToLowerInvariant()
    $rootKey = (Get-Asq017Sha256Text -Text $rootIdentity).Substring(0, 16)
    $directory = Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard\quiescence'
    return Join-Path $directory ("fm-wsl12-asq017-$rootKey.json")
}

function Read-Asq017QuiescenceState {
    $path = Get-Asq017QuiescenceStatePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ([string]$state.schema -ne 'asb-quiescence-state/v1') { return $null }
        if ([string]$state.lane -ne 'FM-WSL-12') { return $null }
        return $state
    }
    catch {
        # Corrupt/foreign local state cannot be trusted as a stop signal; fail open to
        # a fresh bounded proof attempt instead of manufacturing a quiescence claim.
        return $null
    }
}

function Write-Asq017QuiescenceState {
    param(
        [Parameter(Mandatory)][string]$BlockerStatus,
        [Parameter(Mandatory)][string]$Fingerprint,
        [Parameter(Mandatory)][string]$ObservedHead
    )
    $path = Get-Asq017QuiescenceStatePath
    $parent = Split-Path -Parent $path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $state = [ordered]@{
        schema = 'asb-quiescence-state/v1'
        lane = 'FM-WSL-12'
        blockerStatus = $BlockerStatus
        proofRelevanceFingerprint = $Fingerprint
        observedHead = $ObservedHead
        observedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding utf8
}

function Clear-Asq017QuiescenceState {
    $path = Get-Asq017QuiescenceStatePath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Remove-Item -LiteralPath $path -Force
    }
}
'''
asq = replace_once(asq, status_fn, quiescence_fns, "quiescence helpers")

pre_launch = """Write-Asq017Status -Key 'PHYSICAL_FLOOR_HEAD' -Value $head
Write-Asq017Status -Key 'WSL_DISTRIBUTION' -Value $WslDistribution
Write-Asq017Status -Key 'ASQ017_ONESHOT' -Value $OneShotPath
Write-Asq017Status -Key 'LIVE_RUNTIME_PROOF' -Value 'UNPROVEN'

$argumentList = @(
"""

pre_launch_guard = r'''Write-Asq017Status -Key 'PHYSICAL_FLOOR_HEAD' -Value $head
Write-Asq017Status -Key 'WSL_DISTRIBUTION' -Value $WslDistribution
Write-Asq017Status -Key 'ASQ017_ONESHOT' -Value $OneShotPath
Write-Asq017Status -Key 'LIVE_RUNTIME_PROOF' -Value 'UNPROVEN'

$proofRelevanceFingerprint = Get-Asq017ProofRelevanceFingerprint
if ([string]::IsNullOrWhiteSpace($proofRelevanceFingerprint)) {
    Write-Asq017Status -Key 'PROOF_RELEVANCE_FINGERPRINT' -Value 'UNKNOWN'
}
else {
    Write-Asq017Status -Key 'PROOF_RELEVANCE_FINGERPRINT' -Value $proofRelevanceFingerprint
}

# Runtime circuit breaker: a second identical environment blocker is not a new
# evidence pass. HEAD movement is intentionally irrelevant unless one of the
# proof-relevant files/inputs above changed.
if ($null -eq (Get-Command wsl.exe -ErrorAction SilentlyContinue) -and
    -not [string]::IsNullOrWhiteSpace($proofRelevanceFingerprint)) {
    $priorQuiescence = Read-Asq017QuiescenceState
    if ($null -ne $priorQuiescence -and
        [string]$priorQuiescence.blockerStatus -eq 'BLOCKED_WINDOWS_WSL_REQUIRED' -and
        [string]$priorQuiescence.proofRelevanceFingerprint -eq $proofRelevanceFingerprint) {
        Write-Host 'STATUS=QUIESCENT_BLOCKED'
        Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'QUIESCENT_BLOCKED'
        Write-Asq017Status -Key 'BLOCKER_STATUS' -Value 'BLOCKED_WINDOWS_WSL_REQUIRED'
        Write-Asq017Status -Key 'PROGRESS_BEARING' -Value 'false'
        Write-Asq017Status -Key 'RETRY_ELIGIBLE' -Value 'false'
        Write-Asq017Status -Key 'QUIESCENCE_REASON' -Value 'REPEATED_UNCHANGED_EXTERNAL_BLOCKER'
        Write-Asq017Status -Key 'PROOF_LEVEL' -Value 'LIVE_ATTEMPT_FAIL_CLOSED'
        Write-Asq017Status -Key 'LIVE_RUNTIME_PROOF' -Value 'UNPROVEN'
        Write-Asq017Status -Key 'CHILD_EXIT_CODE' -Value '46'
        Write-Asq017Status -Key 'NEXT' -Value 'run on a Windows Admin Box with wsl.exe+Ubuntu, or change a proof-relevant runtime input; do not rerun this cloud/non-Windows proof or create citation-only/tip-cite updates while the fingerprint is unchanged'
        exit 46
    }
}

$argumentList = @(
'''
asq = replace_once(asq, pre_launch, pre_launch_guard, "pre-launch guard")

child_seam = """$childExit = [int]$oneshotProcess.ExitCode
Write-Asq017Status -Key 'CHILD_EXIT_CODE' -Value \"$childExit\"

$oneshotBlob = ''
"""

child_state = r'''$childExit = [int]$oneshotProcess.ExitCode
Write-Asq017Status -Key 'CHILD_EXIT_CODE' -Value "$childExit"

if ($childExit -eq 46 -and -not [string]::IsNullOrWhiteSpace($proofRelevanceFingerprint)) {
    Write-Asq017QuiescenceState -BlockerStatus 'BLOCKED_WINDOWS_WSL_REQUIRED' -Fingerprint $proofRelevanceFingerprint -ObservedHead $head
    Write-Asq017Status -Key 'QUIESCENCE_ON_REPEAT' -Value 'true'
}
else {
    # The old environment blocker is no longer the current outcome. Clear it so a
    # changed environment/behavior is never suppressed by stale local state.
    Clear-Asq017QuiescenceState
}

$oneshotBlob = ''
'''
asq = replace_once(asq, child_seam, child_state, "child state persistence")

ASQ.write_text(asq, encoding="utf-8")


test = TEST.read_text(encoding="utf-8")
anchor = """    def test_physical_floor_preserves_structured_prerequisite_exit_codes(self) -> None:
"""
new_test = r'''    def test_asq017_quiesces_repeated_unchanged_environment_blocker(self) -> None:
        asq = (ROOT / "Invoke-Asq017AdminBoxLiveFloor.ps1").read_text(encoding="utf-8")
        # Quiescence is runtime behavior, not a HEAD/tip citation heuristic.
        self.assertIn("Get-Asq017ProofRelevanceFingerprint", asq)
        self.assertIn("Get-FileHash", asq)
        self.assertIn("PROOF_RELEVANCE_FINGERPRINT", asq)
        for proof_input in (
            "Invoke-FmWsl12AdminBoxLiveProof.ps1",
            "Invoke-FirstMatePhysicalFloorContinuation.ps1",
            "Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1",
            "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1",
            "integration-contract.json",
            "upstream-pin.json",
            "wslDistribution=",
            "prerequisiteTimeoutSeconds=",
            "skipProtectedControl=",
        ):
            self.assertIn(proof_input, asq)
        self.assertIn("asb-quiescence-state/v1", asq)
        self.assertIn("[System.IO.Path]::GetTempPath()", asq)
        self.assertIn("BLOCKED_WINDOWS_WSL_REQUIRED", asq)
        self.assertIn("STATUS=QUIESCENT_BLOCKED", asq)
        self.assertIn("ASQ017_RESULT", asq)
        self.assertIn("QUIESCENCE_REASON", asq)
        self.assertIn("REPEATED_UNCHANGED_EXTERNAL_BLOCKER", asq)
        self.assertIn("PROGRESS_BEARING", asq)
        self.assertIn("RETRY_ELIGIBLE", asq)
        self.assertIn("Write-Asq017QuiescenceState", asq)
        self.assertIn("Clear-Asq017QuiescenceState", asq)
        self.assertIn("QUIESCENCE_ON_REPEAT", asq)
        self.assertIn("do not rerun this cloud/non-Windows proof or create citation-only/tip-cite updates", asq)
        # The stored HEAD is provenance only; fingerprint construction explicitly excludes HEAD.
        self.assertIn("HEAD itself is deliberately excluded", asq)
        self.assertIn("observedHead", asq)
        # Unknown/corrupt state must never suppress a fresh bounded attempt.
        self.assertIn("fail open to", asq)

    def test_physical_floor_preserves_structured_prerequisite_exit_codes(self) -> None:
'''
test = replace_once(test, anchor, new_test, "focused test insertion")
TEST.write_text(test, encoding="utf-8")

print("patched runtime quiescence guard")
