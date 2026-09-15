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
    "    [void]$entries.Add(('skipProtectedControl={0}' -f [bool]$SkipProtectedControl))\n    return Get-Asq017Sha256Text -Text ($entries -join \"`n\")\n",
    "    [void]$entries.Add(('skipProtectedControl={0}' -f [bool]$SkipProtectedControl))\n    $firstMateSelector = if ([string]::IsNullOrWhiteSpace($FirstMatePath)) { '<default>' } else { [System.IO.Path]::GetFullPath($FirstMatePath).ToLowerInvariant() }\n    [void]$entries.Add(('firstMatePathSelectorSha256={0}' -f (Get-Asq017Sha256Text -Text $firstMateSelector)))\n    return Get-Asq017Sha256Text -Text ($entries -join \"`n\")\n",
    "FirstMate selector fingerprint",
)

asq = replace_once(
    asq,
    "        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'recorded'\n    }\n    catch {\n",
    "        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'recorded'\n        return $true\n    }\n    catch {\n",
    "write success return",
)
asq = replace_once(
    asq,
    "        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'unavailable'\n        Write-Asq017Status -Key 'QUIESCENCE_STATE_OPERATION' -Value 'write'\n    }\n}\n\nfunction Clear-Asq017QuiescenceState",
    "        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'unavailable'\n        Write-Asq017Status -Key 'QUIESCENCE_STATE_OPERATION' -Value 'write'\n        return $false\n    }\n}\n\nfunction Clear-Asq017QuiescenceState",
    "write failure return",
)

old_call = """if ($childExit -eq 46 -and -not [string]::IsNullOrWhiteSpace($proofRelevanceFingerprint)) {
    Write-Asq017QuiescenceState -BlockerStatus 'BLOCKED_WINDOWS_WSL_REQUIRED' -Fingerprint $proofRelevanceFingerprint -ObservedHead $head
    Write-Asq017Status -Key 'QUIESCENCE_ON_REPEAT' -Value 'true'
}
else {
"""
new_call = """if ($childExit -eq 46 -and -not [string]::IsNullOrWhiteSpace($proofRelevanceFingerprint)) {
    $quiescenceRecorded = Write-Asq017QuiescenceState -BlockerStatus 'BLOCKED_WINDOWS_WSL_REQUIRED' -Fingerprint $proofRelevanceFingerprint -ObservedHead $head
    Write-Asq017Status -Key 'QUIESCENCE_ON_REPEAT' -Value $(if ($quiescenceRecorded) { 'true' } else { 'false' })
}
else {
"""
asq = replace_once(asq, old_call, new_call, "conditional repeat eligibility")
ASQ.write_text(asq, encoding="utf-8")


test = TEST.read_text(encoding="utf-8")
test = replace_once(
    test,
    '            "skipProtectedControl=",\n        ):\n',
    '            "skipProtectedControl=",\n            "firstMatePathSelectorSha256=",\n        ):\n',
    "fingerprint selector assertion",
)
test = replace_once(
    test,
    '        self.assertIn("QUIESCENCE_ON_REPEAT", asq)\n',
    '        self.assertIn("QUIESCENCE_ON_REPEAT", asq)\n        self.assertIn("$quiescenceRecorded", asq)\n        self.assertIn("return $true", asq)\n        self.assertIn("return $false", asq)\n',
    "persistence outcome assertions",
)
TEST.write_text(test, encoding="utf-8")
print("finalized runtime quiescence guard")
