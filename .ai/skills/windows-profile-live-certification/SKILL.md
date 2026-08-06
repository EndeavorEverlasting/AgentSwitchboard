---
id: windows-profile-live-certification
version: 1.3.0
status: canonical
---

# Windows Profile Live Certification

## Trigger

`profile.workstation-certification-request`, explicit live-certification invocation, an operator report that the technician pull/setup/launch path failed, hung, false-passed, contradicted static or CI evidence, or any handoff that contains a shell prompt, duplicated prompt, continuation prompt, transcript, or PowerShell error output.

## Read first

1. `tooling/profiles/windows/harness/technician-live-cert/manifest.json`
2. `tooling/profiles/windows/harness/technician-live-cert/codebase-map.json`
3. `tooling/profiles/windows/harness/technician-live-cert/workflows/maintenance.workflow.json`
4. `tooling/profiles/windows/harness/technician-live-cert/workflows/field-failure-repair.workflow.json`
5. `tooling/profiles/windows/harness/technician-live-cert/artifact-registry.json`
6. `tooling/profiles/windows/harness/technician-live-cert/operator-command-contract.json`
7. `.ai/skills/operator-command-envelope/SKILL.md`
8. `tooling/profiles/windows/technician-live-cert/technician-live-cert.manifest.json`
9. The failed run evidence and exact operator output

## Inputs

- Exact AgentSwitchboard commit SHA
- Exact installed launcher path and manifest hash
- Requested mode: open-or-activate or new-instance
- Exact operator command and exact operator shell
- Prompt-free candidate command separated from terminal output
- WSL distribution name
- Expected tmux identity
- Expected command-resolution surface for Windows and WSL tools
- Evidence root path
- Timeout seconds
- Any required interactive input or browser handoff
- Current branch/worktree ownership and dirty-state evidence
- Exact failed stage, child exit identity, and local evidence path when repairing a field failure

## Procedure

1. Freeze the run context: repo, commit, launcher path, manifest hash, mode, operator command, exact operator shell, distribution, tmux identity, evidence root, timeout, rollback boundary, proof ceiling.
2. Preserve unrelated work. One branch or worktree has one writer; use an isolated worktree when the active checkout contains another sprint.
3. Separate executable input from the operator's current prompt, continuation prompt, stdout, stderr, stack trace, and error metadata. Select `.ai/skills/operator-command-envelope/SKILL.md` before publishing or rerunning a command.
4. Prefer a repository-owned CMD or PS1 entrypoint over a long inline bootstrap. Name the shell outside the code fence and begin the block with the first executable character.
5. Capture before snapshot: desktop shortcut target and arguments, WezTerm frontend processes and top-level windows, tmux sessions, tmux clients, installed launcher and manifest hashes.
6. Preflight every command in the shell where the operator was told to run it. A WSL-only command does not count as PowerShell-ready unless the contract explicitly instructs `wsl.exe` or installs a repo-owned shim and verifies it from PowerShell.
7. Treat optional agents separately from the requested core path. Hermes, another optional provider, or browser authentication may not block a requested WezTerm -> WSL -> tmux -> AGY/OpenCode setup unless that optional surface was explicitly selected.
8. For a browser handoff that waits for Enter, model the newline as required deterministic input. Supply it once, bound the wait, preserve stdout and stderr, and fail with the exact stage when the browser or callback does not complete.
9. Execute the exact prompt-free operator command in the requested mode.
10. Capture after snapshot: same fields as before.
11. Compare before and after: new windows, new tmux sessions, new tmux clients, command resolution, tool versions, and effective PATH or shim state.
12. Classify result: opened, activated, new-instance-opened, duplicate-detected, blocked, or failed.
13. Emit stage ledger, mode result, duplicate report, English operator report, and final handoff.
14. When Live mode: require user-visible observation fields. Process handles and tmux session existence alone are insufficient.
15. Observed live failure outranks static and CI success for the same operator path. Record a sanitized failure classification, repair the same evidence chain, and rerun the exact operator command before promoting proof.
16. For a repair, identify the harness gap that allowed the defect: skipped shell, parameter-binding timing, ambiguous .NET overload, unexecuted branch, interactive pager, static token-only check, operator-command envelope gap, or proof inflation.
17. Add a deterministic guard that would have failed before field use. Run the owning validator in **Windows PowerShell 5.1** and **PowerShell 7**. A pass in one shell does not establish compatibility in the other.
18. Resolve `$PSScriptRoot` and other automatic variables in the script body, not in parameter default expressions. Force explicit .NET overloads where empty strings, characters, arrays, or `$null` could bind ambiguously.
19. Use `git --no-pager` in agent and CI commands. Validation must not depend on an interactive pager or terminal state.
20. Run `scripts/Test-OperatorCommandEnvelope.ps1` before publishing a handoff. When a draft handoff exists, pass it through `-CandidatePath`.
21. Run `scripts/Test-TechnicianLiveCertHarness.ps1` after the focused surface validator and before broader repository validation.

