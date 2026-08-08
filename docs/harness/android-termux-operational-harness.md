# Android Termux operational harness

## Purpose

This harness makes Android/Termux repository work repeatable when mobile terminal input, text selection, split-pane rendering, scrollback, clipboard transport, app switching, or evidence preservation is unreliable. The Android runtime is now separately implemented and registered on `main`; this harness indexes that runtime but does not modify it or claim live provider/model/tool success.

## Prerequisites and floor

Keep the checkout under Termux `$HOME` (for example `$HOME/dev/AgentSwitchboard`), use a named tmux session, and keep generated evidence under `$HOME/agentswitchboard-evidence`. The narrow tool floor is `git`, `openssh`, `tmux`, `gh`, `curl`, `jq`, plus the runtime-specific packages installed by the separate Android runtime entrypoint when that lane is active.

A durable shell is a gate: prove detach, `tmux ls`, and reattach before work that must survive an Android app switch or terminal loss.

## Mobile terminal rule: pane identity beats touch selection

Android long-press selection is not a reliable tmux pane boundary. When selection highlights text across multiple panes, or touch scrolling is unclear, do not fight the UI and do not require a screenshot for proof.

First list pane identities:

```sh
tmux list-panes -a -F '#S:#I.#P active=#{pane_active} cmd=#{pane_current_command}'
```

Then target exactly one **non-sensitive** pane and capture bounded history:

```sh
mkdir -p "$HOME/agentswitchboard-evidence"
TARGET='<session:window.pane>'
OUT="$HOME/agentswitchboard-evidence/tmux-pane-$(date +%Y%m%d-%H%M%S).txt"
tmux capture-pane -p -S -200 -t "$TARGET" > "$OUT"
printf 'EVIDENCE=%s\n' "$OUT"
```

Do not persist a pane that contains an OAuth/device code, password, token, private key, credential-file content, or comparable secret. Switch to a safe pane or run a fresh sanitized read-only command and capture that output instead.

For **human browsing only**, tmux copy mode is the fallback: press `Ctrl+B`, release, press `[`, navigate with Page Up/Page Down or arrows, and press `q` to leave copy mode. `capture-pane` remains the preferred evidence path because it is explicit, bounded, scriptable, and independent of Android native selection.

## Input framing workflow

If a pasted command appears with literal `[200~` or another framing marker, stop downstream diagnosis. A line such as `[200~gh ...` is evidence that the shell did not receive `gh` as the executable name; it is not evidence that GitHub CLI is uninstalled. Manually type `command -v gh` / `gh --version` before considering package repair.

## Transport choices

Clipboard copy/paste is convenient but optional. Critical commands have one canonical plain-text form and may be delivered by careful manual entry, QR payload, monitored live document, or file artifact. Prefer short repository-owned launchers over long fragile commands. Transport carries text; it does not create execution authority.

## Validation

Android-local contract:

```sh
python tests/test_android_termux_harness.py
```

Opt-in hooks:

```sh
bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh
bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPrePush.sh
```

PowerShell/hosted completeness:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-AndroidTermuxHarnessCompleteness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-AppHarness.ps1
```

Patch hygiene:

```sh
git diff --check
```

## Artifacts

Use `tooling/profiles/android/harness/termux/artifact-registry.json`. Pane inventory, bounded pane capture, terminal interaction report, bootstrap logs, clone proof and harness validation are local/untracked. Never commit raw operator evidence simply to prove the harness exists.

## Runtime boundary

The canonical runtime entrypoint is `Start-AgentSwitchboard-Android.sh`, and the installed command is `agentswitchboard-android`. Runtime provider login, model response, tool execution and repository-writing proof remain separate live gates. The harness may route to them but must not promote static/CI evidence into runtime proof.

## Failure handling

Preserve the tmux session and the first safe failure evidence. Route bracketed-paste failures through the input-boundary workflow and multi-pane/scrollback failures through `capture-terminal-output.workflow.json` / `android-termux-terminal-recovery`. If the only relevant screen contains secrets, do not broaden the screenshot or capture; generate sanitized output in a known pane.

## Rollback

Hooks are opt-in and the harness installs nothing globally. Stop invoking a hook to remove it from a local workflow. Generated evidence may be deleted only deliberately. Package removal, credential revocation, repository deletion, Android runtime uninstall, and Termux app removal are separate operations.

## Proof ceiling

Tracked harness structure, deterministic validators, CI, pane-capture procedure, failure classification, and evidence policy only. This does not prove identical Android UI behavior, clipboard reliability on every device, provider authentication, model/tool behavior, repository mutation, or operator acceptance.
