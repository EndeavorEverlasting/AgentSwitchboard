---
id: operator-command-envelope
version: 1.0.0
status: canonical
---

# Operator Command Envelope

## Trigger

Use this skill whenever an agent provides a copy/paste shell command, an exact next command, a workstation recovery command, a terminal handoff, or an operator-facing code block.

## Read first

1. `tooling/profiles/windows/harness/technician-live-cert/operator-command-contract.json`
2. `tooling/profiles/windows/harness/technician-live-cert/fixtures/operator-command-contamination.fixture.json`
3. `tooling/profiles/windows/harness/technician-live-cert/artifact-registry.json`
4. The selected workflow and the exact shell in which the operator will run the command

## Inputs

- exact target shell;
- repository and branch or detached-worktree boundary;
- fixed ref and commit SHA when known;
- command owner;
- dependency or blocker being advanced;
- expected artifact or observable proof;
- completion gate;
- candidate handoff file when one exists.

## Procedure

1. Prefer a repository-owned CMD, PS1, or other tracked launcher over a long inline bootstrap.
2. Name the shell outside the code fence.
3. Put executable input only inside the code fence.
4. Begin at the first executable character. Never include a PowerShell prompt, Command Prompt prompt, WSL prompt, tmux prompt, or continuation prompt.
5. Never copy the operator's current prompt into the command, even when repeating their terminal context.
6. Never mix stdout, stderr, stack traces, `At line` diagnostics, category metadata, expected output, or explanatory prose into the executable block.
7. Keep the owner, dependency, artifact, and completion gate outside the block.
8. Carry known repository, ref, SHA, and path values into the command. Leave only genuinely unknown runtime values explicit.
9. When a stale checkout lacks the needed entrypoint, prefer an existing tracked bootstrap or create an owned harness artifact before handoff. Do not improvise a transcript-shaped command.
10. Validate registered command surfaces and any candidate handoff file with `scripts/Test-OperatorCommandEnvelope.ps1`.
11. When a violation is found, publish the sanitized command from the report, not the contaminated original.
12. Treat a new operator contamination incident as a field-failure repair: preserve evidence privately, add a minimized synthetic fixture, repair the harness, and rerun the exact validator.

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
```

Validate a draft handoff artifact with:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1 -CandidatePath '<handoff-file>'
```

## Outputs

- prompt-free executable command;
- owner and dependency statement;
- expected artifact and completion gate;
- untracked JSON and Markdown envelope report;
- minimized synthetic fixture when a new contamination class is discovered.

## Forbidden

- shell prompts inside executable blocks;
- duplicated prompts;
- continuation prompts;
- terminal transcripts presented as commands;
- PowerShell error headers or metadata inside executable blocks;
- explanatory labels such as `Run:` inside the block;
- private usernames, hostnames, credentials, or production output in fixtures;
- claiming workstation success from envelope validation;
- asking the operator to reconstruct or edit a long command manually.

## Proof ceiling

This skill and its validator prove command-presentation hygiene for registered surfaces and supplied candidate files. They do not prove that the command executes successfully on the target workstation.
