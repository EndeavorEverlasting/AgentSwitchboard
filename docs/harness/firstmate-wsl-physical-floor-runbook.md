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
2. Checkout current `main` (post `FM-BRIDGE-10`, including `Invoke-Asq017AdminBoxLiveFloor.ps1` after #183 merges) and record the exact SHA.
3. Confirm the WSL distribution named `Ubuntu` exists and is runnable (`wsl.exe -l -v`; `wsl.exe -d Ubuntu --exec true`).
4. Do not change the default WSL distro to satisfy this floor; the harness must target `Ubuntu` explicitly.
5. Pre-stage inside Ubuntu before expecting PASS: one primary harness on PATH (`claude`, `grok`, `pi`, `pi-signed`, `omp`, `codex`, `opencode`, or `cursor-agent`) and Ubuntu `gh` auth. If a clean FirstMate clone is missing, `Test-FirstMateInterop.sh` may perform a **bounded** bootstrap clone of `kunchenguid/firstmate` to `$HOME/firstmate` at audited pin `b182d0f908b78d08c7ccb8dce3775bdca8c5d657` (never mutates an existing path or upstream). Optional: pass `-FirstMatePath` through `Invoke-Asq017AdminBoxLiveFloor.ps1` when discovery/bootstrap should be skipped.
6. GitHub auth is probed **inside Ubuntu** (`gh auth status`); Windows-only login is not sufficient. Exit 45 remains the operator credential gate.
7. Keep evidence local/untracked. Do not commit receipts, tokens, or machine-local paths.
8. Treat bounded missing-package repair inside `Ubuntu` as in-scope for this sprint; do not stop merely because the prerequisite gate reports an allowlisted tool missing. Passwordless `sudo` is required for non-interactive apt repair.

## Exact commands

From the AgentSwitchboard checkout root on the Admin Box (after #183 is on `main`, or from this PR tip):

```powershell
$ErrorActionPreference = 'Stop'
# Preferred ASQ-017 durable owner: ff-only main refresh + FM-WSL-12 one-shot.
# Keep the interactive parent shell open: capture CHILD_EXIT_CODE and throw (do not exit).
if (-not (Test-Path -LiteralPath .\Invoke-Asq017AdminBoxLiveFloor.ps1)) {
  throw 'Run from AgentSwitchboard checkout root (Invoke-Asq017AdminBoxLiveFloor.ps1 missing).'
}
pwsh -NoLogo -NoProfile -File .\Invoke-Asq017AdminBoxLiveFloor.ps1
$childExit = $LASTEXITCODE
Write-Host "CHILD_EXIT_CODE=$childExit"
if ($childExit -eq 45) {
  throw 'BLOCKED_GITHUB_AUTH — complete gh auth login inside Ubuntu then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
}
if ($childExit -eq 47) {
  throw 'BLOCKED_SUDO — enable passwordless sudo for apt-get in Ubuntu (sudo -n apt-get --version must succeed), then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
}
if ($childExit -eq 48) {
  throw 'BLOCKED_PRIMARY_HARNESS — install one primary harness on PATH inside Ubuntu visible to non-interactive bash -lc (claude|grok|pi|pi-signed|omp|codex|opencode|cursor-agent), then rerun'
}
if ($childExit -eq 49) {
  throw 'BLOCKED_FIRSTMATE_DIRTY — commit/stash/move dirty work in $HOME/firstmate, or remove that path so bounded bootstrap can run, then rerun'
}
if ($childExit -eq 50) {
  throw 'BLOCKED_FIRSTMATE_PIN — in $HOME/firstmate run: git fetch --all && git checkout b182d0f908b78d08c7ccb8dce3775bdca8c5d657, or remove that path / pass -FirstMatePath to a clean audited checkout, then rerun'
}
if ($childExit -ne 0) {
  throw "ASQ-017 Admin Box live floor failed with exit $childExit"
}
```

`Invoke-Asq017AdminBoxLiveFloor.ps1` is the durable ASQ-017 Admin Box floor owner. It fail-closes native git refresh (`fetch`/`switch`/`pull`/`rev-parse` with capture-before-Trim), then runs `Invoke-FmWsl12AdminBoxLiveProof.ps1` (contract → `physical-floor-continue` → protected `physical-floor`). The one-shot still stops for GitHub authentication (exit 45), passwordless apt sudo (exit 47), missing primary harness on non-interactive PATH (exit 48), dirty `$HOME/firstmate` (exit 49), and FirstMate pin mismatch / blocked bootstrap (exit 50); probes runnable `Ubuntu` before apt/preflight; and writes a local untracked receipt. Interactive pastes must print `CHILD_EXIT_CODE` and `throw` rather than calling interactive `exit`.

Equivalent expanded form (same proof ceiling; prefer the durable entrypoint above):

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
pwsh -NoLogo -NoProfile -File .\Invoke-FmWsl12AdminBoxLiveProof.ps1 `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
$childExit = $LASTEXITCODE
Write-Host "CHILD_EXIT_CODE=$childExit"
if ($childExit -eq 45) {
  throw 'BLOCKED_GITHUB_AUTH — complete gh auth login then rerun Invoke-FmWsl12AdminBoxLiveProof.ps1'
}
if ($childExit -eq 47) {
  throw 'BLOCKED_SUDO — enable passwordless sudo for apt-get in Ubuntu (sudo -n apt-get --version must succeed), then rerun'
}
if ($childExit -eq 48) {
  throw 'BLOCKED_PRIMARY_HARNESS — install one primary harness on PATH inside Ubuntu visible to non-interactive bash -lc, then rerun'
}
if ($childExit -eq 49) {
  throw 'BLOCKED_FIRSTMATE_DIRTY — commit/stash/move dirty work in $HOME/firstmate, or remove that path so bounded bootstrap can run, then rerun'
}
if ($childExit -eq 50) {
  throw 'BLOCKED_FIRSTMATE_PIN — checkout audited FirstMate pin b182d0f908b78d08c7ccb8dce3775bdca8c5d657 or pass -FirstMatePath, then rerun'
}
if ($childExit -ne 0) {
  throw "FM-WSL-12 Admin Box live proof failed with exit $childExit"
}
```

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
| `sudo` / package manager cannot complete (`STATUS=BLOCKED_SUDO`, exit 47) | Enable passwordless `sudo` for `apt-get` inside Ubuntu so `sudo -n apt-get --version` succeeds non-interactively. Preserve `sudo-probe-stdout.txt` / `sudo-probe-stderr.txt` evidence. Do not broaden to another distro, Windows package manager, or arbitrary package source. |
| GitHub auth blocked (`STATUS=BLOCKED_GITHUB_AUTH`, exit 45) | Operator performs the emitted `gh auth login ...` command **inside Ubuntu**. Do not automate credential entry or persist tokens. Then rerun the physical floor / continuation entrypoint. |
| Host lacks `wsl.exe`, or `Ubuntu` is missing/unrunnable (`STATUS=BLOCKED_WINDOWS_WSL_REQUIRED`, exit 46 / `FAILURE_CODE=WINDOWS_WSL_REQUIRED`) | Cloud/Linux hosts without `wsl.exe`, and Windows hosts whose contracted distribution cannot run `wsl --distribution Ubuntu --exec true`, fail closed before package repair or interop. This is a LIVE_ATTEMPT_FAIL_CLOSED receipt, not physical PASS. Move to an authorized Windows Admin Box with explicit runnable `Ubuntu`. |
| Primary harness missing on non-interactive PATH (`STATUS=BLOCKED_PRIMARY_HARNESS`, exit 48) | Install one primary harness (`claude`\|`grok`\|`pi`\|`pi-signed`\|`omp`\|`codex`\|`opencode`\|`cursor-agent`) so `wsl -d Ubuntu --exec bash -lc "command -v <harness>"` succeeds, then rerun. |
| Dirty `$HOME/firstmate` (`STATUS=BLOCKED_FIRSTMATE_DIRTY`, exit 49) | Commit, stash, or move dirty work under `$HOME/firstmate`, or remove that path so bounded bootstrap can run, then rerun. |
| FirstMate pin mismatch / blocked bootstrap (`STATUS=BLOCKED_FIRSTMATE_PIN`, exit 50) | In `$HOME/firstmate` run `git fetch --all && git checkout b182d0f908b78d08c7ccb8dce3775bdca8c5d657`, or remove that path / pass `-FirstMatePath` to a clean audited `kunchenguid/firstmate` checkout, then rerun. |
| Exact-head mismatch | Re-fetch/ff-only `main`, re-resolve HEAD, rerun with the new SHA. |
| WSL timeout / transport failure | Preserve the Windows evidence root; default cleanup removes the script-owned WSL clone. Re-run after repairing the environment. |
| Wrong distribution | Do not retarget to the operator default. Repair/install the contract `Ubuntu` distribution in a separately authorized environment/bootstrap lane. |

## Ownership reminder

AgentSwitchboard owns the Windows/WSL substrate and evidence. FirstMate owns live crew execution after this floor. Do not revive an AgentSwitchboard FirstMate crew skill, capability, or trigger to satisfy `FM-WSL-12`.

Allowlisted Ubuntu prerequisite package repair is substrate convergence and remains AgentSwitchboard-side work. It does not transfer live crew ownership back to AgentSwitchboard.

## Next transition

After a physical-floor PASS on the Admin Box, the next owner is `FM-CREW-13`: one bounded local-only FirstMate crew pilot. Do not promote a physical-floor PASS into crew-runtime proof.
