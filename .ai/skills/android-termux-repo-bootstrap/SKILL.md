---
id: android-termux-repo-bootstrap
version: 1.2.0
status: experimental
---

# Android Termux repository bootstrap

## Trigger

Use when an operator is turning Termux into a bounded AgentSwitchboard repository workspace, resuming the merged Android runtime, or recovering an Android command/evidence boundary before repository work.

## Inputs

- repository owner/name and intended base branch;
- bounded sprint lane, owned scope and forbidden scope;
- current tmux session identity;
- installed command evidence for `git`, `tmux`, `gh`, `ssh`, `curl`, `jq`, and `python`;
- the first unproved gate: input, scrollback/evidence, authentication, clone, branch isolation, validation, repository-family routing, or runtime.

## Procedure

1. Read `AGENTS.md`, `.ai/agent-contract.json`, `.ai/harness/repository-family.registry.json`, `CODEBASE_MAP.md`, `.ai/harness/device-profile-registry.json`, and `tooling/profiles/android/harness/termux/manifest.json`.
2. Keep repository work inside a named tmux session. Prove detach/list/reattach before credentials or mutations if persistence has not already been proved.
3. Keep the Git checkout under Termux `$HOME`, not Android shared storage, unless a repository-specific contract requires otherwise.
4. Prove the harness tool floor. If `python` is missing, the harness—not the separate Android runtime installer—owns the bounded prerequisite `pkg install -y python`; then prove `command -v python` and `python --version`.
5. If Android native selection spans panes or touch scrollback is unreliable, route to `.ai/skills/android-termux-terminal-recovery/SKILL.md`; use exact pane identity plus bounded `tmux capture-pane` rather than requiring long-press selection or screenshots.
6. Before reinstalling any other missing-looking executable, run a short `command -v <name>` and version probe. Literal `[200~` routes to the terminal-boundary workflows rather than package repair.
7. Authenticate GitHub only after the input boundary is clean. Never record OAuth device codes, access tokens, passwords, recovery codes, credential files, or private SSH key material.
8. Before any fetch or branch operation, verify the local path is a Git checkout and the origin is AgentSwitchboard. If no usable clone exists, acquire it under `$HOME/dev/AgentSwitchboard` first; do not run `git fetch origin main` against a nonexistent or unrelated directory.
9. For cross-repository work, read `.ai/harness/repository-family.registry.json` and require `scripts/Get-RepositoryFamilyHarnessStatus.ps1` on a PowerShell-capable environment. If `pwsh` is unavailable on Termux, record the family status probe as unavailable and do not promote local inspection into cross-repository readiness.
10. After clone verification, fetch the live remote base, preserve default-branch state, and create/use one isolated feature branch with one writer. Never force-push or destructively clean unrelated work.
11. Run `python tests/test_android_termux_harness.py` on the phone and broader repository validators where their runtimes exist. Do not inflate hosted/static proof into phone runtime proof.
12. Use the merged Android runtime through `Start-AgentSwitchboard-Android.sh` / `agentswitchboard-android` only when the task enters the separate runtime lane; this harness skill does not modify runtime product code.
13. Produce local evidence named by the artifact registry and render an operator report with one exact next command.

## Outputs

- bootstrap/persistence/input/pane-capture evidence under `$HOME/agentswitchboard-evidence`;
- verified local clone/origin state before branch work;
- family-status proof or explicit PowerShell-unavailable boundary for cross-repository work;
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
- do not modify the Android runtime installer merely to satisfy a harness-only prerequisite;
- do not install hooks implicitly or mutate global shell configuration without an explicit lane;
- do not expose or persist credentials, OAuth device codes, tokens, passwords, recovery codes, private SSH keys, credential-file contents, customer data, or private hostnames;
- do not use force, destructive cleanup, or default-branch writes.

## Stop and escalate

Stop at the exact boundary when command framing remains ambiguous, the only useful pane contains sensitive authentication material, Python cannot be installed inside the authorized harness prerequisite lane, authentication cannot be proved, no valid local clone/origin can be established, a required repository-family status probe is unavailable for a cross-repository claim, the remote base moves incompatibly, branch ownership collides, required validation cannot run, or proceeding would cross forbidden scope. Preserve safe evidence and name the smallest executable action that advances that gate.
