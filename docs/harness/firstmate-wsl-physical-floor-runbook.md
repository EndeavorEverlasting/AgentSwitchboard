# FM-WSL-12 — FirstMate physical WSL floor runbook

## Purpose

Execute the prerequisite-gated Windows→Ubuntu/WSL physical floor on an authorized Admin Box after `FM-BRIDGE-10` integration.

This runbook proves **one physical bridge floor**, not live FirstMate crew dispatch.

Architecture authority: [`docs/architecture/asb-firstmate-runtime-boundary.md`](../architecture/asb-firstmate-runtime-boundary.md).
Bridge contract owner: [`docs/harness/firstmate-operational-harness.md`](firstmate-operational-harness.md).

## Proof ceiling

A PASS may claim only:

- explicit Ubuntu selection;
- prerequisite observation (`git`, `gh`, `tmux`, `python3`, GitHub auth);
- WSL-owned standalone exact-head AgentSwitchboard clone;
- read-only FirstMate interoperability probe inside that clone;
- local untracked evidence root.

A PASS must **not** claim:

- native-Windows FirstMate runtime;
- live crew dispatch / supervision;
- provider/model behavior;
- PR/merge/deploy delivery;
- Herdr readiness.

Live crew proof remains `FM-CREW-13`.

## FM-WSL-12 autonomy boundary

`FM-WSL-12` is a physical-environment proof sprint, not a read-only inspection sprint.

When the prerequisite gate emits `STATUS=BLOCKED_MISSING_TOOLS`, the execution owner is authorized to execute the exact emitted Ubuntu `NEXT_ACTION` package command and then rerun the physical floor **without stopping for additional operator permission**.

That repair authority is intentionally bounded:

- distribution: explicit `Ubuntu` only;
- package manager: `apt-get` only;
- package set: only required FirstMate floor tools (`git`, `gh`, `tmux`, `python3`), and only when the gate reports them missing;
- source of truth: the exact `NEXT_ACTION` emitted by the current exact-head prerequisite gate;
- no Windows package-manager mutation;
- no WSL distribution install/removal;
- no arbitrary package additions;
- no FirstMate upstream mutation;
- no credential or authentication mutation.

GitHub authentication is different from package repair. If the gate emits `STATUS=BLOCKED_GITHUB_AUTH`, `gh auth login` remains an operator/user credential gate and must not be automated or have tokens captured in evidence.

The harness itself remains fail-closed and non-installing; this runbook grants the **FM-WSL-12 execution owner** authority to perform the bounded recovery action between attempts and continue the same sprint. That bounded repair is authorized by FM-WSL-12. The durable owner for that loop is `Invoke-FirstMatePhysicalFloorContinuation.ps1` / harness `-Mode physical-floor-continue` (Prompt/P08 continuation authority).

## Preconditions

1. Use an authorized Windows Admin Box with PowerShell 7+ (`pwsh`).
2. Checkout current `main` (post `FM-BRIDGE-10`) and record the exact SHA.
3. Confirm the WSL distribution named `Ubuntu` exists (`wsl.exe -l -v`).
4. Do not change the default WSL distro to satisfy this floor; the harness must target `Ubuntu` explicitly.
5. Keep evidence local/untracked. Do not commit receipts, tokens, or machine-local paths.
6. Treat bounded missing-package repair inside `Ubuntu` as in-scope for this sprint; do not stop merely because the prerequisite gate reports an allowlisted tool missing.

## Exact commands

From a clean AgentSwitchboard checkout on the Admin Box:

```powershell
$ErrorActionPreference = 'Stop'
git fetch --all --prune --tags
if ($LASTEXITCODE -ne 0) { throw "git fetch failed with exit $LASTEXITCODE" }
git switch main
if ($LASTEXITCODE -ne 0) { throw "git switch failed with exit $LASTEXITCODE" }
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw "git pull failed with exit $LASTEXITCODE" }
$headRaw = git rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve HEAD' }
$head = ("$headRaw").Trim()
if ([string]::IsNullOrWhiteSpace($head)) { throw 'Unable to resolve HEAD' }
Write-Host "PHYSICAL_FLOOR_HEAD=$head"

# Preferred FM-WSL-12 Admin Box one-shot (contract → physical-floor-continue → protected control):
# Capture child exit; do not use interactive `exit` (keeps the parent shell open).
# Fail closed on native git nonzero exits before launching the one-shot.
pwsh -NoLogo -NoProfile -File .\Invoke-FmWsl12AdminBoxLiveProof.ps1 `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
$childExit = $LASTEXITCODE
Write-Host "CHILD_EXIT_CODE=$childExit"
if ($childExit -eq 45) {
  throw 'BLOCKED_GITHUB_AUTH — complete gh auth login then rerun Invoke-FmWsl12AdminBoxLiveProof.ps1'
}
if ($childExit -ne 0) {
  throw "FM-WSL-12 Admin Box live proof failed with exit $childExit"
}
```

`Invoke-FmWsl12AdminBoxLiveProof.ps1` is the durable Admin Box live-proof owner for FM-WSL-12. It runs contract, then `physical-floor-continue` (allowlisted apt repair + rerun without another permission round-trip), then report-only `physical-floor` as the protected control. It still stops for GitHub authentication (exit 45) and writes a local untracked receipt under the evidence root. Operator paste commands must print `CHILD_EXIT_CODE` and `throw` on failure rather than calling interactive `exit`.

Equivalent stepped form (same proof ceiling):

```powershell
# Contract front door first (no live WSL requirement beyond ContractOnly surfaces).
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 `
  -Mode contract `
  -ExpectedHead $head `
  -WslDistribution Ubuntu

# FM-WSL-12 / P08 continuation entrypoint:
# missing allowlisted packages -> install exact NEXT_ACTION -> rerun until PASS
# or a non-package blocker (for example BLOCKED_GITHUB_AUTH).
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 `
  -Mode physical-floor-continue `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
```

