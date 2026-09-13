# FirstMate ↔ AgentSwitchboard convergence

This document is the durable Windows Admin Box guidance for FirstMate on current `main`. It extracts ownership and safety invariants from the stale FirstMate PR stack without merging that stack.

Machine-readable authority:

- `tooling/firstmate/harness/convergence-contract.json`
- `tooling/firstmate/harness/upstream-pin.json`

## Architecture decision binding

Accepted ADR [`docs/architecture/asb-firstmate-runtime-boundary.md`](../architecture/asb-firstmate-runtime-boundary.md) (`ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME`) makes FirstMate the **canonical live crew runtime**. AgentSwitchboard keeps workstation/bootstrap convergence, readiness, policy, validation, and evidence sinks. Do **not** grow the child-agent bus into a second crew orchestration platform.

Windows Admin Box hosts the **bridge only**; FirstMate execution remains **WSL/Ubuntu**. The historical PR #96 audit commit is provenance; rebase must re-verify against the ADR evidence floor (or newer reviewed FirstMate main) before live interop claims.

## Roles

| Role | Owner |
|---|---|
| Control plane | AgentSwitchboard — machine, provider, workflow, policy, validators, evidence, escalation |
| Crew chief | FirstMate — decompose and supervise parallel crew work under ASB policy |
| Workers | Coding agents — bounded edits/tests/reports in assigned branches or worktrees |
| Session backend | tmux — reference substrate only |

## Windows Admin Box guidance

- **FirstMate runtime is WSL/Ubuntu only.** Prove and operate FirstMate inside Ubuntu on WSL.
- **Windows hosts are bridge only.** The Windows Admin Box may launch, select, and diagnose the WSL path. It does not host a native Windows FirstMate runtime.
- **Native Windows FirstMate is out of scope.** Do not claim or implement native Windows FirstMate compatibility from this convergence floor.
- **Herdr is deferred.** Both the FirstMate session-Herdr lane and Android/Termux Herdr remain experimental-unproved and are not part of Windows Admin Box bootstrap now.

## Separate native Windows system bootstraps (already on main)

FirstMate is not a Windows native system-bootstrap product. Keep these lanes separate:

- OpenCode reversible Windows bootstrap: `docs/harness/opencode-native-system-bootstrap.md`
- Pi Windows system bootstrap: `docs/harness/pi-system-bootstrap-and-child-agents.md`
- Multi-product sequencing charter: `docs/harness/multi-product-bootstrap-charter.md`

## Upstream pin

- Repository: [`kunchenguid/firstmate`](https://github.com/kunchenguid/firstmate)
- Audited commit (from PR #96): `833a9a25bcf2ae522d6f93dbbd9911a6d8e7c409`
- Pin file: `tooling/firstmate/harness/upstream-pin.json` (metadata only; no vendor tree)

Upstream declares macOS and Linux. WSL is an AgentSwitchboard integration inference from Linux support, not an upstream WSL certification claim.

## First safe sprint

Until live WSL evidence exists after rebase:

- delivery mode: `local-only`
- `yoloEnabled`: `false`
- no credential mutation
- no dependency installation by the AgentSwitchboard harness
- no FirstMate upstream mutation and no shared ASB registry mutation from this floor

## Stale PR stack (do not merge as-is)

PR #96 (`feat/firstmate-interop-wsl-20260808`) is mergeable but far behind current `main`. Do **not** merge it without rebase. Dependency order for salvage:

1. **#96** — FirstMate interop / WSL foundation
2. **#98** — Ubuntu runtime hardening (depends on #96)
3. **#101** — WSL prerequisite gate (depends on #96; re-stack when integrating)
4. **#99** — Windows-native harness portability (depends on #98; bridge host only)
5. **#100** — Python interpreter continuity (depends on #99)

Rebase the stack onto current `main` before integration. Prefer extracting durable contracts onto main (this floor) over cherry-picking the entire stack.

## Operator next (after rebase)

When `tooling/firstmate/Test-FirstMateInterop.sh` is present on a rebased branch, run this **inside WSL/Ubuntu**:

```bash
bash tooling/firstmate/Test-FirstMateInterop.sh
```

If the FirstMate clone is outside default probe locations:

```bash
bash tooling/firstmate/Test-FirstMateInterop.sh --firstmate "$HOME/path/to/firstmate"
```

That future probe must stay read-only: no credential mutation, no dependency install by the ASB harness, and no live FirstMate crew dispatch claim from a static or contract pass.

## Proof ceiling

This convergence floor proves contract + docs + static tests only. It does **not** prove live FirstMate crew dispatch, physical WSL runtime success, native Windows FirstMate execution, Herdr readiness, or merge of PR #96 / #98 / #101 / #99 / #100.
