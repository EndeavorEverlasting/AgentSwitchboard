# Android Termux operational harness

## Purpose

This harness makes Android/Termux repository work repeatable when mobile terminal input, text selection, split-pane rendering, scrollback, clipboard transport, app switching, modal editors, foreground-process state, or evidence preservation is unreliable. The Android runtime is separately implemented and registered on `main`; this harness indexes that runtime but does not modify it or claim live provider/model/tool success.

## Prerequisites and authority floor

Read `AGENTS.md`, `.ai/agent-contract.json`, `.ai/harness/repository-family.registry.json`, `CODEBASE_MAP.md`, and `.ai/harness/device-profile-registry.json` before mutation. Keep the checkout under Termux `$HOME` (for example `$HOME/dev/AgentSwitchboard`), use a named tmux session, and keep generated evidence under `$HOME/agentswitchboard-evidence`.

The harness tool floor is `git`, `openssh`, `tmux`, `gh`, `curl`, `jq`, and `python`. The merged Android runtime installer owns its own runtime packages and intentionally remains separate. If Python is absent, install only the harness prerequisite and prove it:

```sh
pkg install -y python
command -v python
python --version
```

For cross-repository work, the canonical status probe is `scripts/Get-RepositoryFamilyHarnessStatus.ps1`. Run it on a PowerShell-capable environment before claiming repository-family readiness. If `pwsh` is unavailable on Termux, read the family registry locally, record the probe as unavailable, and do not invent a family-level PASS.

A durable shell is a gate: prove detach, `tmux ls`, and reattach before work that must survive an Android app switch or terminal loss.

## Clone before branch operations

Before `git fetch origin main`, branch creation, or pull operations, prove that the intended directory is a usable AgentSwitchboard checkout:

```sh
git rev-parse --show-toplevel
git remote get-url origin
```

If the checkout does not exist, acquire it under `$HOME/dev/AgentSwitchboard` first. Never let a first-use workflow run branch commands against a nonexistent path or unrelated repository.

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

## Modal terminal state is not a hang by default

Every operator instruction that opens a modal surface must include four things **before** the command is run: the expected foreground screen, the fact that the shell prompt will be absent while that application owns the pane, the exact exit keys, and whether exiting saves or discards work.

From another safe pane, classify an ambiguous pane with:

```sh
bash tooling/profiles/android/harness/termux/Inspect-TerminalState.sh <session:window.pane>
```

For nano, the common visible state is the edited filename plus `Modified` near the top and shortcuts including `^G Help`, `^O Write Out`, and `^X Exit` at the bottom. That is an editor waiting for input, not evidence that Termux or the shell is hung.

The exit contract is explicit:

- press `Ctrl+X`;
- if nano asks to save a modified buffer, press `N` to discard accidental content;
- or press `Y`, then `Enter`, to save the shown filename when the text is intentionally the sprint prompt.

After exit, prove the shell actually returned:

```sh
printf 'PHONE_SHELL_READY=%s\n' "$(date -Iseconds)"
```

Do not kill Termux, close the tmux session, or press random keys simply because the prompt disappeared.

### Sprint prompt boundary

The shell commands used to prepare work are **not** the content of `sprint.md`. A valid sprint prompt contains the bounded repository task that the coding agent should execute. If the file contains lines such as `cd`, `git switch main`, `git pull --ff-only`, `git switch -c ...`, or `nano "$HOME/sprint.md"`, classify the intake as authoring confusion and repair or discard that file before running:

```sh
agentswitchboard-android sprint --prompt-file "$HOME/sprint.md"
```

The workflow `workflows/recover-modal-terminal-state.workflow.json` and fixture `fixtures/nano-modal-editor.fixture.txt` are the deterministic recovery contract for this failure.

## Input framing workflow

If a pasted command appears with literal `[200~` or another framing marker, stop downstream diagnosis. A line such as `[200~gh ...` is evidence that the shell did not receive `gh` as the executable name; it is not evidence that GitHub CLI is uninstalled. Manually type `command -v gh` / `gh --version` before considering package repair.

## Transport choices

Clipboard copy/paste is convenient but optional. Critical commands have one canonical plain-text form and may be delivered by careful manual entry, QR payload, monitored live document, or file artifact. Prefer short repository-owned launchers over long fragile commands. Transport carries text; it does not create execution authority.

## Validation

Android-local contracts:

```sh
python tests/test_android_termux_harness.py
python tests/test_android_termux_modal_state_harness.py
```

Opt-in hooks:

```sh
bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh
bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPrePush.sh
```

PowerShell/hosted completeness:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-AndroidTermuxHarnessCompleteness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-AndroidTermuxModalStateHarness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-AppHarness.ps1
```

Patch hygiene:

```sh
git diff --check
```

## Artifacts

Use `tooling/profiles/android/harness/termux/artifact-registry.json`. Terminal-state reports, pane inventory, bounded pane capture, terminal interaction reports, bootstrap logs, clone proof and harness validation are local/untracked. Never commit raw operator evidence simply to prove the harness exists.

## Runtime boundary

The canonical runtime entrypoint is `Start-AgentSwitchboard-Android.sh`, and the installed command is `agentswitchboard-android`. Runtime provider login, model response, tool execution and repository-writing proof remain separate live gates. The harness may route to them but must not promote static/CI evidence into runtime proof.

## Failure handling

Preserve the tmux session and the first safe failure evidence. Route modal editor/pager ambiguity through `recover-modal-terminal-state.workflow.json`, bracketed-paste failures through the input-boundary workflow, and multi-pane/scrollback failures through `capture-terminal-output.workflow.json` / `android-termux-terminal-recovery`. If the only relevant screen contains secrets, do not broaden the screenshot or capture; generate sanitized output in a known pane.

## Rollback

Hooks are opt-in and the harness installs nothing globally except the explicit Python prerequisite when the operator runs that command. Stop invoking a hook to remove it from a local workflow. Generated evidence may be deleted only deliberately. Package removal, credential revocation, repository deletion, Android runtime uninstall, and Termux app removal are separate operations.

## Proof ceiling

Tracked harness structure, deterministic validators, CI, pane-capture procedure, modal-state classifier, explicit editor exit contract, sprint-prompt boundary, clone gate, repository-family routing boundary, failure classification, and evidence policy only. This does not prove identical Android UI behavior, clipboard reliability on every device, foreground-process health, repository-family status without its PowerShell probe, provider authentication, model/tool behavior, repository mutation, or operator acceptance.
