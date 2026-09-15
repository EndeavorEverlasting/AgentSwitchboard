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
old_write = r'''function Write-Asq017QuiescenceState {
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
new_write = r'''function Write-Asq017QuiescenceState {
    param(
        [Parameter(Mandatory)][string]$BlockerStatus,
        [Parameter(Mandatory)][string]$Fingerprint,
        [Parameter(Mandatory)][string]$ObservedHead
    )
    try {
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
        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'recorded'
    }
    catch {
        # The cache is advisory. Persistence failure must not replace the real
        # runtime blocker or fabricate a successful quiescence observation.
        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'unavailable'
        Write-Asq017Status -Key 'QUIESCENCE_STATE_OPERATION' -Value 'write'
    }
}

function Clear-Asq017QuiescenceState {
    try {
        $path = Get-Asq017QuiescenceStatePath
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
    catch {
        # Stale cache cleanup is also advisory. The current child result remains
        # authoritative; a cleanup problem cannot replace it.
        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'unavailable'
        Write-Asq017Status -Key 'QUIESCENCE_STATE_OPERATION' -Value 'clear'
    }
}
'''
asq = replace_once(asq, old_write, new_write, "fail-open quiescence persistence")
ASQ.write_text(asq, encoding="utf-8")


test = TEST.read_text(encoding="utf-8")
needle = '''        # Unknown/corrupt state must never suppress a fresh bounded attempt.\n        self.assertIn("fail open to", asq)\n'''
replacement = '''        # Unknown/corrupt state must never suppress a fresh bounded attempt.\n        self.assertIn("fail open to", asq)\n        # Advisory cache persistence/cleanup must not replace the primary blocker.\n        self.assertIn("The cache is advisory", asq)\n        self.assertIn("QUIESCENCE_STATE", asq)\n        self.assertIn("QUIESCENCE_STATE_OPERATION", asq)\n        self.assertIn("'write'", asq)\n        self.assertIn("'clear'", asq)\n'''
test = replace_once(test, needle, replacement, "focused fail-open assertions")
TEST.write_text(test, encoding="utf-8")

print("hardened advisory quiescence cache")
