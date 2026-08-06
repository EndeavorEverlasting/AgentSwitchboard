# Technician Live-Cert Operational Harness

This scoped harness protects the Windows technician P00-P09 live-certification surface, operator command handoffs, and owned repair workflows without replacing product behavior or the repository governance contract.

## Mission

A fresh agent must be able to locate the live-cert implementation, choose the maintenance or field-failure workflow, identify generated evidence, run the correct validators in every required shell, avoid known Windows/PowerShell and terminal-copy traps, produce English status reports, and hand the sprint off with an exact prompt-free next command.

The canonical machine-readable entrypoint is:

`tooling/profiles/windows/harness/technician-live-cert/manifest.json`

The canonical operator-command envelope is:

`tooling/profiles/windows/harness/technician-live-cert/operator-command-contract.json`

## What is working

- P00-P08 remain the required core sequence; P09 Hermes remains optional.
- Repository-owned CMD files dispatch stages and repairs and propagate nonzero exit codes.
- WSL/Ubuntu repair owns machine-wide feature activation, reboot continuation, Ubuntu registration, and initialization.
- Generated run evidence remains under `%LOCALAPPDATA%\AgentSwitchboard` and is not tracked.
- The focused harness has a codebase map, maintenance workflow, field-failure workflow, artifact registry, schema, validators, opt-in hook, status reporter, report templates, scoped skills, and CI.
- The operator-command envelope parses registered command blocks and optional candidate handoff files.
- Synthetic fixtures reject duplicated PowerShell prompts, single prompts, Command Prompt prefixes, continuation prompts, `At line` diagnostics, category metadata, fully qualified error IDs, and PowerShell diagnostic headers.
- Violations produce path, line, rule ID, and sanitized executable input without committing private operator evidence.

## What is broken when a guard fails

A failure is not reduced to “the script does not work.” Classify the exact boundary:

- **Operator-command contamination:** a shell prompt such as `PS C:\Work\Repo>` or terminal output was copied into executable input. In PowerShell, the leading `PS` can resolve to the `Get-Process` alias and the path becomes an invalid positional argument.
- **Duplicated prompt:** two prompts appear before the real command, making visual review unreliable.
- **Transcript re-execution:** continuation prompts, stdout, stderr, stack traces, `At line` diagnostics, `CategoryInfo`, or `FullyQualifiedErrorId` were presented as commands.
- **Parameter-binding timing:** `$PSScriptRoot` or another automatic variable was evaluated in a parameter default before the script body established context.
- **Ambiguous .NET overload:** PowerShell selected a `char/char` overload where the code intended `string/string`.
- **Skipped shell:** a validator passed in PowerShell 7 but was never executed in Windows PowerShell 5.1, or vice versa.
- **Unexecuted runtime branch:** hosted CI used a fixture-safe surface and did not prove real WSL/Ubuntu execution.
- **Interactive tooling:** `git diff` opened a pager and automation depended on terminal state.
- **False pass:** a parent process launched but child exit, effective-state readback, required observation, or repeatability was not proven.
- **Proof inflation:** static, fixture, or command-envelope evidence was presented as workstation runtime evidence.

Observed field failure outranks static and CI success until the **exact operator command** is rerun successfully.

## What is missing until the live sequence completes

The harness and CI do not prove:

- that a clean command executes successfully on a specific workstation;
- real WSL feature activation for the current user;
- initialized Ubuntu;
- visible WezTerm behavior;
- tmux client attachment;
- AGY or OpenCode user-visible launch;
- repeatability;
- rollback;
- provider authentication;
- operator acceptance.

Those claims require the repository-owned live-cert sequence and local run artifacts.

## Repository map

