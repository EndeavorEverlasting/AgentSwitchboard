# FirstMate ↔ AgentSwitchboard convergence

This document is the durable Windows Admin Box guidance for FirstMate on current `main`. It preserves the useful failure contracts from the historical FirstMate PR stack without merging that stale stack wholesale.

Machine-readable authority:

- `tooling/firstmate/harness/convergence-contract.json`
- `tooling/firstmate/harness/upstream-pin.json`
- `tooling/firstmate/harness/integration-contract.json`
- `tooling/firstmate/harness/operational/manifest.json`
- `tooling/firstmate/Test-FirstMateInterop.sh`

Focused integration docs:

- [`docs/harness/firstmate-integration.md`](firstmate-integration.md)
- [`docs/harness/firstmate-operational-harness.md`](firstmate-operational-harness.md)

## Architecture decision binding

Accepted ADR [`docs/architecture/asb-firstmate-runtime-boundary.md`](../architecture/asb-firstmate-runtime-boundary.md) (`ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME`) makes FirstMate the **canonical live crew runtime**. AgentSwitchboard keeps workstation/bootstrap convergence, readiness, policy, validation, evidence sinks, and escalation. Do **not** grow the child-agent bus or the Windows bridge into a second crew orchestration platform.

Windows Admin Box hosts the **bridge only**; FirstMate execution remains **WSL/Ubuntu**. The historical PR #96 audit commit (`833a9a25bcf2ae522d6f93dbbd9911a6d8e7c409`) is provenance only. Current audited pin is FirstMate `main@b182d0f908b78d08c7ccb8dce3775bdca8c5d657`.

`FM-REFRESH-06` rebuilt the Linux/WSL foundation on current main. `FM-BRIDGE-10` rebuilds the durable Windows→WSL bridge lessons from PRs #98/#99/#100/#101 on that refreshed floor. The stale stack remains historical evidence and is not merged as-is.

## Roles

| Role | Owner |
|---|---|
| Workstation/bootstrap convergence, readiness, validation, evidence | AgentSwitchboard |
| Crew chief / live runtime | FirstMate |
| Workers | Coding agents managed by FirstMate |
| Reference session backend | tmux |

## Windows Admin Box guidance

- **FirstMate runtime is WSL/Ubuntu only.** Prove and operate FirstMate inside Ubuntu on WSL.
- **Windows hosts are bridge only.** The tracked PowerShell harness validates the Windows side and crosses into explicit Ubuntu; it does not host FirstMate natively.
- **Native Windows FirstMate is out of scope.** Do not infer support from a Windows-hosted contract PASS.
- **FirstMate owns dispatch and lifecycle.** AgentSwitchboard does not register a FirstMate crew-routing skill, capability, trigger, wake loop, task state machine, or runtime selector in `FM-BRIDGE-10`.
- **Herdr is deferred.** FirstMate/Herdr and Android/Termux Herdr remain experimental-unproved and outside the Windows Admin Box bootstrap wave.

## Separate native Windows system bootstraps

FirstMate is not a Windows-native system-bootstrap product. Keep these lanes separate:

- OpenCode reversible Windows bootstrap: `docs/harness/opencode-native-system-bootstrap.md`
- Pi Windows system bootstrap: `docs/harness/pi-system-bootstrap-and-child-agents.md`
- Multi-product sequencing charter: `docs/harness/multi-product-bootstrap-charter.md`

## Upstream pin

- Repository: [`kunchenguid/firstmate`](https://github.com/kunchenguid/firstmate)
- Current audited commit: `b182d0f908b78d08c7ccb8dce3775bdca8c5d657`
- Historical PR #96 audit commit: `833a9a25bcf2ae522d6f93dbbd9911a6d8e7c409`
- Pin owner: `tooling/firstmate/harness/upstream-pin.json`

Upstream declares macOS and Linux. WSL remains an AgentSwitchboard integration inference from Linux support, not an upstream WSL certification claim.

## First safe sprint

Until live crew proof exists:

- delivery mode: `local-only`
- `yoloEnabled`: `false`
- no remote writes
- no credential mutation
- no dependency installation by the AgentSwitchboard harness
- no FirstMate upstream mutation
- no shared ASB registry mutation from the runtime lane

## Historical PR stack disposition

Do **not** merge the old stack wholesale.

1. **#96** — foundation provenance; rebuilt by `FM-REFRESH-06`.
2. **#98** — explicit Ubuntu, bounded WSL subprocesses, unique evidence roots; rebuilt by `FM-BRIDGE-10`.
3. **#101** — prerequisite gate; rebuilt by `FM-BRIDGE-10`.
4. **#99** — Windows-native contract front door; rebuilt by `FM-BRIDGE-10`.
5. **#100** — Windows interpreter continuity; rebuilt by `FM-BRIDGE-10` using the current Python executable.

Historical green CI remains evidence for why those contracts exist, not proof for the new mainline implementation.

## Operator next: physical-floor

After the bridge contract is integrated on current main, use the Windows-native front door from a clean, refreshed AgentSwitchboard checkout:

```powershell
$head = (git rev-parse HEAD).Trim()
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 `
  -Mode physical-floor `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
```

The prerequisite wrapper first checks inside Ubuntu for `git`, `gh`, `tmux`, `python3`, and GitHub CLI authentication. It may print exact package/login recovery commands, but AgentSwitchboard does not execute those recovery commands, install dependencies, or mutate credentials itself.

If prerequisites pass, the lower bridge creates a WSL-owned standalone clone at the exact AgentSwitchboard SHA, runs the tracked bridge contract, then runs the read-only FirstMate interoperability probe. Local receipts remain untracked.

A successful physical-floor run proves the Windows→Ubuntu/WSL interoperability floor only. It does not dispatch a FirstMate worker. The later `FM-CREW-13` local-only pilot owns live crew proof.

## Proof ceiling

This convergence floor may prove:

- current FirstMate pin and ownership contract;
- Windows bridge-only posture;
- tracked explicit-Ubuntu bridge mechanics;
- hosted Windows/Linux bridge validation;
- prerequisite-gate ordering and non-mutation;
- preservation of historical Windows→WSL regression contracts;
- deliberate non-registration of an AgentSwitchboard FirstMate crew-routing skill/capability/trigger.

It does **not** prove:

- the physical Windows→Ubuntu/WSL floor until `FM-WSL-12` runs;
- live FirstMate crew dispatch/supervision until `FM-CREW-13` runs;
- native Windows FirstMate execution;
- provider/model delivery;
- Herdr readiness;
- merge of historical PR #96/#98/#99/#100/#101.
