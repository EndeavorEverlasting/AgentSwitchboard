---
id: android-termux-repo-bootstrap
version: 1.1.0
status: experimental
---

# Android Termux repository bootstrap

## Trigger

Use when an operator is turning Termux into a bounded AgentSwitchboard repository workspace, resuming the merged Android runtime, or recovering an Android command/evidence boundary before repository work.

## Inputs

- repository owner/name and intended base branch;
- bounded sprint lane, owned scope and forbidden scope;
- current tmux session identity;
- installed command evidence for `git`, `tmux`, `gh`, `ssh`, `curl`, and `jq`;
- the first unproved gate: input, scrollback/evidence, authentication, clone, branch isolation, validation, or runtime.

## Procedure

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, `.ai/harness/device-profile-registry.json`, and `tooling/profiles/android/harness/termux/manifest.json`.
2. Keep repository work inside a named tmux session. Prove detach/list/reattach before credentials or mutations if persistence has not already been proved.
3. Keep the Git checkout under Termux `$HOME`, not Android shared storage, unless a repository-specific contract requires otherwise.
4. If Android native selection spans panes or touch scrollback is unreliable, route to `.ai/skills/android-termux-terminal-recovery/SKILL.md`; use exact pane identity plus bounded `tmux capture-pane` rather than requiring long-press selection or screenshots.
5. Before reinstalling a missing-looking executable, run a short `command -v <name>` and version probe. Literal `[200~` routes to the terminal-boundary workflows rather than package repair.
6. Authenticate GitHub only after the input boundary is clean. Never record OAuth device codes, access tokens, passwords, recovery codes, credential files, or private SSH key material.
7. Fetch the live remote base, preserve default-branch state, and create/use one isolated feature branch with one writer. Never force-push or destructively clean unrelated work.
8. Run `python tests/test_android_termux_harness.py` on the phone and broader repository validators where their runtimes exist. Do not inflate hosted/static proof into phone runtime proof.
9. Use the merged Android runtime through `Start-AgentSwitchboard-Android.sh` / `agentswitchboard-android` only when the task enters the separate runtime lane; this harness skill does not modify runtime product code.
10. Produce local evidence named by the artifact registry and render an operator report with one exact next command.

## Outputs

- bootstrap/persistence/input/pane-capture evidence under `$HOME/agentswitchboard-evidence`;
- verified GitHub auth/clone state only when those gates actually pass;
- Android Termux harness validation output;
- operator report and next-command handoff.

## Deterministic validation

- `python tests/test_android_termux_harness.py`
- `bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh`
- `bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPrePush.sh` before push
- `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidTermuxHarnessCompleteness.ps1` on PowerShell-capable repo/CI
- `pwsh -NoLogo -NoProfile -File scripts/Test-AppHarness.ps1`
- `git diff --check`

## Forbidden scope

- do not edit `AGENTS.md` or governance policy from this harness skill;
- do not claim the merged Android runtime is live-proved merely because its files exist;
- do not install hooks implicitly or mutate global shell configuration without an explicit lane;
- do not expose or persist credentials, OAuth device codes, tokens, passwords, recovery codes, private SSH keys, credential-file contents, customer data, or private hostnames;
- do not use force, destructive cleanup, or default-branch writes.

## Stop and escalate

Stop at the exact boundary when command framing remains ambiguous, the only useful pane contains sensitive authentication material, authentication cannot be proved, the remote base moves incompatibly, branch ownership collides, required validation cannot run, or proceeding would cross forbidden scope. Preserve safe evidence and name the smallest executable action that advances that gate.
