# ASB-2026-09 user tutorial path ranking

## Mission

After FirstMate became the canonical live crew runtime, AgentSwitchboard remains the Windows-first bootstrapper, readiness surface, policy/evidence owner, and bounded single-agent (GNHF) launcher. This plan ranks which user journeys deserve tutorial investment and which must not be taught as current product.

Evidence floor: `main@3a153c11f9db9cacc1d9d9dda8c7358c0e3ecbf0`
ADR: `docs/architecture/asb-firstmate-runtime-boundary.md`
Open Worker: no repository matches — rejected as a product journey.

## Launch order

1. **TUT-01** — Day-0 technician bootstrap → pull-and-run → Ready (**P18**, READY_NOW)
2. **Safe parallel after TUT-01:** **TUT-03** live-cert click path + **TUT-04** machine-profile anti-OneDrive (**P18**)
3. **TUT-02** — Startup readiness → OpenCode click sprint / bounded GNHF (**P18**, after TUT-01)
4. **Safe parallel prerequisites (not tutorials):** **TUT-PRE-01** ASQ-016 GNHF NARROW + **TUT-PRE-02** Pi doc strip (**P07**)
5. **TUT-05** — FirstMate Windows→WSL floor tutorial only after ASQ-015/017 runtime proof (**P08**, blocked)

## Immediate move

First tutorial sprint: **TUT-01 Day-0 technician bootstrap to Ready**.

Why first: it is the highest-frequency friction reducer for the product ASB still owns (workstation acquisition and readiness), it is already implemented with CMD entrypoints and workstation docs, and later single-agent / live-cert tutorials depend on that starting state. It is not merely the largest documentation gap — it is the only path that makes the rest independently usable.

No product-fix prerequisite blocks TUT-01. Prefer clarifying “bootstrap + readiness, not crew control plane” in TUT-01 framing rather than waiting on README metaphor edits.

## Ranked tutorial portfolio

| Rank | Path | Audience | Readiness | User value | Evidence maturity | Principal gap | Dependencies | Risk | Format | Proof ceiling |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Day-0 bootstrap → pull-and-run → Ready | Windows technician | READY_NOW | Highest onboarding | CMD + docs + ready/live-cert validators | No single post-FirstMate Day-0 tutorial | none | WSL/WezTerm installs; reboot 3010 | Concise walkthrough | Local readiness ≠ provider auth |
| 2 | Startup readiness → OpenCode click sprint | Agent-operator / developer | READY_NOW | Primary remaining ASB execution path | Launchers + readiness docs | Control-plane language vs bounded GNHF | TUT-01 recommended | Worktree sprint; provider auth outside ASB | Click/command walkthrough | Launcher ack ≠ model quality |
| 3 | Live-cert click path P00–P08 | Technician | READY_NOW | High for cert/recovery | Click guide + harness validators | Consolidation into teachable path | TUT-01 | Installers/network; optional Hermes | Stage guide + repairs | Docs ≠ LIVE PASS |
| 4 | Machine-profile / chosen-directory | Technician | READY_NOW | Prevents OneDrive/path mistakes | Profile docs + bootstrap tests | Buried supporting path | TUT-01 | Path binding | Short anti-footgun | Profile ≠ workstation success |
| 5 | OpenCode system-wide bootstrap | Admin/technician | READY_NOW | Medium | Lifecycle validators | Narrow audience | TUT-01 | Program Files / PATH | Apply/Remove | Lifecycle ≠ LSP runtime |
| 6 | tmux/WezTerm open-or-activate | Technician | READY_NOW | Medium supporting | Launcher contract + field history | Duplicate-window confusion | TUT-01 | GUI consent | Short launch-mode | Shortcut needs local runtime |
| 7 | Pi Windows/WSL install-only | Technician/admin | READY_AFTER_DOC_FIX | Medium | Pi harness completeness | Stale child-bus teaching in Pi docs | TUT-PRE-02 | Admin elevation | Install-only | Installer ≠ crew runtime |
| 8 | FirstMate WSL physical floor | Admin | BLOCKED_BY_ACCESS_OR_ENVIRONMENT | High Admin / low general until PASS | Contracts on main; live UNPROVEN | gh auth + pin refresh + observed PASS | ASQ-015/017 | apt/sudo/gh/dirty pin | P08 field procedure | Bridge only; never ASB crew |

## Candidate disposition ledger

| Candidate | Disposition | Note |
|---|---|---|
| Day-0 bootstrap + pull-and-run + Ready | ready | TUT-01 first launch |
| OpenCode click / startup readiness | ready | TUT-02; label bounded GNHF |
| Live-cert click path | ready | TUT-03 safe parallel after TUT-01 |
| Machine-profile / directory bootstrap | ready | TUT-04 safe parallel after TUT-01 |
| OpenCode system-wide bootstrap | deferred | after Day-0; medium value |
| tmux open-or-activate / new-instance shortcut | deferred | supporting; shortcut needs local runtime |
| Exact-head / stale-checkout validation | deferred | support/debug |
| OpenCode fresh-TUI LSP (ASQ-005) | deferred | advanced; LIVE_PASS already exists |
| Pi install-only bootstrap | prerequisite-first | TUT-PRE-02 before teaching |
| GNHF fleet / night panel / thinker routes | prerequisite-first | TUT-PRE-01 / ASQ-016 before expansion |
| FirstMate bridge / FM-WSL-12 floor | deferred | TUT-05 blocked on access/runtime |
| Android Termux on-the-move | deferred | device-gated niche |
| Prompt Kit website sync | reference-only | admin narrow |
| App-output / progressive disclosure / test floor | reference-only | developer harness |
| ASB child-bus spawn / nested crew / control-plane tutorials | rejected-with-reason | ADR FREEZE/RETIRE; empty adapters |
| Open Worker product journey | rejected-with-reason | zero repository matches |
| Auggie unattended GNHF product path | rejected-with-reason | readiness boundary only |
| Prompt Kit ↔ FirstMate live bridge UX | rejected-with-reason | contract-only |
| README control-plane metaphor as tutorial thesis | merged with another path | clarify inside TUT-01/TUT-02 framing |

## Rejected / frozen teaching traps

Do not author tutorials that present ASB as:

- a live multi-agent crew supervisor (`fm-spawn` / secondmates / nested bus);
- a working child-bus launcher (`adapters: []`; fail-closed only);
- an Open Worker product surface (no repo evidence).

Prefer FirstMate docs/upstream for crew runtime once ASQ-015/017 clear.

## Proof ceiling

This ranking is **static / coordination** proof. It does not prove that any tutorial step was executed on a technician workstation, that live-cert PASS occurred, or that FirstMate crew dispatch works.
