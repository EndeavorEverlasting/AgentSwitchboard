# Operator command-delivery harness

## Purpose

This harness protects the boundary between repository evidence and a command pasted into an operator shell. It exists because a command can be correct in source yet fail before the intended runtime when a ref/file is not independently resolved, punctuation is escaped during transport, prompt text is copied, or a top-level `exit` closes the interactive shell.

## Current state

- **Working:** tracked map, artifact registry, verification workflow, failure workflow, fixtures, opt-in pre-push hook, scoped skill, human report template, PowerShell completeness validator, Python contract, and CI.
- **Working:** the positive fixture uses canonical PowerShell environment syntax and explicit `gh api --method GET` source reads.
- **Working:** the negative fixture preserves the known corruption class and must be rejected deterministically.
- **Missing by design:** this harness does not execute product launchers, install WSL, open WezTerm, attach tmux, authenticate providers, or claim operator acceptance.

## Required operator-command shape

For a Windows PowerShell operator command that needs repository files from GitHub:

1. Resolve the intended source ref to an exact commit.
2. Resolve each required file at that exact commit before execution.
3. Use explicit GET semantics for parameterized GitHub API reads.
4. Use `$env:NAME` exactly for environment variables.
5. Run exit-propagating work in a child process so the interactive parent shell stays open.
6. Capture and print the child exit code.
7. Resolve and print the downstream canonical artifact after the child completes.

A safe retrieval fragment follows this form:

```powershell
$resolved = gh api --method GET 'repos/EndeavorEverlasting/AgentSwitchboard/commits/main' --jq '.sha'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolved)) { throw 'Unable to resolve main.' }
$content = gh api --method GET 'repos/EndeavorEverlasting/AgentSwitchboard/contents/Open-AgentSwitchboard-Tmux.ps1' -f "ref=$resolved" --jq '.content'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($content)) { throw 'Unable to resolve launcher file.' }
```

The complete operator command should additionally verify every file it downloads, run the child launcher through `cmd.exe /d /c` or another explicit child boundary when appropriate, capture `$LASTEXITCODE`, and print the canonical runtime artifact. It must not end the interactive parent command with `exit`.

## Known traps

- `$env:NAME` is PowerShell syntax. A backslash inserted before the colon is corruption, not escaping.
- `PS C:\...>` and `>>` are shell UI, not command content.
- A commit SHA resolving successfully does not prove a named file exists at that commit.
- A PR merge message does not replace an exact file read.
- Query-string interpolation in a copy-paste command is avoidable; prefer explicit GET request parameters.
- Static source verification does not prove the downstream app is open or usable.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandDeliveryHarnessCompleteness.ps1
python -m unittest tests.test_operator_command_delivery_harness
```

The optional tracked pre-push adapter is:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/harness/operator-command-delivery/hooks/pre-push.ps1
```

It is never installed implicitly.

## Failure recovery

When a command fails before the intended runtime gate, preserve the failed command and earliest stderr/stdout, classify the boundary, re-resolve source identity and files independently, repair the harness if the failure class was unenforced, rerun focused validators, then issue the smallest repaired command. Do not skip directly to a higher runtime claim.

## Proof ceiling

Passing this harness proves command-source resolution rules, transport-integrity contracts, interactive-shell safety rules, component discoverability, and deterministic regression detection. It does not prove the downstream runtime until the owning runtime artifact passes its own gate.