`physical-floor-continue` remains the durable execution-owner loop for Prompt/P08-class continuation authority. It keeps the physical-floor harness itself non-installing, executes only allowlisted `apt-get` `NEXT_ACTION` values inside explicit `Ubuntu`, and still stops for GitHub authentication or other non-package blockers.

Equivalent direct continuation entrypoint:

```powershell
pwsh -NoLogo -NoProfile -File .\Invoke-FirstMatePhysicalFloorContinuation.ps1 `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
```

If you intentionally want a single non-repairing probe (report-only), use `-Mode physical-floor` instead. When that mode reports `STATUS=BLOCKED_MISSING_TOOLS`, either switch to `physical-floor-continue` or execute the exact emitted `NEXT_ACTION` inside explicit Ubuntu and rerun. For the currently observed `MISSING_TOOLS=gh` case, the emitted recovery is:

```bash
sudo apt-get update && sudo apt-get install -y gh
```

The execution owner should continue immediately after successful package repair. A package-manager failure, unavailable sudo authorization, repository/package-source failure, or credential/authentication requirement is a real blocker and should be reported with the existing evidence root.

Optional direct physical wrapper without continuation (same floor, same proof ceiling, no package repair loop):

```powershell
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1 `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
```

## Pass markers to capture

Preserve the console markers and the printed evidence root:

- `[PASS] FIRSTMATE_WINDOWS_OPERATIONAL_HARNESS` from contract mode;
- `[PASS] FIRSTMATE_WINDOWS_WSL_PHYSICAL_FLOOR` from physical mode, or `[PASS] FIRSTMATE_WINDOWS_WSL_PHYSICAL_FLOOR_CONTINUATION` from continuation mode;
- `HEAD=<40-char sha>`;
- `WSL_DISTRIBUTION=Ubuntu` (and/or bridge `WSL_DISTRIBUTION=Ubuntu`);
- `EVIDENCE_ROOT=...`;
- `PREREQUISITE_EVIDENCE=...`;
- `[PROOF_CEILING] Physical WSL interoperability floor only; no live FirstMate crew dispatch is proven.`

## Failure handling

| Symptom | Execution-owner action |
|---|---|
| Missing Ubuntu tools (`git`/`gh`/`tmux`/`python3`) | Prefer `-Mode physical-floor-continue` / `Invoke-FirstMatePhysicalFloorContinuation.ps1`, which executes the exact emitted `NEXT_ACTION` package command inside explicit Ubuntu and reruns without another permission round-trip. Manual repair remains valid when using report-only `-Mode physical-floor`. |
| `sudo` / package manager cannot complete | Preserve the evidence root and report the exact package-manager/sudo blocker. Do not broaden to another distro, Windows package manager, or arbitrary package source. |
| GitHub auth blocked (`STATUS=BLOCKED_GITHUB_AUTH`, exit 45) | Operator performs the emitted `gh auth login ...` command. Do not automate credential entry or persist tokens. Then rerun the physical floor / continuation entrypoint. |
| Host lacks `wsl.exe`, or `Ubuntu` is missing/unrunnable (`STATUS=BLOCKED_WINDOWS_WSL_REQUIRED`, exit 46 / `FAILURE_CODE=WINDOWS_WSL_REQUIRED`) | Cloud/Linux hosts without `wsl.exe`, and Windows hosts whose contracted distribution cannot run `wsl --distribution Ubuntu --exec true`, fail closed before package repair or interop. This is a LIVE_ATTEMPT_FAIL_CLOSED receipt, not physical PASS. Move to an authorized Windows Admin Box with explicit runnable `Ubuntu`. |
| Exact-head mismatch | Re-fetch/ff-only `main`, re-resolve HEAD, rerun with the new SHA. |
| WSL timeout / transport failure | Preserve the Windows evidence root; default cleanup removes the script-owned WSL clone. Re-run after repairing the environment. |
| Wrong distribution | Do not retarget to the operator default. Repair/install the contract `Ubuntu` distribution in a separately authorized environment/bootstrap lane. |

## Ownership reminder

AgentSwitchboard owns the Windows/WSL substrate and evidence. FirstMate owns live crew execution after this floor. Do not revive an AgentSwitchboard FirstMate crew skill, capability, or trigger to satisfy `FM-WSL-12`.

Allowlisted Ubuntu prerequisite package repair is substrate convergence and remains AgentSwitchboard-side work. It does not transfer live crew ownership back to AgentSwitchboard.

## Next transition

After a physical-floor PASS on the Admin Box, the next owner is `FM-CREW-13`: one bounded local-only FirstMate crew pilot. Do not promote a physical-floor PASS into crew-runtime proof.
