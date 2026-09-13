# ASQ-005 — OpenCode fresh-TUI Python LSP runtime gates

Machine-readable twin: `tooling/harness/operational/opencode-lsp-setup/asq005-runtime-gates.contract.json`.

## Proof ceiling

ASQ-005 proves or disproves **active Python LSP behavior in a fresh interactive OpenCode TUI**.

- Configure success, CI green, overlay `lsp=true`, and launcher existence are **G1 only**.
- Configure success never counts as ASQ-005 DONE. They never promote to ASQ-005 DONE.
- Cloud/Linux agents cannot substitute for Admin Box 1 observation.
- Runtime receipts stay **local and untracked**.

## Canonical floor

- Checkout: `%USERPROFILE%\dev\AgentSwitchBoard-Live`
- Origin: `https://github.com/EndeavorEverlasting/AgentSwitchboard`
- Live routing floor commit: `24cce9e321a4913dda32f21a2d51a599dd0e4bb4` (must be ancestor of refreshed `main`)
- Headless comparison baseline: `20260912T194619Z-e3f423df`
- Fixture: `tests/test_technician_live_cert_surface.py`
- Symbol: `read_text`
- Operations (LSP tool only, in order): `hover` → `goToDefinition` → `findReferences`
- Forbidden: grep/ripgrep/text/AST/manual semantic fallback

## Gates G0–G8

| Gate | Name | Pass means |
|---|---|---|
| G0 | Canonical repository floor | Correct Live root/origin, fetch + ff-only `main`, clean worktree, ledger still permits ASQ-005, baseline not invalidated |
| G1 | Configuration proof | `OPENCODE_EXPERIMENTAL_LSP_TOOL=true`, Configure exit 0, immutable run dir, overlay `lsp=true`, generated launcher, no foreign OpenCode config rewrite |
| G2 | Fresh TUI launch | Fresh TUI from generated CMD, canonical root, LSP tool exposed, no reused session evidence |
| G3 | LSP activation trigger | Fixture opened exactly once; activation attempted after open; server identity or verbatim prerequisite failure captured |
| G4 | Strict semantic operations | hover/definition/references all LSP-backed; verbatim errors; `nonLspSemanticFallbackUsed = No` |
| G5 | Differential classification | Exactly one of `PASS_TUI_HEADLESS_DIFFERENTIAL`, `PASS_BOTH_MODES`, `FAIL_TUI_ONLY`, `FAIL_BOTH_MODES` |
| G6 | Canonical runtime artifacts | Local `opencode-lsp-runtime-smoke.json/.md` under the run dir; JSON schema-valid; untracked |
| G7 | Owning harness validation | `scripts/Test-OpenCodeLspHarness.ps1` green; `git diff --check` clean |
| G8 | Terminal decision | DONE only when G2–G7 prove live semantic PASS with `LSP_RUNTIME_SMOKE_TEST: PASS`; otherwise FAIL/STOP or bounded defect lane |

## DONE / FAIL

**DONE** only when all are true: fresh TUI observed; supported Python file opened; active semantic LSP proven; hover/definition/references PASS; `nonLspSemanticFallbackUsed = No`; runtime-smoke JSON valid; MD written; verdict `LSP_RUNTIME_SMOKE_TEST: PASS`; owning harness green.

**FAIL/STOP** when the server does not activate, a prerequisite/server error occurs, any semantic operation fails, evidence is incomplete/non-verbatim, fallback is used, the receipt is invalid, or the harness fails.

A TUI failure does not weaken the gate. A reproducible product/harness defect may open a bounded repair lane; after repair, ASQ-005 must be rerun from the refreshed head with new runtime evidence.

## Successor policy (ledger truth)

- ASQ-008 / ASQ-009 remain **FREEZE / HAND-OFF** under `ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME`. Completing ASQ-005 does not authorize ASB live adapter expansion for those lanes.
- ASQ-010–ASQ-012 stay FirstMate-frozen unless an explicit ADR supersession unfreezes them.
- If nested work is ever reauthorized: ASQ-011 owns the bounded nested-delegation mechanism/contract; ASQ-012 owns physical/runtime certification of one heterogeneous depth-2 chain.
- ASQ-013 converges only after authorized terminal predecessors; old receipts do not promote across material head/schema/runtime-owner change.

## Operator entry

Use the ASQ-005 **Next action** in `.ai/WORK_QUEUE.md` on Admin Box 1. Universal lane-entry checks (root/origin/fetch/ff-only/clean/frontier) are part of G0.
