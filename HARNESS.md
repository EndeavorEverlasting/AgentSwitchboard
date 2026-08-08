# AgentSwitchboard Operational Harness

Start here **after `AGENTS.md`** when you need to enter the repository without relying on remembered paths or hidden commands.

This operational harness does not replace the repository-family, environment-capability, device-profile, application, Pi, GNHF, or Windows profile harnesses. It tells you how to find and select the owner, run the right validator, record artifacts, recover from failures, and hand off.

## Fast entry

From the repository root:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperationalHarness.ps1
python tests/test_operational_harness.py
python tooling/harness/operational/Get-OperationalHarnessStatus.py --task "describe the task"
```

On POSIX systems use `python3` instead of `python` when that is the installed command.

The status command is read-only. By default it writes untracked evidence below the operating-system temporary directory and prints the report path.

For an isolated verification worktree, preserve the logical branch and exact head explicitly:

```powershell
python tooling/harness/operational/Get-OperationalHarnessStatus.py `
  --task "verify this PR before review or merge" `
  --branch-label "<logical-branch>" `
  --branch-ref "origin/<logical-branch>" `
  --expected-head "<exact-sha>" `
  --pr-number <number> `
  --validated-command "<command already run successfully>" `
  --gate-complete
```

`--gate-complete` is caller attestation and requires at least one explicit validation receipt. The reporter does not execute or infer those receipts. When a complete PR gate is reported, the generated next action names the repository owner, keeps merge authorization/review as an explicit dependency, and pins any proposed merge command to the exact observed head.

## Canonical operational files

- `tooling/harness/operational/manifest.json` — operational harness entrypoints and safety ceiling.
- `tooling/harness/operational/codebase-map.json` — compact repository structure, commands, and known traps.
- `tooling/harness/operational/workflow-registry.json` — deterministic routing to task intake, validation, failure recovery, handoff, and specialized domain skills.
- `tooling/harness/operational/artifact-registry.json` — generated evidence roles, names, generators, and proof ceilings.
- `tooling/harness/operational/validator-registry.json` — owning, foundation, domain, and aggregate checks.
- `tooling/harness/operational/workflows/` — executable workflow specifications.
- `.ai/skills/operational-harness-routing/SKILL.md` — scoped repeatable procedure.
- `docs/harness/operational-harness.md` — human operator guide.
- `scripts/Test-OperationalHarness.ps1` and `tests/test_operational_harness.py` — completeness contracts.
- `.github/workflows/operational-harness.yml` — Windows/Linux hosted gate.
- `tooling/harness/operational/hooks/Invoke-OperationalHarnessPreCommit.ps1` — optional pre-commit helper. It is never installed implicitly.
- `tooling/harness/operational/hooks/Invoke-OperationalHarnessPrePush.ps1` — optional pre-push helper. It never guesses a stacked base when no upstream exists.

## Workflow choice

Use `task-intake` when entering fresh or when repository/branch ownership is uncertain.

Use `pre-commit-validation` after implementation is complete but before committing.

Use `failure-recovery` when a validator, CI job, schema, fixture, or contract fails.

Use `handoff` when another agent/chat/operator must continue the exact branch and proof state, or when a completed verification gate has reached a review/merge dependency.

Cross-environment work must route through `.ai/skills/environment-capability-routing/SKILL.md`. Operator-visible runtime proof must route through `.ai/skills/end-to-end-runtime-validation/SKILL.md`. Those specialized owners outrank generic operational convenience.

## Safety and proof

This harness may inspect repository files, local Git identity/state, and registered validators. It may generate local status/report/handoff artifacts. It does not authorize governance edits, product mutation, provider access, credentials, deployment, live-target mutation, destructive Git, merge, or proof promotion.

A generated merge command is an owner-gated next action, not merge authorization and not an action performed by the harness.

A green operational harness means the repository has a coherent **operational control surface**. It does not mean the application, agents, providers, remote machines, or user workflow have run successfully.