- `tooling/profiles/windows/technician-live-cert/` — stage and repair implementation.
- `tooling/profiles/windows/harness/technician-live-cert/` — scoped harness contracts and reports.
- `tooling/profiles/windows/harness/technician-live-cert/fixtures/` — minimized synthetic failure fixtures.
- `scripts/Test-OperatorCommandEnvelope.ps1` — command-block and candidate-handoff validator.
- `scripts/Test-TechnicianLiveCertSurface.ps1` — behavior and surface validator.
- `scripts/Test-TechnicianLiveCertHarness.ps1` — completeness and integration validator.
- `tests/test_operator_command_envelope.py` — dependency-free fixture and command-surface contract.
- `tests/test_technician_live_cert_harness.py` — harness and compatibility contracts.
- `tooling/profiles/windows/Get-TechnicianLiveCertHarnessStatus.ps1` — JSON and English status artifacts.
- `tooling/profiles/windows/hooks/Invoke-TechnicianLiveCertPreCommit.ps1` — opt-in local gate.
- `.ai/skills/operator-command-envelope/SKILL.md` — reusable prompt-free handoff procedure.
- `.github/workflows/technician-live-cert-surface.yml` — cross-shell CI.

## Workflow selection

Use `maintenance.workflow.json` for planned changes to stages, repairs, launchers, manifests, schemas, reports, validators, skills, or exact-next-command surfaces.

Use `field-failure-repair.workflow.json` when an operator supplies a failed or contradictory live command, or when command text contains a prompt or transcript. Preserve private evidence, separate executable input, validate the sanitized candidate, add a privacy-safe fixture when the signature is new, repair the harness, run the cross-shell matrix, and rerun only the prompt-free command.

## Operator-command envelope

A copy/paste command has two surfaces:

1. **Context outside the code block:** shell, owner, dependency, expected artifact, and completion gate.
2. **Executable input inside the code block:** commands only.

Never place a shell prompt, output, error, explanation, or expected result inside the executable block. Prefer a tracked CMD or PS1 entrypoint over a long inline bootstrap.

Validate every registered surface:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1
```

Validate a draft handoff file:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1 -CandidatePath '<handoff-file>'
```

The validator writes:

- `operator-command-envelope-report.json`
- `operator-command-envelope-report.md`

under `%LOCALAPPDATA%\AgentSwitchboard\technician-live-cert\operator-command-envelope`.

## Validation order

From the repository root:

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

Do not substitute `git diff` without `--no-pager` in an automated path.

The opt-in pre-commit gate is:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/hooks/Invoke-TechnicianLiveCertPreCommit.ps1
```

It is never installed implicitly.

## Operator reports

Generate the current read-only harness report:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-TechnicianLiveCertHarnessStatus.ps1
```

The harness status includes component state, runtime guards, operator-command envelope status, branch, HEAD, proof ceiling, and exact next command.

Generate or refresh the command-envelope report directly:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1
```

## Failure handling

1. Preserve the active run directory and exact stage output privately.
2. Record the shell: Command Prompt, Windows PowerShell 5.1, PowerShell 7, WSL Bash, WezTerm, tmux, TUI, or browser.
3. Separate executable input from prompts and transcript lines.
4. Validate the sanitized command with the operator-command envelope.
5. Record the child exit identity and local evidence path.
6. Repair the same branch and evidence chain when the defect is owned and correctable.
7. Add a behavior-level, fixture-backed guard.
8. Run both Windows PowerShell 5.1 and PowerShell 7 validators.
9. Rerun the exact prompt-free operator command.
10. Report the new run ID and honest proof ceiling.

## Handoff contract

A handoff includes repository, branch or worktree, exact HEAD, owned and forbidden paths, files changed, generated artifacts, validator results by shell, observed failures, skipped checks, proof ceiling, push or PR state, preserved local work, and one exact executable next command.

The next command must:

- name its shell outside the block;
- name the owner and dependency;
- state the artifact and completion gate;
- contain no prompt or transcript text;
- begin at the first executable character;
- propagate nonzero exit codes;
- advance the next useful unproven state.

## Proof ceiling

This harness proves tracked structure, discoverability, registered command-block hygiene, fixture-backed prompt and transcript rejection, cross-shell parser and contract compatibility, fixture-safe CMD dispatch, noninteractive Git hygiene, local artifact policy, and failure-boundary reporting. It does not prove workstation command execution or operator acceptance.
