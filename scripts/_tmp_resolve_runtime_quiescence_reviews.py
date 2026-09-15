from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASQ = ROOT / "Invoke-Asq017AdminBoxLiveFloor.ps1"
TEST = ROOT / "tests" / "test_firstmate_windows_wsl_prerequisite_gate.py"
RUNBOOK = ROOT / "docs" / "harness" / "firstmate-wsl-physical-floor-runbook.md"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


asq = ASQ.read_text(encoding="utf-8")
sha_fn = r'''function Get-Asq017Sha256Text {
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
'''
helpers = sha_fn + r'''
function Get-Asq017PathIdentity {
    param(
        [AllowNull()][AllowEmptyString()][string]$PathValue,
        [Parameter(Mandatory)][string]$DefaultMarker
    )
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $DefaultMarker }
    $resolved = [System.IO.Path]::GetFullPath($PathValue)
    if ($IsWindows) { return $resolved.ToLowerInvariant() }
    return $resolved
}

function Get-Asq017WslEnvironmentSignature {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($null -eq $wsl) { return 'wsl=missing' }

    # The signature is a cheap capability discriminator, not a second physical proof.
    # A timeout/launch error is UNKNOWN so quiescence fails open to the real child.
    $probeTimeoutSeconds = [Math]::Max(3, [Math]::Min(15, $PrerequisiteTimeoutSeconds))
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $wsl.Source
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        foreach ($argument in @('--distribution', $WslDistribution, '--exec', 'true')) {
            [void]$psi.ArgumentList.Add([string]$argument)
        }
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        if (-not $process.Start()) { return $null }
        $completed = $process.WaitForExit($probeTimeoutSeconds * 1000)
        if (-not $completed) {
            try {
                $process.Kill($true)
                [void]$process.WaitForExit(5000)
            }
            catch {}
            return $null
        }
        if ($process.ExitCode -eq 0) { return 'wsl=runnable' }
        return ('wsl=blocked;exit={0}' -f $process.ExitCode)
    }
    catch {
        return $null
    }
}
'''
asq = replace_once(asq, sha_fn, helpers, "path/environment helpers")

start = asq.index("function Get-Asq017ProofRelevanceFingerprint {")
end = asq.index("\nfunction Get-Asq017QuiescenceStatePath {", start)
old_fp = asq[start:end]
new_fp = r'''function Get-Asq017ProofRelevanceFingerprint {
    param([AllowNull()][AllowEmptyString()][string]$WslEnvironmentSignature)
    # HEAD itself is deliberately excluded. Only behavior/proof inputs belong here,
    # so documentation/ledger/tip-cite movement cannot reopen an unchanged proof.
    try {
        if ([string]::IsNullOrWhiteSpace($WslEnvironmentSignature)) { return $null }
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
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $null }
            $normalized = $relativePath.Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            [void]$entries.Add(('{0}={1}' -f $normalized, $hash))
        }
        [void]$entries.Add(('wslDistribution={0}' -f $WslDistribution))
        [void]$entries.Add(('wslEnvironmentSignature={0}' -f $WslEnvironmentSignature))
        [void]$entries.Add(('prerequisiteTimeoutSeconds={0}' -f $PrerequisiteTimeoutSeconds))
        [void]$entries.Add(('skipProtectedControl={0}' -f [bool]$SkipProtectedControl))
        $firstMateSelector = Get-Asq017PathIdentity -PathValue $FirstMatePath -DefaultMarker '<default>'
        [void]$entries.Add(('firstMatePathSelectorSha256={0}' -f (Get-Asq017Sha256Text -Text $firstMateSelector)))
        $evidenceSelector = Get-Asq017PathIdentity -PathValue $EvidenceRoot -DefaultMarker '<default>'
        [void]$entries.Add(('evidenceRootSelectorSha256={0}' -f (Get-Asq017Sha256Text -Text $evidenceSelector)))
        return Get-Asq017Sha256Text -Text ($entries -join "`n")
    }
    catch {
        # Unknown proof relevance must never become a false stop signal. Allow one
        # fresh bounded attempt and report the fingerprint as UNKNOWN instead.
        return $null
    }
}
'''
asq = asq[:start] + new_fp + asq[end:]

asq = replace_once(
    asq,
    "$rootIdentity = [System.IO.Path]::GetFullPath($Root).ToLowerInvariant()\n    $rootKey = (Get-Asq017Sha256Text -Text $rootIdentity).Substring(0, 16)",
    "$rootIdentity = [System.IO.Path]::GetFullPath($Root)\n    if ($IsWindows) { $rootIdentity = $rootIdentity.ToLowerInvariant() }\n    $rootKey = (Get-Asq017Sha256Text -Text $rootIdentity).Substring(0, 16)",
    "root case identity",
)

