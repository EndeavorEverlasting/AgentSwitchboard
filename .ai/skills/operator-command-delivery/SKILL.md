---
id: operator-command-delivery
status: canonical
owner: EndeavorEverlasting/AgentSwitchboard
---

# Operator Command Delivery

## Trigger

Use this skill before producing a copy-paste command for an operator when the command crosses repository, shell, process, installer, terminal, TUI, or GUI boundaries. Also use it after a command fails before the intended runtime proof, especially for HTTP 404, malformed PowerShell, missing downloaded files, terminal closure, or lost diagnostics.

## Required inputs

- repository owner/name;
- intended source branch, tag, or commit;
- exact required remote files;
- declared operator shell;
- owning downstream validator or launcher;
- canonical downstream artifact path or the tracked registry/manifest/workflow that resolves it;
- proof level the command is allowed to claim.

## Procedure

1. Read `AGENTS.md`, the applicable harness doctrine, this skill, and `tooling/profiles/windows/harness/operator-command-delivery/codebase-map.json`.
2. Resolve the requested ref to an exact commit using a read-only source query. Never rely only on remembered chat state, PR text, or a previously reported SHA.
3. Resolve every required remote file at that exact commit before writing the operator command. A commit existing does not prove a file path exists there.
4. Build the command for the declared shell only. For PowerShell, environment variables use `$env:NAME`; reject `$env\\:NAME` and other escaped punctuation introduced by transport or formatting.
5. Strip prompt and transcript material. Never include `PS C:\\...>`, `>>`, `+ CategoryInfo`, or copied shell decorations inside the command body.
6. Preserve the interactive parent shell. Do not end a command pasted at a prompt with top-level `exit`. When a child must propagate a nonzero code, run the child process, capture `$LASTEXITCODE`, print it, persist evidence, and raise/return failure without closing the parent terminal.
7. For parameterized `gh api` reads, use explicit read semantics such as `gh api --method GET <endpoint> -f ref=<commit>` instead of an interpolated content query string.
8. Resolve the canonical downstream artifact from tracked repository evidence before delivery. The command must print or open that artifact after execution whenever the owning runtime produces it.
9. Run `pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandDeliveryHarnessCompleteness.ps1` and `python -m unittest tests.test_operator_command_delivery_harness` before publishing a new command form when repository execution is available.
10. Deliver only the command body the operator should paste. Do not place prompt markers or escaped Markdown punctuation inside it.

## Expected outputs

- verified repository + exact commit;
- verified required file list;
- transport-integrity result;
- interactive-shell safety result;
- one operator command;
- canonical downstream artifact path;
- honest proof ceiling.

## Deterministic validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandDeliveryHarnessCompleteness.ps1
python -m unittest tests.test_operator_command_delivery_harness
```

The positive fixture must pass. The corrupted fixture containing `$env\\:TEMP`, a PowerShell prompt prefix, query-string content retrieval, and top-level `exit` must be detected as invalid.

## Proof promotion

Command-delivery validation proves source resolution and command transport integrity only. A successful downstream child exit can promote only to the proof level owned by that downstream validator or launcher. Tmux live proof, for example, still requires its runtime artifact to record `tmuxClientAttachedObserved=true` and `proofLevel=tmux-client-attached`.

## Forbidden scope

- Do not change product behavior merely to make a command easier to deliver.
- Do not weaken P00, runtime, provider, launcher, or artifact gates.
- Do not commit generated operator evidence, usernames, hostnames, credentials, tokens, or private endpoints.
- Do not install implicit Git hooks; the tracked hook is opt-in and documentation-driven.
- Do not claim GUI, TUI, tmux attachment, hosted response, or operator acceptance from static command validation.

## Stop and escalate

Stop at the command-delivery boundary when the exact ref or required file cannot be resolved, the repair needs product code outside the declared lane, the target machine requires protected access or credentials, or the next step would be destructive. Preserve the exact failed command and earliest observed failure without inflating downstream proof.
