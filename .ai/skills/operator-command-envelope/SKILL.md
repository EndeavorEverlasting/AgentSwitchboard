---
id: operator-command-envelope
version: 1.1.0
status: canonical
---

# Operator Command Envelope

## Deterministic trigger

Trigger ID: `operator.command-artifact`

Select this skill whenever an agent provides an operator-facing executable command, exact next command, workstation recovery command, terminal handoff, or executable code block. This skill is shell-agnostic: it owns presentation hygiene and does not own shell grammar.

When the target shell is PowerShell and delivery is interactive copy/paste, `powershell-interactive-execution` is mandatory and becomes the primary syntax-boundary owner. The two skills compose; neither substitutes for the other.

## Required inputs

- exact target shell and delivery mode;
- command artifact or candidate path;
- repository and branch/worktree boundary when applicable;
- fixed ref and commit SHA when known;
- command owner and dependency;
- expected artifact or observable proof;
- completion gate.

## Preconditions

- The artifact is intended for an operator to execute.
- The owning workflow has resolved authority and current repository/runtime state.
- A shell-specific skill is selected when the command depends on shell grammar or interactive parsing.

## Procedure

1. Prefer a repository-owned CMD, PS1, or tracked launcher over a long inline bootstrap.
2. Name the shell outside the executable block.
3. Put executable input only inside the block and begin at the first executable character.
4. Never include a PowerShell prompt, Command Prompt prompt, WSL/POSIX prompt, continuation prompt, transcript, stack trace, error metadata, expected output, or explanatory prose in executable input.
5. Keep owner, dependency, expected artifact, proof ceiling, and completion gate outside executable input.
6. Carry forward verified repository, ref, SHA, and path values; leave only genuinely unknown values explicit.
7. For interactive PowerShell, require `powershell-interactive-execution` and run both command-envelope and skill-factoring validators.
8. When a stale checkout lacks a local launcher, use the registered stale-checkout bootstrap rather than pretending the launcher exists.
9. Treat each newly observed contamination or submission-boundary failure as a fixture-backed harness repair.

## Produced outputs

- prompt-free executable command content;
- operator metadata outside executable input;
- sanitized JSON and Markdown validation reports;
- explicit shell-specific composition when required.

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

## Deterministic validation

```powershell
python -m unittest tests.test_operator_command_envelope
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-SkillFactoringContracts.ps1
```

## Forbidden conditions

- Shell prompt or terminal transcript inside executable input.
- Detached PowerShell continuation keywords presented as safe interactive commands.
- Shell-specific syntax rules duplicated here instead of delegated to their canonical owner.
- A command acknowledgement or validation pass promoted to runtime behavior proof.

## Proof ceiling

This skill proves command-presentation hygiene for registered and candidate artifacts. It does not prove shell parsing, command execution, state mutation, runtime behavior, or operator acceptance.
