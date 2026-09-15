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
old_fp = r'''function Get-Asq017ProofRelevanceFingerprint {
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
    $firstMateSelector = if ([string]::IsNullOrWhiteSpace($FirstMatePath)) { '<default>' } else { [System.IO.Path]::GetFullPath($FirstMatePath).ToLowerInvariant() }
    [void]$entries.Add(('firstMatePathSelectorSha256={0}' -f (Get-Asq017Sha256Text -Text $firstMateSelector)))
    return Get-Asq017Sha256Text -Text ($entries -join "`n")
}
'''
new_fp = r'''function Get-Asq017ProofRelevanceFingerprint {
    # HEAD itself is deliberately excluded. Only behavior/proof inputs belong here,
    # so documentation/ledger/tip-cite movement cannot reopen an unchanged proof.
    try {
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
        $firstMateSelector = if ([string]::IsNullOrWhiteSpace($FirstMatePath)) { '<default>' } else { [System.IO.Path]::GetFullPath($FirstMatePath).ToLowerInvariant() }
        [void]$entries.Add(('firstMatePathSelectorSha256={0}' -f (Get-Asq017Sha256Text -Text $firstMateSelector)))
        return Get-Asq017Sha256Text -Text ($entries -join "`n")
    }
    catch {
        # Unknown proof relevance must never become a false stop signal. Allow one
        # fresh bounded attempt and report the fingerprint as UNKNOWN instead.
        return $null
    }
}
'''
asq = replace_once(asq, old_fp, new_fp, "fingerprint fail-open")
old_read = r'''function Read-Asq017QuiescenceState {
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
'''
new_read = r'''function Read-Asq017QuiescenceState {
    try {
        $path = Get-Asq017QuiescenceStatePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
        $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ([string]$state.schema -ne 'asb-quiescence-state/v1') { return $null }
        if ([string]$state.lane -ne 'FM-WSL-12') { return $null }
        return $state
    }
    catch {
        # Corrupt/foreign/unresolvable local state cannot be trusted as a stop signal;
        # fail open to a fresh bounded proof attempt instead of manufacturing quiescence.
        return $null
    }
}
'''
asq = replace_once(asq, old_read, new_read, "state read fail-open")
ASQ.write_text(asq, encoding="utf-8")


test = TEST.read_text(encoding="utf-8")
test = replace_once(
    test,
    '        self.assertIn("fail open to", asq)\n        # Advisory cache persistence/cleanup must not replace the primary blocker.\n',
    '        self.assertIn("fail open to", asq)\n        self.assertIn("Unknown proof relevance must never become a false stop signal", asq)\n        self.assertIn("Corrupt/foreign/unresolvable local state", asq)\n        # Advisory cache persistence/cleanup must not replace the primary blocker.\n',
    "fail-open static assertions",
)
test = replace_once(
    test,
    '        self.assertIn("BLOCKED_WINDOWS_WSL_REQUIRED", self.runbook)\n        self.assertIn("WINDOWS_WSL_REQUIRED", self.runbook)\n',
    '        self.assertIn("BLOCKED_WINDOWS_WSL_REQUIRED", self.runbook)\n        self.assertIn("WINDOWS_WSL_REQUIRED", self.runbook)\n        self.assertIn("QUIESCENT_BLOCKED", self.runbook)\n        self.assertIn("PROOF_RELEVANCE_FINGERPRINT", self.runbook)\n        self.assertIn("PROGRESS_BEARING=false", self.runbook)\n',
    "runbook quiescence assertions",
)
TEST.write_text(test, encoding="utf-8")


