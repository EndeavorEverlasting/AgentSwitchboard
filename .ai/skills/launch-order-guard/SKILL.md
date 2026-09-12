# Launch Order Guard — P13 Recurrence Prevention

Trigger: any `xyz_*` placeholder sprint or repeated proof floor without advancing `plans/active/ASB-2026-09-agent-bootstrap-child-bus` frontier.

Rule:
1. Resolve `git fetch --all --prune --tags` → `origin/main` HEAD before choosing gate.
2. Read `scripts/Get-RepositoryWorkLedgerFrontier.ps1 -Json` → `selected` + `actionableCount`.
3. If frontier is `READY`/`BOUNDED` (`ASQ-005`/`006`/`007`), that lane is the critical path — do not re-report `R1` proof floor.
4. Probe parallel execution: `PARALLEL EXECUTION: unavailable — <reason>` when no sub-agent slots; otherwise dispatch collision-safe lanes per P07 one-writer-per-surface.
5. Execute one critical-path advancement before long report; branch listing / PR status alone is not movement.

Validation: `python -m unittest tests.test_p13_recurrence_guard -v` + `python -m unittest tests.test_launch_order_gate` (when present).