old_write_fragment = r'''        $state = [ordered]@{
            schema = 'asb-quiescence-state/v1'
            lane = 'FM-WSL-12'
            blockerStatus = $BlockerStatus
            proofRelevanceFingerprint = $Fingerprint
            observedHead = $ObservedHead
            observedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        }
        $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding utf8
        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'recorded'
        return $true
'''
new_write_fragment = r'''        $state = [ordered]@{
            schema = 'asb-quiescence-state/v1'
            lane = 'FM-WSL-12'
            blockerStatus = $BlockerStatus
            proofRelevanceFingerprint = $Fingerprint
            observedHead = $ObservedHead
            observedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        }
        $tempPath = Join-Path $parent ('.' + [System.IO.Path]::GetFileName($path) + '.' + [guid]::NewGuid().ToString('n') + '.tmp')
        try {
            $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $tempPath -Encoding utf8
            # Same-directory replace prevents readers from observing a truncated JSON file.
            [System.IO.File]::Move($tempPath, $path, $true)
        }
        finally {
            if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'recorded'
        return $true
'''
asq = replace_once(asq, old_write_fragment, new_write_fragment, "atomic state write")

old_pre = r'''$proofRelevanceFingerprint = Get-Asq017ProofRelevanceFingerprint
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
'''
new_pre = r'''$wslEnvironmentSignature = Get-Asq017WslEnvironmentSignature
if ([string]::IsNullOrWhiteSpace($wslEnvironmentSignature)) {
    Write-Asq017Status -Key 'WSL_ENVIRONMENT_SIGNATURE' -Value 'UNKNOWN'
}
else {
    Write-Asq017Status -Key 'WSL_ENVIRONMENT_SIGNATURE' -Value $wslEnvironmentSignature
}
$proofRelevanceFingerprint = Get-Asq017ProofRelevanceFingerprint -WslEnvironmentSignature $wslEnvironmentSignature
if ([string]::IsNullOrWhiteSpace($proofRelevanceFingerprint)) {
    Write-Asq017Status -Key 'PROOF_RELEVANCE_FINGERPRINT' -Value 'UNKNOWN'
}
else {
    Write-Asq017Status -Key 'PROOF_RELEVANCE_FINGERPRINT' -Value $proofRelevanceFingerprint
}

# Runtime circuit breaker: a second identical environment blocker is not a new
# evidence pass. The environment signature lets an installed/repaired WSL floor
# change the fingerprint and reopen the real child; UNKNOWN always fails open.
if (-not [string]::IsNullOrWhiteSpace($proofRelevanceFingerprint)) {
'''
asq = replace_once(asq, old_pre, new_pre, "environment-aware precheck")
ASQ.write_text(asq, encoding="utf-8")


test = TEST.read_text(encoding="utf-8")
test = replace_once(
    test,
    '            "wslDistribution=",\n            "prerequisiteTimeoutSeconds=",\n            "skipProtectedControl=",\n            "firstMatePathSelectorSha256=",\n',
    '            "wslDistribution=",\n            "wslEnvironmentSignature=",\n            "prerequisiteTimeoutSeconds=",\n            "skipProtectedControl=",\n            "firstMatePathSelectorSha256=",\n            "evidenceRootSelectorSha256=",\n',
    "expanded fingerprint assertions",
)
test = replace_once(
    test,
    '        self.assertIn("Get-Asq017ProofRelevanceFingerprint", asq)\n        self.assertIn("Get-FileHash", asq)\n',
    '        self.assertIn("Get-Asq017ProofRelevanceFingerprint", asq)\n        self.assertIn("Get-Asq017WslEnvironmentSignature", asq)\n        self.assertIn("Get-Asq017PathIdentity", asq)\n        self.assertIn("Get-FileHash", asq)\n        self.assertIn("if ($IsWindows)", asq)\n',
    "environment/path assertions",
)
test = replace_once(
    test,
    '        self.assertIn("return $false", asq)\n',
    '        self.assertIn("return $false", asq)\n        self.assertIn("[System.IO.File]::Move($tempPath, $path, $true)", asq)\n',
    "atomic write assertion",
)
TEST.write_text(test, encoding="utf-8")


runbook = RUNBOOK.read_text(encoding="utf-8")
runbook = replace_once(
    runbook,
    "- `PROOF_RELEVANCE_FINGERPRINT=<sha256>` from the ASQ-017 front door.\n",
    "- `WSL_ENVIRONMENT_SIGNATURE=...` and `PROOF_RELEVANCE_FINGERPRINT=<sha256>` from the ASQ-017 front door.\n",
    "runbook environment marker",
)
runbook = replace_once(
    runbook,
    "move the proof to the Admin Box or change a proof-relevant input; do not create a tip-cite/ledger update merely to make repository HEAD newer.",
    "move the proof to the Admin Box or change a proof-relevant input/environment. Explicit `-EvidenceRoot` and `-FirstMatePath` selectors participate by hashed identity, and WSL command/distribution capability participates through `WSL_ENVIRONMENT_SIGNATURE`; do not create a tip-cite/ledger update merely to make repository HEAD newer.",
    "runbook fingerprint inputs",
)
RUNBOOK.write_text(runbook, encoding="utf-8")
print("resolved runtime quiescence review gaps")
