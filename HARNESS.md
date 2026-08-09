# AgentSwitchboard Operational Harness

Start here **after `AGENTS.md`** when you need to enter the repository without relying on remembered paths or hidden commands.

This operational harness does not replace the repository-family, Wayfinder, environment-capability, device-profile, application, Pi, GNHF, or Windows profile harnesses. It tells you how to find/select the owner, run the right validator, preserve granted integration authority, record artifacts, recover from failures, complete safe integration, and hand off only when work truly transfers or remains blocked.

## Fast entry

From the repository root:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperationalHarness.ps1
python tests/test_operational_harness.py
python tests/test_operational_merge_authority.py
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

`--gate-complete` is caller attestation and requires at least one explicit validation receipt. The reporter does not execute or infer those receipts.

If the current task or an explicit standing repository-owner directive already authorizes merging validated in-scope work, **preserve that authority** instead of asking again:

```powershell
python tooling/harness/operational/Get-OperationalHarnessStatus.py `
  --task "complete validated PR integration" `
  --pr-number <number> `
  --validated-command "<command already run successfully>" `
  --gate-complete `
  --merge-authorized `
  --merge-authority-source "<current task prompt or standing repository-owner directive>"
```

With recorded authority, the generated exact-head merge action is owned by the **current harness agent**. The agent must recheck live mergeability/checks/reviews and execute the pinned merge in the same work cycle when safe. Opening a PR, printing the command, or asking the owner to repeat authorization is not completion.

Without recorded merge authority, the generated next action remains owner-controlled and explicitly names authorization/review as the dependency. The reporter never invents authority.

## Wayfinder: multi-session ambiguity

Use `.ai/skills/wayfinder/SKILL.md` when the destination is larger than one bounded session **and the safe route is not yet clear because important decisions remain in fog**. Do not use Wayfinder merely because an implementation is large if the route is already known.

Wayfinder has its own harness root:

- `tooling/harness/wayfinder/manifest.json` — ownership, ticket types, tracker adapter, lifecycle and proof ceiling.
- `tooling/harness/wayfinder/wayfinder_contract.py` — deterministic ticket gates/frontier/spec-readiness classes and methods.
- `tooling/harness/wayfinder/github_tracker.py` — GitHub issue/sub-issue/dependency/claim/resolution command adapter.
- `tooling/harness/wayfinder/schemas/` — closed map, decision-ticket and temporary-spec schemas.
- `scripts/Test-WayfinderHarness.ps1` and `tests/test_wayfinder_harness.py` — owning validators.
- `docs/harness/wayfinder.md` — operator doctrine and live-proof boundary.
- `third_party/mattpocock-skills/<pinned-commit>/` — immutable donor-source evidence; never ASB runtime authority.

Wayfinder's decision tickets are not public-plan `tasks[]` and are not implementation tickets. The tracker child ticket owns the exact question/resolution. The public plan may mirror the map for repository coordination. After fog and decision tickets clear, `to-spec` may create a temporary spec; `to-tickets` or `bounded-sprint` owns later implementation.

Ticket type is a fail-closed workflow gate:

- research → `research` and primary-source findings;
- prototype → `prototype` plus an observed human verdict;
- grilling → `grilling` + `domain-modeling` plus actual human answers;
- task → prerequisite action actually completed.

Chart mode stops before resolving non-research tickets. A normal work session resolves at most one non-research decision ticket.

## OpenCode prompt preflight and execution

Do **not** use two separate clipboard-backed invocations for an OpenCode `PlanOnly` preflight followed by execution. The clipboard is a mutable intake surface, not a continuation artifact.

When preflight must happen before the bounded sprint, use the prompt-handoff harness so the prompt is materialized once and both gates receive the same `-PromptPath` and SHA-256 identity:

```powershell
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-prompt-handoff/Invoke-OpenCodePromptHandoff.ps1 `
  -RepoPath <repo-path> `
  -Name <sprint-name> `
  -PushBranch
