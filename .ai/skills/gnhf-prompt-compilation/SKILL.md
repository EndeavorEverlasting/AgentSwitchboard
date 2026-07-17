---
id: gnhf-prompt-compilation
version: 1.0.0
status: canonical
---

# Good Night, Have Fun Prompt Compilation

## Trigger

Use when the repository owner explicitly asks for a **Good Night, Have Fun prompt**, **GNHF prompt**, or asks to **compile a sprint for Good Night, Have Fun**.

This trigger is literal and takes precedence over generic bounded-sprint prompt writing. The requested artifact is a copy-ready GNHF launch command, not a sprint map, launch pack, plan, essay, or ordinary agent prompt.

## Inputs

- one target repository or repository path;
- one bounded sprint objective;
- preferred agent or verified agent launch form;
- execution domain and shell, normally PowerShell on Windows;
- run profile: `SMOKE`, `NAP`, `OVERNIGHT`, or `EXTENDED`;
- exactly one Git execution mode: worktree or current branch;
- iteration cap and token cap;
- positive observable stop condition;
- owned scope, forbidden scope, dependencies, expected tracked deliverable, validation, and proof ceiling.

When agent spawnability is not proven in the intended execution domain, compile the bounded spawnability probe before compiling the repository sprint.

## Procedure

1. Produce an executable PowerShell command beginning with:

   ```powershell
   gnhf `
   ```

2. Include all mandatory runtime controls:

   ```text
   --agent
   exactly one of --worktree or --current-branch
   --max-iterations
   --max-tokens
   --prevent-sleep on
   --stop-when
   ```

3. Default to `--worktree`. Do not include `--push` unless the repository owner explicitly authorizes it for that exact run.
4. Use bounded profiles:
   - `SMOKE`: 1-2 iterations;
   - `NAP`: 3-5 iterations;
   - `OVERNIGHT`: 6-10 iterations;
   - `EXTENDED`: 10-15 iterations.
5. Never compile an unlimited unattended run. Every command requires both iteration and token caps.
6. Write a **positive, observable** `--stop-when` condition describing the delivered state. Do not use a vague instruction such as “when done.”
7. Place one quoted objective block after the flags. The block must contain, in compact form:
   - `Repo` or `Run from`;
   - `Sprint`;
   - `Lane`;
   - dependencies or prerequisites;
   - owned scope;
   - forbidden scope;
   - one narrow objective;
   - ordered execution loop;
   - repeated no-progress rule;
   - stop conditions;
   - required tracked deliverable or exact blocker report;
   - validation commands or canonical proof command;
   - commit requirement;
   - final report requirements;
   - proof ceiling;
   - final `git status --short` review.
8. Run one repository per GNHF process. Do not compile a multi-repository objective into one command.
9. Require a tracked local deliverable, normally a commit ahead of the base. Process exit code zero alone is not delivery proof.
10. Classify spawn, quota, authentication, network, timeout, malformed output, and terminal/backend failures as operational failures. They do not authorize silent fallback or a success claim.
11. Preserve interrupted worktrees, branches, logs, notes, and review commands. Do not instruct GNHF to erase unknown partial state.
12. Output the copy-ready launch command directly. Add explanation only when the owner explicitly asks for explanation.

Canonical command shape:

```powershell
gnhf `
  --agent "<verified-agent>" `
  --worktree `
  --max-iterations <bounded-count> `
  --max-tokens <bounded-count> `
  --prevent-sleep on `
  --stop-when "<positive observable completion condition>" `
  "Repo: <one repository>

Sprint: <one bounded sprint>
Lane: <one lane>

Dependencies:
- <required floor>

Owned scope:
- <owned paths or behavior>

Forbidden scope:
- <explicit exclusions>

Objective:
<one narrow tracked outcome>

Execution loop:
1. Inspect the minimum repository evidence required for safety.
2. Make the smallest useful tracked change.
3. Add or update deterministic enforcement.
4. Run targeted validation.
5. Commit coherent progress.
6. Stop when the observable completion condition is true.

No-progress rule:
Stop after repeated iterations produce no tracked progress. Preserve evidence and report the blocker.

Required deliverable:
- <commit or exact blocker artifact>

Validation:
- <canonical proof command>

Final report:
- files changed
- commit SHA
- validation actually run
- skipped checks
- proof level and ceiling
- final git status --short

Do not push, merge, deploy, authenticate, or mutate live or personal state unless this exact sprint explicitly authorizes it."
```

## Outputs

- one copy-ready PowerShell `gnhf` launch command;
- one bounded repository sprint per process;
- explicit caps, stop condition, tracked deliverable, validation, proof ceiling, and recovery behavior;
- a spawnability probe instead of a sprint command when the intended agent cannot yet be proven launchable.

## Deterministic validation

A valid compiled prompt must satisfy all of these checks:

- begins with `gnhf` rather than prose about GNHF;
- includes `--agent`;
- includes exactly one of `--worktree` or `--current-branch`;
- includes both `--max-iterations` and `--max-tokens`;
- includes `--prevent-sleep on`;
- includes a positive observable `--stop-when` value;
- targets one repository;
- contains owned and forbidden scope;
- contains repeated no-progress and operational-failure handling;
- requires a tracked deliverable or exact blocker report;
- contains validation and a proof ceiling;
- does not include automatic push, merge, deployment, authentication, or live mutation by default;
- is not a sprint map, multi-chat launch pack, plan-only response, or generic prompt template.

## Forbidden scope

- No prose-only substitute for the executable launch command.
- No unlimited unattended command.
- No missing token or iteration cap.
- No default `--current-branch` or `--push` posture.
- No multi-repository process.
- No automatic push, merge, deployment, release, provider authentication, secret access, or live/personal-state mutation.
- No claim that configured stop text or process exit zero proves delivery.
- No conversion of a GNHF prompt request into a sprint map or repository-intake essay.

## Stop and escalate

Stop and request only the smallest missing fact when a bounded command cannot be produced safely, such as a missing repository or objective.

Compile a spawnability probe instead of repository work when the exact agent launch form is unknown or unverified in the intended execution domain.

Stop with an explicit blocker when the requested run would require unlimited execution, destructive Git, unapproved push/merge/deploy, credentials, live-target mutation, or multiple repositories in one process.