## Outputs

- Run context (untracked)
- Before and after snapshots (untracked)
- Stage ledger (untracked)
- Shell-specific command-resolution report (untracked)
- Mode result (untracked)
- Duplicate report (untracked)
- English operator report (untracked)
- Final prompt-free handoff (untracked)
- Operator-command envelope JSON and Markdown report (untracked)
- Harness status JSON and Markdown (untracked)
- Deliberately minimized public failure fixture only when a live failure changes repository doctrine or validation
- Tracked scoped map, workflow, registry, validator, hook, report, skill, or CI repair when the harness gap requires it

## Deterministic validation

Run in this order:

```powershell
python -m unittest tests.test_operator_command_envelope
python -m unittest tests.test_technician_live_cert_harness
python -m unittest tests.test_technician_live_cert_surface
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-OperatorCommandEnvelope.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-TechnicianLiveCertSurface.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-TechnicianLiveCertHarness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertSurface.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertHarness.ps1
git --no-pager diff --check
```

Validate a candidate handoff with:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1 -CandidatePath '<handoff-file>'
```

The harness validator must prove:

- all scoped components exist and are tracked;
- JSON contracts parse;
- generated evidence remains untracked;
- hooks remain opt-in;
- validators perform no network or target mutation;
- registered command blocks contain executable input only;
- the synthetic duplicated-prompt fixture is rejected;
- PowerShell prompt contamination is classified before it can resolve `PS` as the `Get-Process` alias;
- Windows PowerShell 5.1 and PowerShell 7 entrypoints resolve their repository root at runtime;
- P00 does not use the ambiguous `Replace([char]0, '')` overload;
- executable NUL-padded WSL output normalizes to `Ubuntu`;
- CI runs the cross-shell matrix and fixture-safe CMD surface;
- the operator guide and skill expose the exact next command and honest proof ceiling.

## Forbidden scope

- Runtime execution in CI
- Storing private hostnames, usernames, or unredacted command lines in committed fixtures
- Shell prompts, duplicated prompts, continuation prompts, transcripts, stack traces, expected output, or PowerShell error metadata inside executable command blocks
- Claiming live proof from static tests or command acknowledgement
- Treating command presence in another shell or operating-system boundary as operator-shell readiness
- Allowing an optional agent or provider to block an explicitly narrower core setup
- Blind waits or operator-only Ctrl+C/debug recovery at a known interactive boundary
- Installing hooks implicitly
- Mutating unrelated launcher or provider product code
- Process handles as visible-window proof
- tmux session existence as client-attachment proof
- Parameter defaults that depend on `$PSScriptRoot`
- Ambiguous .NET overload selection at field boundaries
- Interactive Git paging in automation
- Replacing an observed live failure with a lower static pass

## Stop and escalate

- Launcher path or hash differs from the pinned contract
- WezTerm, WSL, or tmux prerequisites are missing or unresolved in the promised shell
- AGY or OpenCode installation completes without an absolute command path and version proof
- Hermes or another browser-auth flow waits without the declared input and timeout contract
- The operator command cannot be separated safely from prompt or transcript text
- The operator command was not acknowledged
- Duplicate detection finds more than one new window per request
- Observed live behavior contradicts static or CI evidence
- Windows PowerShell 5.1 and PowerShell 7 disagree
- The exact failed command cannot be rerun safely
- Rollback fails
