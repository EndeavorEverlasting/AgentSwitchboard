---
id: operator-command-delivery
version: 1.1.0
status: canonical
owner: EndeavorEverlasting/AgentSwitchboard
---

# Operator Command Delivery

## Trigger

Use this skill before producing a copy-paste command for an operator when the command crosses repository, shell, process, installer, terminal, TUI, or GUI boundaries. Also use it after a command fails before the intended runtime proof, especially for HTTP 404, malformed PowerShell, missing downloaded files, blocked child-process launch, terminal closure, or lost diagnostics.

## Required inputs

- repository owner/name;
- intended source branch, tag, or commit;
- exact required remote files;
- declared operator shell;
- exact external executables the command must launch and bounded side-effect-free probe arguments for each;
- owning downstream validator or launcher;
- canonical downstream artifact path or the tracked registry/manifest/workflow that resolves it;
- proof level the command is allowed to claim.

## Procedure

1. Read `AGENTS.md`, the applicable harness doctrine, this skill, and `tooling/profiles/windows/harness/operator-command-delivery/codebase-map.json`.
2. Resolve the requested ref to an exact commit using a read-only source query. Never rely only on remembered chat state, PR text, or a previously reported SHA.
3. Resolve every required remote file at that exact commit before writing the operator command. A commit existing does not prove a file path exists there.
4. Before the delivered command depends on an external executable, resolve its exact path and prove that exact file can start using `scripts/Test-OperatorChildExecutableLaunch.ps1` or an equivalent bounded probe with `UseShellExecute=false`, timeout, captured stdout/stderr, and durable evidence. `where`, `Get-Command`, file existence, download success, and version metadata without process creation are not launch proof.
5. If an executable launch is blocked, stop before downstream runtime work, classify the boundary as `child-executable-launch`, print the launch artifact, and do not substitute another wrapper whose own launchability is unproven.
6. Build the command for the declared shell only. For PowerShell, environment variables use `$env:NAME`; reject `$env\\:NAME` and other escaped punctuation introduced by transport or formatting.
7. Strip prompt and transcript material. Never include `PS C:\\...>`, `>>`, `+ CategoryInfo`, or copied shell decorations inside the command body.
8. Preserve the interactive parent shell. Do not use a PowerShell `exit` statement anywhere in a command pasted at an interactive prompt, including after a semicolon. When a child must propagate a nonzero code, run the child process, capture `$LASTEXITCODE`, print it, persist evidence, and raise/return failure without closing the parent terminal.
9. For parameterized `gh api` reads, use explicit read semantics such as `gh api --method GET <endpoint> -f ref=<resolvedCommit>` instead of an interpolated content query string. Every file read must use the exact commit produced by the preceding ref-resolution step.
10. Resolve the canonical downstream artifact from tracked repository evidence before delivery. The command must print or open that artifact after execution whenever the owning runtime produces it.
11. Save the exact candidate command to a temporary `.ps1` file and run `pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandDeliveryHarnessCompleteness.ps1 -CandidatePath <candidate.ps1>` plus `python -m unittest tests.test_operator_command_delivery_harness` before publishing a new command form when repository execution is available. The validator must inspect the candidate itself; fixture-only validation is insufficient.
12. Deliver only the command body the operator should paste. Do not place prompt markers or escaped Markdown punctuation inside it.

## Expected outputs

- verified repository + exact commit;
- verified required file list;
- exact child executable path(s) and launch-proof artifact(s);
- transport-integrity result for the actual candidate command;
- interactive-shell safety result for the actual candidate command;
- one operator command;
- canonical downstream artifact path;
- honest proof ceiling.

## Deterministic validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandDeliveryHarnessCompleteness.ps1 -CandidatePath <candidate.ps1>
python -m unittest tests.test_operator_command_delivery_harness
```

The positive fixture must pass. The corrupted fixture containing `$env\\:TEMP`, a PowerShell prompt prefix, query-string content retrieval, and top-level or inline `exit` must be detected as invalid. The child-launch regression fixture must classify `Access is denied.` before any downstream artifact as `child-executable-launch-blocked`. The candidate path is required when validating a command for publication so the published command cannot bypass the canned fixtures.

## Proof promotion

Command-delivery validation proves source resolution, child-executable launchability for the bounded probe, and command transport integrity only. A successful downstream child exit can promote only to the proof level owned by that downstream validator or launcher. Tmux live proof, for example, still requires its runtime artifact to record `tmuxClientAttachedObserved=true` and `proofLevel=tmux-client-attached`.

## Forbidden scope

- Do not change product behavior merely to make a command easier to deliver.
- Do not weaken P00, runtime, provider, launcher, or artifact gates.
- Do not commit generated operator evidence, usernames, hostnames, credentials, tokens, or private endpoints.
- Do not install implicit Git hooks; the tracked hook is opt-in and documentation-driven.
- Do not claim GUI, TUI, tmux attachment, hosted response, or operator acceptance from static command or executable-launch validation.

## Stop and escalate

Stop at the command-delivery boundary when the exact ref or required file cannot be resolved, a required child executable cannot be concretely launched, the candidate command fails deterministic validation, the repair needs product code outside the declared lane, the target machine requires protected access or credentials, or the next step would be destructive. Preserve the exact failed command and earliest observed failure without inflating downstream proof.
