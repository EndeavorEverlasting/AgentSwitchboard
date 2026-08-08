# Android Termux operational harness

## Purpose

This harness makes the Android/Termux repository path inspectable and repeatable without pretending that a canonical AgentSwitchboard Android launcher already exists. The Android profile remains governed by `.ai/harness/device-profile-registry.json`; this lane supplies operator contracts, portable validation, failure handling, local evidence naming, and handoff.

## Prerequisites

Use the F-Droid build of Termux and keep Termux add-ons optional until a specific workflow requires them. The narrow repository toolchain is `git`, `openssh`, `tmux`, `gh`, `curl`, `jq`, and an editor. Repository work should live under Termux `$HOME`, for example `$HOME/dev/AgentSwitchboard`, rather than Android shared storage.

A durable shell is a gate, not decoration. Start or attach a named tmux session and prove detach, `tmux ls`, and reattach before doing credential or repository work that must survive an Android app switch or terminal loss.

## First-use workflow

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, the Android profile registry, and `tooling/profiles/android/harness/termux/manifest.json`.
2. Run the task-intake workflow and prove required commands resolve.
3. If a pasted command appears with literal `[200~` or another framing marker, stop downstream work and use the terminal-boundary workflow. A rendered line such as `[200~gh ...` is evidence that the shell did not receive `gh` as the executable name. It is not by itself evidence that GitHub CLI is uninstalled.
4. When paste framing is suspect, manually type a short probe such as `gh --version`. Run `command -v gh` before any reinstall. Only reopen package installation if the manually typed resolution probe actually fails.
5. Once command delivery is clean, perform GitHub authentication. Keep device codes and credentials out of logs, screenshots, issues, PRs and chat.
6. Clone under `$HOME/dev`, fetch the current remote base, and compare local HEAD with `origin/main` before creating an isolated work branch. Concurrent work may move `main`; matching a newer fetched remote is success, while stale hard-coded SHAs are not.
7. Run the portable contract test on Android before broader repository work.

## Validation

Android-local, dependency-free contract check:

```sh
python tests/test_android_termux_harness.py
```

Opt-in staged-change hook:

```sh
bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh
```

Repository/CI completeness check:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-AndroidTermuxHarnessCompleteness.ps1
```

Aggregate repository harness where PowerShell is available:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-AppHarness.ps1
```

Patch hygiene:

```sh
git diff --check
```

## Artifacts and evidence

Generated Android evidence is local and untracked under `$HOME/agentswitchboard-evidence`. Use `artifact-registry.json` for names and proof ceilings. Do not commit operator logs simply to prove the harness exists. A terminal crash or app switch must not destroy the only copy of evidence: commands that matter should use `tee` or write explicit local report files before the next boundary.

## Failure handling

Preserve the tmux session, classify the exact boundary, and do not discard contradictory proof. If a bootstrap log already proves `gh --version` and a later pasted line says `[200~gh: command not found`, treat that as an input-boundary inconsistency until a manually typed probe resolves it. Do not reinstall a healthy tool to make an unrelated paste defect disappear.

If authentication fails, preserve only redacted status and error identity. Never preserve device codes, tokens, passwords, recovery codes, or private key content. If a clone or branch step fails, record the remote, branch, local HEAD, `origin/main`, status and the nonzero command without force or cleanup.

## Rollback

The harness itself installs nothing globally and its hook is opt-in. Rollback for a local validation attempt is therefore to stop invoking the hook and remove only generated local evidence that the operator explicitly chooses to discard. Package removal, credential revocation, repository deletion, or Android app removal are separate actions and are not automatic rollback steps.

## Current gaps

- The canonical Android profile launcher is not proved implemented by this harness.
- GitHub authentication on a particular phone is a runtime gate and must be proved on that device.
- Repository clone, branch mutation, agent runtime, provider routing and product behavior remain separate gates.
- Bracketed-paste framing is a documented failure signature; deterministic prevention across Android keyboards/terminal versions is not claimed.

## Proof ceiling

Tracked contracts and deterministic structural validation only, plus whatever runtime evidence an operator explicitly captures locally. No Android launcher, credential, clone, agent-provider, product-runtime or deployment success is implied.
