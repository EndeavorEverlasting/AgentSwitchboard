---
id: end-to-end-runtime-validation
version: 1.1.0
status: canonical
---

# End-to-End Runtime Validation

## Trigger

Use when an operator-facing installer, repair, launcher, profile, terminal workflow, cross-process integration, or automation must be proven through the same command and environment chain the operator will use. Select this skill when success crosses one or more boundaries such as Command Prompt, PowerShell, `pwsh`, `wsl.exe`, a named WSL distribution, Bash, tmux, WezTerm, a TUI, a GUI, a provider adapter, browser authentication, or another child process.

This skill is narrower than `runtime-proof`: `runtime-proof` establishes observed behavior in one authorized runtime, while this skill proves the complete operator path, boundary by boundary, through final effective-state readback.

## Inputs

- exact operator command, including working directory and shell;
- ordered runtime boundary chain and named environment identities;
- expected user-visible behavior and machine-readable acceptance criteria;
- preconditions, required tools, versions, configuration paths, active sessions, and command-resolution expectations in each shell;
- authorized mutations, forbidden mutations, and evidence root;
- required interactive input, browser handoff, callback, timeout, and cancellation behavior;
- rollback, backup, cleanup, and idempotence requirements;
- lower-level parser, static, unit, contract, and dry-run validators;
- wall-clock, retry, and process-tree termination limits.

## Procedure

1. **Freeze the operator path.** Record the exact command the operator will run, current repository or configuration identity, exact shell, host platform, named WSL distribution when applicable, and the expected terminal result. Do not substitute a developer-only invocation for the operator path.
2. **Prove the lower floors.** Run parser, lint, schema, unit, contract, and plan or dry-run checks before the end-to-end mutation. A lower-floor failure blocks runtime execution.
3. **Enumerate every boundary.** Write the chain explicitly, for example: `Command Prompt -> pulled CMD -> pwsh child -> wsl.exe -> Ubuntu -> bash -lc -> tmux server -> WezTerm -> provider browser handoff`. Name the command, expected input, expected output, timeout, and failure identity for each stage.
4. **Preflight boundaries independently.** Verify command resolution in the exact promised shell, version, distribution identity, quoting, filesystem translation, permissions, required files, tmux server or session state, browser prerequisites, and rollback assets before mutation. Presence in WSL does not prove PowerShell readiness; use an explicit `wsl.exe` invocation or a repo-owned shim when the operator is promised a direct PowerShell command.
5. **Separate optional stages.** An optional agent, provider, installer, or browser-auth flow may not block a narrower explicitly requested core path. Optional surfaces require their own mode, timeout, stage result, and proof ceiling.
6. **Model interactive input.** A required Enter, newline, confirmation, browser launch, or callback is part of the deterministic contract. Inject the declared input exactly once, preserve child output, bound the wait, and classify the exact handoff stage when it fails. Do not make Ctrl+C, `/debug`, or manual reconstruction the normal recovery path.
7. **Execute the exact operator command once.** Use bounded waits and terminate owned child process trees on timeout. Do not introduce a blind retry or silently change parameters after failure.
8. **Preserve stage output.** Capture stdout, stderr, exit code, start and finish times, and the exact command for every child boundary. Never collapse a failed child process into only `exit code 1`, and never discard the child output before constructing the operator report.
9. **Read back effective state.** Validate the consumer-visible result rather than configuration intent. Examples include `Get-Command` in the promised PowerShell process, exact executable or shim target, WSL `command -v`, `wezterm ls-fonts`, a clean WezTerm configuration load, `tmux show-options`, session and pane state, generated artifact identity, or the application’s own status interface.
10. **Observe the user experience.** Confirm the expected terminal, TUI, GUI, window, pane, browser, status bar, launcher, or artifact outcome. Absence of an error is not sufficient when the requested behavior is visual or interactive.
11. **Prove idempotence and rollback.** Re-run only when the contract requires an idempotence check and the first run reached a known safe state. Verify that a second run does not duplicate loaders, hooks, PATH entries, shims, sessions, windows, or configuration entries. Exercise rollback or restore validation when the change can impair startup or operator access.
12. **Classify and repair in the same context.** Mark each stage `pass`, `fail`, `blocked`, or `skipped-with-reason`. Observed live failure outranks lower-floor success for the same operator path. Preserve independently passing stages, repair the deterministic failure in the same branch and evidence chain, then rerun the failed stage and the complete operator path.
13. **Emit the handoff.** Report the exact failed or successful stage, command, exit code, bounded stdout and stderr paths or excerpts, effective-state readback, required input result, rollback state, idempotence result, final proof level, remaining risks, and one exact next command.

## Outputs

- `end-to-end-run-context.json` with host, shell, boundary chain, limits, and proof ceiling;
- `end-to-end-stage-ledger.json` with one record per boundary;
- bounded stdout and stderr artifacts for each stage;
- shell-specific command-resolution and effective PATH or shim evidence;
- interactive-input and browser-handoff result;
- before-and-after effective-state evidence;
- rollback and idempotence result;
- English operator report identifying what worked, what failed, what remains unproved, and the next command;
- compressed final handoff that requires the receiver to re-inspect current state.

Generated evidence is local-operational and untracked unless deliberately minimized and reviewed as a public fixture.

## Deterministic validation

End-to-end success requires all mandatory stages to pass, the exact operator command to complete, every promised command to resolve in the promised shell, and the requested effective state to be observed. Process creation, command acknowledgement, configuration-file presence, command presence in another shell, a zero parent exit code, or a successful lower-level validator is insufficient by itself.

For a nested child failure, the stage ledger must retain the child command, exit code, stdout, stderr, boundary identity, required input state, and timeout result. A report that says only `tmux verification failed with exit code 1` is incomplete evidence and must not be presented as a diagnosable operator handoff.

Validation order is:

1. parser, schema, lint, and static checks;
2. focused unit and contract checks;
3. plan or dry-run behavior;
4. independent command-resolution and boundary preflights;
5. exact operator invocation;
6. interactive-input and browser-handoff observation when applicable;
7. effective-state and user-experience readback;
8. idempotence and rollback checks when required;
9. broader safe repository validators;
10. clean-state, diff-hygiene, commit, push, and PR evidence for a writing sprint.

## Forbidden scope

- No runtime success claim from static inspection, CI alone, configuration intent, file existence, command presence in another shell, or parent exit code alone.
- No suppression, truncation without disclosure, or replacement of child stderr with a generic exception.
- No blind retry, unbounded wait, orphaned child process, or automatic expansion to another host, distribution, profile, provider, account, or live target.
- No optional agent or browser-auth stage blocking an explicitly narrower requested core path.
- No mutation of unowned configuration, sessions, repositories, credentials, customer data, or default branches.
- No manual operator workaround presented as proof that the automated path works.
- No destructive rollback or cleanup without explicit authority and an identified backup.

## Stop and escalate

Stop when the exact environment cannot be identified, a lower floor fails, rollback is missing, a boundary cannot preserve diagnostics, the observed state contradicts the expected state, the process tree cannot be bounded, required interactive input cannot be represented safely, permissions or credentials would be exposed, a second run would enter unknown partial state, or repair attempts reach their declared limit.

Escalate with the last known safe state, exact failed stage, command, exit code, stdout and stderr evidence, required-input result, rollback status, and one safe diagnostic command. Do not ask the operator to rerun an opaque failing script merely to recover evidence the script should have retained.
