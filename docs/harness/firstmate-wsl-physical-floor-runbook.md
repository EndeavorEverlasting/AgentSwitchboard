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
- package installation or credential mutation by AgentSwitchboard;
- provider/model behavior;
- PR/merge/deploy delivery;
- Herdr readiness.

Live crew proof remains `FM-CREW-13`.

## Preconditions

1. Use an authorized Windows Admin Box with PowerShell 7+ (`pwsh`).
2. Checkout current `main` (post `FM-BRIDGE-10`) and record the exact SHA.
3. Confirm the WSL distribution named `Ubuntu` exists (`wsl.exe -l -v`).
4. Do not change the default WSL distro to satisfy this floor; the harness must target `Ubuntu` explicitly.
5. Keep evidence local/untracked. Do not commit receipts, tokens, or machine-local paths.

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

| Symptom | Operator action |
|---|---|
| Missing Ubuntu tools (`git`/`gh`/`tmux`/`python3`) | Follow the emitted `NEXT_ACTION` package command manually inside Ubuntu. Do not ask AgentSwitchboard to install. |
| GitHub auth blocked | Follow the emitted `gh auth login ...` command manually. Do not persist tokens into the repo. |
| Exact-head mismatch | Re-fetch/ff-only `main`, re-resolve HEAD, rerun with the new SHA. |
| WSL timeout / transport failure | Preserve the Windows evidence root; default cleanup removes the script-owned WSL clone. Re-run after repairing the environment. |
| Wrong distribution | Do not retarget to the operator default. Repair/install the contract `Ubuntu` distribution. |

## Ownership reminder

AgentSwitchboard owns the Windows/WSL substrate and evidence. FirstMate owns live crew execution after this floor. Do not revive an AgentSwitchboard FirstMate crew skill, capability, or trigger to satisfy `FM-WSL-12`.

## Next transition

After a physical-floor PASS on the Admin Box, the next owner is `FM-CREW-13`: one bounded local-only FirstMate crew pilot. Do not promote a physical-floor PASS into crew-runtime proof.