```

If `-PromptPath` is omitted, the harness reads the clipboard exactly once at startup. It does not require a second copy/paste after preflight. Read `docs/harness/opencode-prompt-handoff.md` and `.ai/skills/opencode-prompt-handoff/SKILL.md` for artifacts, recovery, validation, and proof ceiling.

## Canonical operational files

- `tooling/harness/operational/manifest.json` — operational harness entrypoints and safety ceiling.
- `tooling/harness/operational/codebase-map.json` — compact repository structure, commands, and known traps.
- `tooling/harness/operational/workflow-registry.json` — deterministic routing to task intake, validation, failure recovery, handoff/integration continuation, and specialized domain skills including Wayfinder.
- `tooling/harness/operational/artifact-registry.json` — generated evidence roles, names, generators, and proof ceilings.
- `tooling/harness/operational/validator-registry.json` — owning, foundation, domain, and aggregate checks, including Wayfinder's owning gates.
- `tooling/harness/operational/workflows/` — executable workflow specifications.
- `tooling/harness/operational/opencode-prompt-handoff/` — deterministic prompt materialization plus same-artifact OpenCode preflight/execution composition.
- `tooling/harness/wayfinder/` — typed ambiguity-resolution harness and tracker adapter.
- `.ai/skills/operational-harness-routing/SKILL.md` — scoped repeatable procedure.
- `.ai/skills/wayfinder/SKILL.md` — tracker-backed ambiguity-resolution procedure.
- `.ai/skills/opencode-prompt-handoff/SKILL.md` — canonical no-recopy prompt handoff procedure.
- `docs/harness/operational-harness.md` — human operator guide.
- `docs/harness/wayfinder.md` — Wayfinder operator guide.
- `docs/harness/opencode-prompt-handoff.md` — human prompt-handoff operator guide.
- `scripts/Test-OperationalHarness.ps1`, `tests/test_operational_harness.py`, and `tests/test_operational_merge_authority.py` — completeness and authority-continuation contracts.
- `scripts/Test-WayfinderHarness.ps1` and `tests/test_wayfinder_harness.py` — Wayfinder source/semantic/tracker-contract validation.
- `scripts/Test-OpenCodePromptHandoffHarness.ps1` and `tests/test_opencode_prompt_handoff_harness.py` — prompt-handoff completeness and anti-regression contracts.
- `.github/workflows/operational-harness.yml` — Windows/Linux hosted harness gate.
- `.github/workflows/operational-merge-authority.yml` — Windows/Linux authority-continuation regression gate.
- `.github/workflows/wayfinder-public-plan-contribution.yml` — Windows/Linux Wayfinder + contribution gate.
- `.github/workflows/opencode-prompt-handoff-harness.yml` — Windows/Linux prompt-handoff harness gate.
- `tooling/harness/operational/hooks/Invoke-OperationalHarnessPreCommit.ps1` — optional pre-commit helper; never installed implicitly.
- `tooling/harness/operational/hooks/Invoke-OperationalHarnessPrePush.ps1` — optional pre-push helper; requires an exact base instead of guessing the push range.

## Workflow choice

Use `task-intake` when entering fresh or when repository/branch ownership is uncertain.

Use `wayfinder` before execution planning when the destination is known loosely but important decisions are still too foggy for a safe one-session route.

Use `public-plan-coordination` when work spans sessions/branches/PRs but the route is already sufficiently known, or to mirror Wayfinder state without duplicating its decision tickets.

Use `pre-commit-validation` after implementation is complete but before committing.

Use `failure-recovery` when a validator, CI job, schema, fixture, or contract fails.

Use `handoff` after a complete gate to either finish already-authorized safe integration or transfer exact branch/proof state when a real dependency remains unresolved.

OpenCode clipboard prompt intake, `PlanOnly` preflight, preflight-to-execution prompt identity, or any workflow that would require recopying the same prompt must route through `.ai/skills/opencode-prompt-handoff/SKILL.md` and its tracked harness runner.

Cross-environment work must route through `.ai/skills/environment-capability-routing/SKILL.md`. Operator-visible runtime proof must route through `.ai/skills/end-to-end-runtime-validation/SKILL.md`. Specialized owners outrank generic operational convenience.

## Safety and proof

This harness may inspect repository files, local Git identity/state, and registered validators. It may generate local status/report/handoff artifacts. It does not authorize governance edits, product mutation, provider access, credentials, deployment, live-target mutation, destructive Git, tracker mutation, or proof promotion.

Wayfinder static/hosted validation proves contracts and command construction only. Creating labels/maps/sub-issues/dependencies, claiming/resolving live tickets, and obtaining human HITL verdicts require separately authorized live evidence.

Merge authority may come from the current task or an explicit standing repository-owner directive. The harness may **record and preserve** that authority; it may not invent it. When authority is recorded and the validated in-scope merge remains safe, the current harness agent owns continuation through the exact-head-pinned merge.

A generated merge command without recorded authority is an owner-gated next action. A generated merge command with recorded authority is an executable current-agent action, but it is still not merge proof until GitHub returns a successful merge result.

A green operational harness means the repository has a coherent **operational control surface**. It does not mean the application, agents, providers, remote machines, human decisions, issue tracker, or user workflow have run successfully.