runbook = RUNBOOK.read_text(encoding="utf-8")
runbook = replace_once(
    runbook,
    "if ($childExit -eq 45) {\n  throw 'BLOCKED_GITHUB_AUTH — complete gh auth login inside Ubuntu then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'\n}\nif ($childExit -eq 47) {",
    "if ($childExit -eq 45) {\n  throw 'BLOCKED_GITHUB_AUTH — complete gh auth login inside Ubuntu then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'\n}\nif ($childExit -eq 46) {\n  throw 'BLOCKED_WINDOWS_WSL_REQUIRED / QUIESCENT_BLOCKED — move this proof to a Windows Admin Box with runnable wsl.exe+Ubuntu. Do not rerun an unchanged cloud/non-Windows lane; the same proof-relevance fingerprint is quiescent, not new evidence.'\n}\nif ($childExit -eq 47) {",
    "preferred command exit46",
)
runbook = replace_once(
    runbook,
    "if ($childExit -eq 45) {\n  throw 'BLOCKED_GITHUB_AUTH — complete gh auth login then rerun Invoke-FmWsl12AdminBoxLiveProof.ps1'\n}\nif ($childExit -eq 47) {",
    "if ($childExit -eq 45) {\n  throw 'BLOCKED_GITHUB_AUTH — complete gh auth login then rerun Invoke-FmWsl12AdminBoxLiveProof.ps1'\n}\nif ($childExit -eq 46) {\n  throw 'BLOCKED_WINDOWS_WSL_REQUIRED — this expanded direct form cannot prove the physical floor on cloud/Linux; move to the Windows Admin Box rather than repeating the same proof.'\n}\nif ($childExit -eq 47) {",
    "expanded command exit46",
)
runbook = replace_once(
    runbook,
    "GitHub authentication (exit 45), passwordless apt sudo (exit 47)",
    "GitHub authentication (exit 45), unavailable Windows/WSL environment (exit 46; ASQ-017 records the first fail-closed observation and an unchanged repeat returns `STATUS=QUIESCENT_BLOCKED` without launching another one-shot), passwordless apt sudo (exit 47)",
    "owner paragraph",
)
runbook = replace_once(
    runbook,
    "- `PREREQUISITE_EVIDENCE=...`;\n- `[PROOF_CEILING] Physical WSL interoperability floor only; no live FirstMate crew dispatch is proven.`\n",
    "- `PREREQUISITE_EVIDENCE=...`;\n- `PROOF_RELEVANCE_FINGERPRINT=<sha256>` from the ASQ-017 front door.\n- `[PROOF_CEILING] Physical WSL interoperability floor only; no live FirstMate crew dispatch is proven.`\n\nOn a non-Windows/cloud host, the first exit-46 observation may additionally emit `QUIESCENCE_STATE=recorded` and `QUIESCENCE_ON_REPEAT=true`. A later invocation with the same proof-relevance fingerprint emits `STATUS=QUIESCENT_BLOCKED`, `BLOCKER_STATUS=BLOCKED_WINDOWS_WSL_REQUIRED`, `PROGRESS_BEARING=false`, and `RETRY_ELIGIBLE=false` before another one-shot is launched. That is an intentional stop signal: move the proof to the Admin Box or change a proof-relevant input; do not create a tip-cite/ledger update merely to make repository HEAD newer.\n",
    "marker documentation",
)
runbook = replace_once(
    runbook,
    "| Host lacks `wsl.exe`, or `Ubuntu` is missing/unrunnable (`STATUS=BLOCKED_WINDOWS_WSL_REQUIRED`, exit 46 / `FAILURE_CODE=WINDOWS_WSL_REQUIRED`) | Cloud/Linux hosts without `wsl.exe`, and Windows hosts whose contracted distribution cannot run `wsl --distribution Ubuntu --exec true`, fail closed before package repair or interop. This is a LIVE_ATTEMPT_FAIL_CLOSED receipt, not physical PASS. Move to an authorized Windows Admin Box with explicit runnable `Ubuntu`. |",
    "| Host lacks `wsl.exe`, or `Ubuntu` is missing/unrunnable (`STATUS=BLOCKED_WINDOWS_WSL_REQUIRED`, exit 46 / `FAILURE_CODE=WINDOWS_WSL_REQUIRED`) | Cloud/Linux hosts without `wsl.exe`, and Windows hosts whose contracted distribution cannot run `wsl --distribution Ubuntu --exec true`, fail closed before package repair or interop. This is a LIVE_ATTEMPT_FAIL_CLOSED receipt, not physical PASS. ASQ-017 records the first non-Windows blocker in local untracked state; an unchanged second invocation returns `STATUS=QUIESCENT_BLOCKED` without another child proof. Move to an authorized Windows Admin Box with explicit runnable `Ubuntu`, or change a proof-relevant input; do not rerun the unchanged cloud lane or create citation-only/tip-cite work. |",
    "failure row",
)
RUNBOOK.write_text(runbook, encoding="utf-8")
print("closed quiescence contract gaps")
