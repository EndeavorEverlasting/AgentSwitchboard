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

The harness itself remains fail-closed and non-installing; this runbook grants the **FM-WSL-12 execution owner** authority to perform the bounded recovery action between attempts and continue the same sprint.

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
git switch main
git pull --ff-only origin main
$head = (git rev-parse HEAD).Trim()
Write-Host "PHYSICAL_FLOOR_HEAD=$head"

# Contract front door first (no live WSL requirement beyond ContractOnly surfaces).
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 `
  -Mode contract `
  -ExpectedHead $head `
  -WslDistribution Ubuntu

# Physical floor: prerequisite gate + bounded Windows→WSL bridge + read-only interop probe.
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 `
  -Mode physical-floor `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
```

If physical-floor mode reports `STATUS=BLOCKED_MISSING_TOOLS`, execute the exact emitted `NEXT_ACTION` inside explicit Ubuntu, then rerun the physical-floor command above. For the currently observed `MISSING_TOOLS=gh` case, the emitted recovery is:

```bash
sudo apt-get update && sudo apt-get install -y gh
```

The execution owner should continue immediately after successful package repair. A package-manager failure, unavailable sudo authorization, repository/package-source failure, or credential/authentication requirement is a real blocker and should be reported with the existing evidence root.

Optional direct physical wrapper (same floor, same proof ceiling):

```powershell
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1 `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
```

## Pass markers to capture

Preserve the console markers and the printed evidence root:

- `[PASS] FIRSTMATE_WINDOWS_OPERATIONAL_HARNESS` from contract mode;
- `[PASS] FIRSTMATE_WINDOWS_WSL_PHYSICAL_FLOOR` from physical mode;
- `HEAD=<40-char sha>`;
- `WSL_DISTRIBUTION=Ubuntu` (and/or bridge `WSL_DISTRIBUTION=Ubuntu`);
- `EVIDENCE_ROOT=...`;
- `PREREQUISITE_EVIDENCE=...`;
- `[PROOF_CEILING] Physical WSL interoperability floor only; no live FirstMate crew dispatch is proven.`

## Failure handling

| Symptom | Execution-owner action |
|---|---|
| Missing Ubuntu tools (`git`/`gh`/`tmux`/`python3`) | Execute the exact emitted `NEXT_ACTION` package command inside explicit Ubuntu, then rerun the same exact-head physical floor. This bounded repair is authorized by FM-WSL-12 and does not require another permission round-trip. |
| `sudo` / package manager cannot complete | Preserve the evidence root and report the exact package-manager/sudo blocker. Do not broaden to another distro, Windows package manager, or arbitrary package source. |
| GitHub auth blocked | Operator performs the emitted `gh auth login ...` command. Do not automate credential entry or persist tokens. Then rerun the physical floor. |
| Exact-head mismatch | Re-fetch/ff-only `main`, re-resolve HEAD, rerun with the new SHA. |
| WSL timeout / transport failure | Preserve the Windows evidence root; default cleanup removes the script-owned WSL clone. Re-run after repairing the environment. |
| Wrong distribution | Do not retarget to the operator default. Repair/install the contract `Ubuntu` distribution in a separately authorized environment/bootstrap lane. |

## Ownership reminder

AgentSwitchboard owns the Windows/WSL substrate and evidence. FirstMate owns live crew execution after this floor. Do not revive an AgentSwitchboard FirstMate crew skill, capability, or trigger to satisfy `FM-WSL-12`.

Allowlisted Ubuntu prerequisite package repair is substrate convergence and remains AgentSwitchboard-side work. It does not transfer live crew ownership back to AgentSwitchboard.

## Next transition

After a physical-floor PASS on the Admin Box, the next owner is `FM-CREW-13`: one bounded local-only FirstMate crew pilot. Do not promote a physical-floor PASS into crew-runtime proof.
