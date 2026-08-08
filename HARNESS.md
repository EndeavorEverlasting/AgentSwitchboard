# AgentSwitchboard Operational Harness

Start here **after `AGENTS.md`** when you need to enter the repository without relying on remembered paths or hidden commands.

This operational harness does not replace the repository-family, environment-capability, device-profile, application, Pi, GNHF, or Windows profile harnesses. It tells you how to find and select the owner, run the right validator, preserve granted integration authority, record artifacts, recover from failures, complete safe integration, and hand off only when work truly transfers or remains blocked.

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

## Execution actor routing

Authority and actor identity are separate contracts. Having authority to perform an operation does not make `ChatGPT`, `AgentSwitchboard`, and the human `operator` interchangeable.

When the user or task contract explicitly names who must perform a repository mutation, bind that actor **before** mutation:

```powershell
python tooling/harness/operational/execution-actor-routing/Invoke-ExecutionActorRouting.py bind `
  --requested-actor agentswitchboard `
  --selected-actor agentswitchboard `
  --selection-source user-explicit `
  --task "complete validated PR integration" `
  --operation "merge PR <number> at exact head <sha>"
```

Canonical actor values are `chatgpt`, `agentswitchboard`, `operator`, and `auto`. Use `auto` only when no actor was explicitly requested, and record the selection reason. The bind command prints `BINDING_SHA256`; preserve that digest outside the mutable binding file before execution.

An explicit mismatch is a hard gate. Do not substitute a direct GitHub/ChatGPT mutation for an AgentSwitchboard-owned operation, do not make AgentSwitchboard perform work explicitly assigned to ChatGPT, and do not execute operator-owned work on the operator's behalf merely because another path is available.

After the operation, verify the actual actor against the original binding digest and supply concrete actor-owned evidence:

```powershell
python tooling/harness/operational/execution-actor-routing/Invoke-ExecutionActorRouting.py verify `
  --binding "<run-root>\execution-actor-binding.json" `
  --expected-binding-sha256 "<BINDING_SHA256 captured at bind>" `
  --actual-actor agentswitchboard `
  --evidence "<actor-owned receipt, log, PR comment, or other concrete evidence>"
```

Verification validates the complete binding and fails closed if the binding's canonical digest differs from the preserved original digest. Read `docs/harness/execution-actor-routing.md` and `.ai/skills/execution-actor-routing/SKILL.md` for failure recovery, output artifacts, validation, trust model, and proof ceiling.

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
- `tooling/harness/operational/workflow-registry.json` — deterministic routing to task intake, validation, failure recovery, handoff/integration continuation, and specialized domain skills.
- `tooling/harness/operational/artifact-registry.json` — generated evidence roles, names, generators, and proof ceilings.
- `tooling/harness/operational/validator-registry.json` — owning, foundation, domain, and aggregate checks.
- `tooling/harness/operational/workflows/` — executable workflow specifications.
- `tooling/harness/operational/execution-actor-routing/` — deterministic requested/selected/actual actor binding and verification.
- `tooling/harness/operational/opencode-prompt-handoff/` — deterministic prompt materialization plus same-artifact OpenCode preflight/execution composition.
- `.ai/skills/operational-harness-routing/SKILL.md` — scoped repeatable procedure.
- `.ai/skills/execution-actor-routing/SKILL.md` — canonical actor-selection and anti-substitution procedure.
- `.ai/skills/opencode-prompt-handoff/SKILL.md` — canonical no-recopy prompt handoff procedure.
- `docs/harness/operational-harness.md` — human operator guide.
- `docs/harness/execution-actor-routing.md` — human execution-actor operator guide.
- `docs/harness/opencode-prompt-handoff.md` — human prompt-handoff operator guide.
- `scripts/Test-OperationalHarness.ps1`, `tests/test_operational_harness.py`, and `tests/test_operational_merge_authority.py` — completeness and authority-continuation contracts.
- `scripts/Test-ExecutionActorRoutingHarness.ps1` and `tests/test_execution_actor_routing_harness.py` — actor-routing completeness and anti-substitution contracts.
- `scripts/Test-OpenCodePromptHandoffHarness.ps1` and `tests/test_opencode_prompt_handoff_harness.py` — prompt-handoff completeness and anti-regression contracts.
- `.github/workflows/operational-harness.yml` — Windows/Linux hosted harness gate.
- `.github/workflows/operational-merge-authority.yml` — Windows/Linux authority-continuation regression gate.
- `.github/workflows/execution-actor-routing-harness.yml` — Windows/Linux actor-routing harness gate.
- `.github/workflows/opencode-prompt-handoff-harness.yml` — Windows/Linux prompt-handoff harness gate.
- `tooling/harness/operational/hooks/Invoke-OperationalHarnessPreCommit.ps1` — optional pre-commit helper. It is never installed implicitly.
- `tooling/harness/operational/hooks/Invoke-OperationalHarnessPrePush.ps1` — optional pre-push helper. It requires an exact base instead of guessing the push range.

## Workflow choice

Use `task-intake` when entering fresh or when repository/branch ownership is uncertain.

Use `pre-commit-validation` after implementation is complete but before committing.

Use `failure-recovery` when a validator, CI job, schema, fixture, or contract fails.

Use `handoff` after a complete gate to either finish already-authorized safe integration or transfer exact branch/proof state when a real dependency remains unresolved.

Explicit execution-actor requests and any operation whose proof depends on who performs it must route through `.ai/skills/execution-actor-routing/SKILL.md` **before mutation**. The status reporter consumes the actor route's registered `routingNeedles` so explicit phrases such as “have AgentSwitchboard” and “AgentSwitchboard must” produce that specialized route.

OpenCode clipboard prompt intake, `PlanOnly` preflight, preflight-to-execution prompt identity, or any workflow that would require recopying the same prompt must route through `.ai/skills/opencode-prompt-handoff/SKILL.md` and its tracked harness runner.

Cross-environment work must route through `.ai/skills/environment-capability-routing/SKILL.md`. Operator-visible runtime proof must route through `.ai/skills/end-to-end-runtime-validation/SKILL.md`. Those specialized owners outrank generic operational convenience.

## Safety and proof

This harness may inspect repository files, local Git identity/state, and registered validators. It may generate local status/report/handoff artifacts. It does not authorize governance edits, product mutation, provider access, credentials, deployment, live-target mutation, destructive Git, or proof promotion.

Merge authority may come from the current task or an explicit standing repository-owner directive. The harness may **record and preserve** that authority; it may not invent it. When authority is recorded and the validated in-scope merge remains safe, the current harness agent owns continuation through the exact-head-pinned merge **unless an explicit execution-actor binding assigns that operation to another actor**.

Actor routing does not create authority. It records which actor is selected under already-valid authority and prevents silent substitution. A verified actor receipt proves actor identity plus continuity with the independently preserved binding digest; the underlying operation still requires its owning evidence. The digest is an integrity anchor, not a hostile-host signature.

A generated merge command without recorded authority is an owner-gated next action. A generated merge command with recorded authority is an executable current-agent action, but it is still not merge proof until the selected actor's evidence shows a successful merge result.

A green operational harness means the repository has a coherent **operational control surface**. It does not mean the application, agents, providers, remote machines, or user workflow have run successfully.
