# Command-Delivery Operational Harness

## Purpose

This harness lets a fresh agent inspect command-delivery ownership, select the right workflow, run deterministic validators, avoid known shell-boundary traps, produce local artifacts, and hand off without relying on chat memory.

The original field defect was a PowerShell assignment submitted as an `if` block, then a separate `elseif`, then a separate `else`. A later field defect proved a second boundary: the inner PowerShell validator could be correct while the CMD wrapper corrupted a quoted `%~dp0` path before PowerShell received it.

## Start here

1. Read `AGENTS.md`.
2. Read `tooling/skills/harness/command-delivery/codebase-map.json`.
3. Read `tooling/skills/harness/command-delivery/manifest.json`.
4. Select one workflow under `tooling/skills/harness/command-delivery/workflows/`.
5. Select the deterministic primary skill through `skill-factoring.registry.json`.
6. Run `tooling/skills/Get-CommandDeliveryHarnessStatus.ps1`.
7. Run the validation order in the manifest before commit or handoff.

## Components

- **Codebase map:** focused directories, entrypoints, commands, and known traps.
- **Workflow specs:** task intake, validation before commit, failure recovery, and handoff.
- **Skill and capability registries:** one primary owner plus explicit composed capabilities.
- **Artifact registry:** local roots, names, generators, sensitivity, and proof ceilings.
- **Validators:** routing, schema, syntax, completeness, documentation, and the actual CMD outer entrypoint.
- **Hooks:** opt-in pre-commit and pre-push checks; never installed implicitly.
- **Scoped skills:** `powershell-interactive-execution`, `operator-command-envelope`, and composed workflow owners.
- **Operator reports:** status JSON, English Markdown, compact handoff JSON, and exact-entrypoint proof.

## Deterministic routing

Routing produces exactly one primary skill. Required composed skills may be added without becoming competing primary owners.

A PowerShell operator command routes primarily to `powershell-interactive-execution` and requires `operator-command-envelope`. A Bash operator command routes to `operator-command-envelope`. A GNHF PowerShell artifact remains primarily owned by `gnhf-prompt-compilation` and composes both command-delivery owners.

## Interactive PowerShell boundary

Allowed:

- guard clauses with no continuation dependency;
- one physical-line `if/elseif/else` or `try/catch/finally`;
- one outer `& { ... }` script block with every continuation attached to the preceding brace;
- structurally complete multiline compound syntax in a saved `.ps1` file.

Rejected:

- a later snippet beginning with `elseif`, `else`, `catch`, or `finally`;
- a continuation keyword starting on a new physical line in an interactive artifact;
- a multiline interactive compound statement without one outer atomic script block;
- an unclosed brace, parenthesis, bracket, quote, here-string, block comment, or trailing backtick;
- one compound statement divided across multiple code fences or submissions;
- an unterminated Markdown fence.

## CMD-to-PowerShell path boundary

A CMD launcher must not pass quoted `%~dp0` directly to a native child process. `%~dp0` ends with a directory separator, which can contaminate the closing quote during native argument parsing. Normalize the launcher root to a fully qualified path without a trailing separator, then pass that normalized variable.

The canonical form is:

```cmd
for %%I in ("%~dp0.") do set "ROOT=%%~fI"
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\Test-SkillFactoringContracts.ps1" -RootPath "%ROOT%" %*
```

An inner PS1 pass does not prove the outer CMD entrypoint. The actual CMD must execute from a representative path containing spaces and produce the canonical report before launcher success is claimed.

## Workflows

- `task-intake.workflow.json` — inspect law and state, choose isolation, route one primary skill, and create initial status.
- `validation-before-commit.workflow.json` — run unit, completeness, exact-entrypoint, documentation, hook, and diff checks.
- `failure-recovery.workflow.json` — preserve evidence, classify the failed boundary, repair the canonical owner, add regression proof, and rerun the outer entrypoint.
- `handoff.workflow.json` — emit current status and handoff artifacts with one exact next command.

## Entrypoints

```cmd
Test-SkillFactoringContracts.cmd
```

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-CommandDeliveryHarnessCompleteness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-CommandDeliveryEntrypoint.ps1
pwsh -NoLogo -NoProfile -File tooling/skills/Get-CommandDeliveryHarnessStatus.ps1
```

Validate a proposed Markdown handoff:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-SkillFactoringContracts.ps1 -CandidatePath '.\handoff.md' -CandidateDeliveryMode interactive-copy-paste
```

## Hooks

The hooks are opt-in and are never installed automatically:

```powershell
pwsh -NoLogo -NoProfile -File tooling/skills/hooks/Invoke-CommandDeliveryHarnessPreCommit.ps1
pwsh -NoLogo -NoProfile -File tooling/skills/hooks/Invoke-CommandDeliveryHarnessPrePush.ps1
```

## Artifacts

The canonical artifact registry is `tooling/skills/harness/command-delivery/artifact-registry.json`.

Generated evidence remains outside tracked authority:

- `%LOCALAPPDATA%\AgentSwitchboard\skill-factoring\`
- `%LOCALAPPDATA%\AgentSwitchboard\command-delivery-harness\`
- `%TEMP%\AgentSwitchboard\command-delivery-entrypoint\<run-id>\`

## Validation

```powershell
python -m unittest tests.test_skill_factoring_contracts tests.test_command_delivery_harness
pwsh -NoLogo -NoProfile -File scripts/Test-CommandDeliveryHarnessCompleteness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-SkillFactoringContracts.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-SkillFactoringContracts.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-CommandDeliveryEntrypoint.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git --no-pager diff --check
```

## Failure handling

Do not substitute a direct PS1 run for a failed CMD proof. A direct invocation may diagnose the inner layer, but completion requires repairing and rerunning the actual outer launcher. Preserve the failed worktree until its evidence has been classified.

## Proof ceiling

A passing completeness result proves tracked harness structure and deterministic contracts. A passing entrypoint result additionally proves one exact CMD-to-PowerShell execution from one observed spaced path. Neither proves arbitrary operator commands, target mutation, provider behavior, deployment, or operator acceptance.
