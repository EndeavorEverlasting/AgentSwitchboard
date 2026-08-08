# Operational Harness

The operational harness is the repository's **newcomer control surface**. It exists because AgentSwitchboard already has several strong focused harnesses; without a compact spine, a fresh agent can still choose the wrong one, miss an owning validator, put evidence in the wrong place, or hand off stale assumptions.

The operational harness references existing authorities. It does not alter `AGENTS.md` and does not replace any domain contract.

## Start here

1. Read `AGENTS.md`.
2. Read root `HARNESS.md`.
3. Run:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperationalHarness.ps1
python tooling/harness/operational/Get-OperationalHarnessStatus.py --task "your task in one sentence"
```

On Linux:

```bash
python3 tests/test_operational_harness.py
python3 tooling/harness/operational/Get-OperationalHarnessStatus.py --task "your task in one sentence"
```

The status reporter is read-only. It resolves its repository root from its own tracked path, not from the caller's current directory. That deliberately avoids the failure mode where an operator starts PowerShell in their home directory and `git rev-parse --show-toplevel` returns no repository.

## Components

### Codebase map

`tooling/harness/operational/codebase-map.json` gives a compact structure overview, key directories, entrypoints, configuration files, safe validation commands, lack of a single generic build/deploy action, and known traps.

### Workflow specs

`tooling/harness/operational/workflow-registry.json` selects among:

- `task-intake` — recover truth and choose the owner before writing;
- `pre-commit-validation` — run owning checks, foundation checks, diff hygiene, and staged review;
- `failure-recovery` — preserve the first failure, repair the owning layer, and rerun;
- `handoff` — refresh branch/SHA/PR/evidence and create a continuation record.

The registry also sends cross-environment, runtime-proof, Windows launch-mode, and Pi work to their existing specialized skills.

### Artifact registry

`tooling/harness/operational/artifact-registry.json` defines four generated evidence roles:

- `operational-harness-status.json`;
- `operational-harness-report.md`;
- `operational-harness-validation-ledger.json`;
- `operational-harness-handoff.json`.

They are local operational evidence and are never tracked by default. The status generator creates a unique run directory in the operating-system temporary directory unless `--output-root` is supplied.

### Validator registry

`tooling/harness/operational/validator-registry.json` separates owning, foundation, domain, and aggregate validators. Run owning checks first. Adding a validator to the registry does not magically prove its domain; the command must actually run successfully in the applicable environment.

### Optional hook

`tooling/harness/operational/hooks/Invoke-OperationalHarnessPreCommit.ps1` is an opt-in helper. The repository does **not** install or configure it automatically. It runs the operational completeness validator and staged `git diff --check`. Operators may invoke it directly or wire it into their own local hook policy.

### Skill

`.ai/skills/operational-harness-routing/SKILL.md` is the repeatable procedure for entering the harness, choosing the owner, validating, recovering from failures, and handing off.

### Operator report

`tooling/harness/operational/Get-OperationalHarnessStatus.py` emits machine-readable status plus an English report. The report says what components exist, what is missing, the selected route for the supplied task text, current local branch/HEAD/dirty observation, validators, known traps, proof ceiling, and next command.

## Failure behavior

A failing validator is evidence, not permission to edit the test until it passes. Keep the first failing command and bounded output. Determine whether the defect is in harness structure, a registry/schema relationship, documentation, script syntax, domain logic, environment dependency, or authority. Repair only the declared owned scope. If the real blocker is credentials, a protected runtime, merge/review, live target, or unsupported topology, hand off the blocker rather than simulating a pass.

## Stacked baseline regression policy

The hosted operational workflow treats its own harness validators as strict: they must pass on the head. For broad existing repository contracts, a stacked PR is compared against its exact PR base in isolated Git worktrees. A check that passes on the base and fails on the head is a blocking regression. A check that already fails on the base and still fails on the head is reported as `INHERITED-BASELINE`: it remains visible debt, but this harness lane does not mutate unrelated files just to absorb it. A base failure repaired by the head is reported separately.

This distinction is not a waiver. It prevents a focused harness PR from claiming that inherited failures are green while also preventing forbidden-scope repairs from being smuggled into the harness commit.

## Validation

Focused:

```text
python3 tests/test_operational_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-OperationalHarness.ps1
git diff --check
```

Hosted `.github/workflows/operational-harness.yml` additionally compares a broad set of existing dependency-light Python/Bash contracts on Linux and existing PowerShell foundation/domain contracts on Windows against the exact PR base. Head-only failures block. Inherited base failures remain visible as baseline debt. This is regression evidence for repository contracts, not live runtime proof.

## Rollback

The harness is isolated under `tooling/harness/operational/`, plus its skill, validators, CI file, root `HARNESS.md`, and this guide. Reverting the harness commit removes the operational layer without rewriting the underlying domain harnesses. Do not use `git reset --hard`, `git clean`, or history rewrite as a routine rollback.

## Proof ceiling

Passing the operational harness proves that the tracked operational components are present, internally cross-referenced, parseable, safely routed, and capable of producing read-only local status/report/handoff artifacts. It does not prove product runtime, AgentSwitchboard orchestration on another environment, provider authentication, SSH/tmux continuity, deployment, or operator acceptance.
