---
id: android-termux-terminal-recovery
version: 1.1.0
status: experimental
---

# Android Termux terminal recovery

## Trigger

Use when Android text selection spans multiple tmux panes, touch scrolling is unclear or unreliable, clipboard paste/selection is suspect, prior terminal output must be recovered, a modal editor or pager appears stuck, the operator cannot tell whether the shell is waiting for input or running a foreground application, or the operator would otherwise need a screenshot to preserve evidence.

## Inputs

- current tmux session and pane inventory;
- the output or decision that must be recovered;
- visible foreground command or editor state when known;
- whether unsaved editor content should be saved or discarded;
- whether any visible pane contains authentication/device-code or credential material;
- maximum history required (default 200 lines);
- the next bounded operator/agent action.

## Procedure

1. Read `AGENTS.md` and `tooling/profiles/android/harness/termux/manifest.json`.
2. Before sending the operator into a modal surface such as nano, less, tmux copy mode, or vi, state the expected foreground screen and exact exit contract. A command that intentionally opens an editor does not return to the shell until the editor exits.
3. When the current state is ambiguous, inspect the exact safe tmux pane with `bash tooling/profiles/android/harness/termux/Inspect-TerminalState.sh <session:window.pane>`. Do not label a foreground application as hung merely because there is no shell prompt.
4. A nano screen showing the filename and `Modified` near the top with shortcuts such as `^G Help`, `^O Write Out`, and `^X Exit` is `modal-editor:nano`, waiting for editor input. Exit with `Ctrl+X`; if prompted, `N` discards accidental edits, while `Y` then `Enter` saves the shown filename.
5. Keep the task-file boundary explicit. `sprint.md` must contain the bounded task instructions for the coding agent, not `cd`, `git switch`, `git pull`, branch creation, or the `nano` command used to prepare the session. Reject shell-bootstrap text before invoking `agentswitchboard-android sprint --prompt-file`.
6. After leaving a modal editor, prove shell return with `printf 'PHONE_SHELL_READY=%s\n' "$(date -Iseconds)"` before continuing.
7. Do not treat Android long-press selection as a pane boundary. List exact pane identities with `tmux list-panes -a -F '#S:#I.#P active=#{pane_active} cmd=#{pane_current_command}'`.
8. Classify sensitivity before persistence. Never capture a pane that shows OAuth/device codes, tokens, passwords, private keys, credential files, or other forbidden evidence.
9. Target one safe pane explicitly and capture only bounded history, normally `tmux capture-pane -p -S -200 -t <session:window.pane>`.
10. When durable proof is needed, redirect that capture to a timestamped file under `$HOME/agentswitchboard-evidence`; do not require selecting terminal text.
11. Inspect the file with `tail`, `sed`, `grep`, `less`, or `cat`. Share only the smallest non-sensitive excerpt or artifact path needed for the next decision.
12. For human browsing only, tmux copy mode is the fallback: `Ctrl+B`, then `[`, navigate with Page Up/Page Down or arrows, and press `q` to leave copy mode. Copy mode is not required for evidence when `capture-pane` works.
13. If clipboard transport remains awkward, use the repository's canonical plain-text command through careful manual entry, QR, monitored live document, or file transport as appropriate. Transport does not grant new execution authority.
14. Preserve the exact target, foreground command, classification, exit contract, capture range, artifact path, redaction/sensitivity decision, and next command in the operator report.

## Outputs

- terminal-state classification with an explicit exit contract;
- bounded tmux pane inventory;
- one safe pane-capture artifact or a documented sensitivity block;
- terminal interaction report;
- exact next command that does not depend on Android native text selection or an unexplained modal state.

## Deterministic validation

- `python tests/test_android_termux_harness.py`
- `python tests/test_android_termux_modal_state_harness.py`
- `bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh`
- `bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPrePush.sh` before pushing Android harness changes
- `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidTermuxHarnessCompleteness.ps1` where PowerShell is available
- `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidTermuxModalStateHarness.ps1` where PowerShell is available
- `git diff --check`

## Forbidden scope

- do not persist or share authentication/device codes, tokens, passwords, recovery codes, credential-file contents, or private SSH keys;
- do not call an editor, pager, TUI, or foreground process hung solely because the shell prompt is absent;
- do not hand off a modal command without the expected screen and exit keys;
- do not pass a shell-bootstrap command list as the coding agent's sprint prompt;
- do not use an unbounded pane capture merely because touch scrolling is inconvenient;
- do not capture every pane when only one pane is relevant;
- do not claim that `capture-pane` proves the command represented in the text succeeded;
- do not modify Android runtime/product code from this harness recovery procedure;
- do not install hooks implicitly.

## Stop and escalate

Stop the capture if exact pane identity cannot be established or the only relevant pane contains sensitive material. If a foreground process cannot be classified safely, preserve the tmux session and inspect non-sensitive pane metadata before sending keys. Generate a fresh sanitized read-only command in a known pane, or name the physical/authentication action required. Never solve a secrecy problem by taking a broader screenshot.
