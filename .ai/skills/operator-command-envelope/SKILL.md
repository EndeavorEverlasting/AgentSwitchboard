---
id: operator-command-envelope
version: 1.1.0
status: canonical
---

# Operator Command Envelope

## Trigger

Trigger ID: `operator.command-artifact`

Use this skill whenever an agent provides a copy/paste shell command, an exact next command, a workstation recovery command, a terminal handoff, or an operator-facing executable code block. This skill is shell-agnostic: it owns presentation hygiene and does not own shell grammar.

When the target shell is PowerShell and delivery is interactive copy/paste, `powershell-interactive-execution` is mandatory and becomes the primary syntax-boundary owner. The two skills compose; neither substitutes for the other.

## Read first

1. `tooling/profiles/windows/harness/technician-live-cert/operator-command-contract.json`
2. `tooling/profiles/windows/harness/technician-live-cert/fixtures/operator-command-contamination.fixture.json`
3. `tooling/profiles/windows/harness/technician-live-cert/artifact-registry.json`
4. `tooling/skills/harness/command-delivery/skill-factoring.registry.json`
5. `.ai/skills/powershell-interactive-execution/SKILL.md` when the target is interactive PowerShell
6. The selected workflow and the exact shell and delivery mode in which the operator will run the command

## Inputs

- exact target shell and delivery mode;
- repository and branch or detached-worktree boundary;
- fixed ref and commit SHA when known;
- command owner;
- dependency or blocker being advanced;
- expected artifact or observable proof;
- completion gate;
- candidate handoff file when one exists.

## Preconditions

- The artifact is intended for an operator to execute.
- The owning workflow has resolved authority and current repository/runtime state.
- A shell-specific skill is selected when the command depends on shell grammar or interactive parsing.

## Procedure

1. Prefer a repository-owned CMD, PS1, or other tracked launcher over a long inline bootstrap.
2. Name the shell outside the code fence.
3. Put executable input only inside the code fence.
4. Begin at the first executable character. Never include a PowerShell prompt, Command Prompt prompt, WSL prompt, tmux prompt, or continuation prompt.
5. Never copy the operator's current prompt into the command, even when repeating their terminal context.
6. Never mix stdout, stderr, stack traces, `At line` diagnostics, category metadata, expected output, or explanatory prose into the executable block.
7. Keep the owner, dependency, expected artifact, and completion gate outside the block.
8. Carry known repository, ref, SHA, and path values into the command. Leave only genuinely unknown runtime values explicit.
9. For interactive PowerShell, require `powershell-interactive-execution`; validate syntax-unit boundaries in addition to this envelope.
10. When a stale checkout lacks the needed entrypoint, prefer the registered stale-checkout bootstrap. Do not pretend a missing local launcher exists or improvise a transcript-shaped command.
11. Validate registered command surfaces and any candidate handoff file with `scripts/Test-OperatorCommandEnvelope.ps1`.
12. Validate interactive PowerShell candidates with `scripts/Test-SkillFactoringContracts.ps1`.
13. When a violation is found, publish the sanitized command from the report, not the contaminated original.
14. Treat a new contamination or submission-boundary incident as a field-failure repair: preserve evidence privately, add a minimized synthetic fixture, repair the harness, and rerun the owning validators.

## Required output shape

State the shell, owner, dependency, expected artifact, and completion gate in prose. Then provide exactly one prompt-free executable block.

```powershell
& '.\Validate-Technician-ExactHead.cmd' 'C:\Work\AgentSwitchBoard-Live' 'refs/heads/main' '<verified-sha>' ready
```

Do not put a rendered shell prompt before that command. Do not append terminal output after it in the same block.

## Deterministic validation

```powershell
python -m unittest tests.test_operator_command_envelope
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-OperatorCommandEnvelope.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1
python -m unittest tests.test_skill_factoring_contracts
pwsh -NoLogo -NoProfile -File scripts/Test-SkillFactoringContracts.ps1
```

Validate a draft handoff artifact with both relevant owners:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1 -CandidatePath '<handoff-file>'
pwsh -NoLogo -NoProfile -File scripts/Test-SkillFactoringContracts.ps1 -CandidatePath '<handoff-file>' -CandidateDeliveryMode interactive-copy-paste
```

## Outputs

- prompt-free executable command;
- owner and dependency statement;
- expected artifact and completion gate;
- explicit shell-specific composition when required;
- untracked JSON and Markdown validation reports;
- minimized synthetic fixture when a new contamination class is discovered.

## Guardrails

- This skill does not own shell grammar, `if`/`else` syntax, or interactive parse boundaries.
- PowerShell interactive syntax belongs only to `powershell-interactive-execution`.
- Runtime behavior and proof belong to the owning runtime skill or workflow.
- Candidate-derived command text is not persisted unsanitized.

## Owning files

- `.ai/skills/operator-command-envelope/SKILL.md`
- `tooling/profiles/windows/harness/technician-live-cert/operator-command-contract.json`
- `scripts/Test-OperatorCommandEnvelope.ps1`
- `tests/test_operator_command_envelope.py`
- `tooling/skills/harness/command-delivery/skill-factoring.registry.json`

## Forbidden

- shell prompts inside executable blocks;
- duplicated prompts;
- continuation prompts;
- terminal transcripts presented as commands;
- PowerShell error headers or metadata inside executable blocks;
- explanatory labels such as `Run:` inside the block;
- detached PowerShell continuation keywords presented as safe interactive commands;
- shell-specific syntax rules duplicated here instead of delegated to their canonical owner;
- private usernames, hostnames, credentials, or production output in fixtures;
- claiming workstation success from envelope validation;
- asking the operator to reconstruct or edit a long command manually.

## Proof ceiling

This skill and its validator prove command-presentation hygiene for registered surfaces and supplied candidate files. They do not prove shell parsing, command execution, state mutation, runtime behavior, or operator acceptance.
