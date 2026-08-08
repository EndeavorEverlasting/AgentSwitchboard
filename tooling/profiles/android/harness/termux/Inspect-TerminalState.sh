#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  printf '%s\n' 'CLASSIFICATION=tmux-unavailable' 'HUNG_CLAIM=not-established' 'NEXT=Install or repair tmux before terminal-state inspection.'
  exit 2
fi

if [ -n "${1:-}" ]; then
  target="$1"
elif [ -n "${TMUX:-}" ]; then
  target="$(tmux display-message -p '#S:#I.#P')"
else
  printf '%s\n' 'CLASSIFICATION=outside-tmux' 'HUNG_CLAIM=not-established' 'NEXT=Attach to the named AgentSwitchboard tmux session or pass an explicit session:window.pane target.'
  exit 3
fi

if ! tmux display-message -p -t "$target" '#S:#I.#P' >/dev/null 2>&1; then
  printf 'CLASSIFICATION=unknown-pane\nTARGET=%s\nHUNG_CLAIM=not-established\n' "$target"
  exit 4
fi

identity="$(tmux display-message -p -t "$target" '#S:#I.#P')"
cmd="$(tmux display-message -p -t "$target" '#{pane_current_command}')"
in_mode="$(tmux display-message -p -t "$target" '#{pane_in_mode}')"
dead="$(tmux display-message -p -t "$target" '#{pane_dead}')"
active="$(tmux display-message -p -t "$target" '#{pane_active}')"

printf 'TARGET=%s\nCOMMAND=%s\nPANE_IN_MODE=%s\nPANE_DEAD=%s\nPANE_ACTIVE=%s\n' "$identity" "$cmd" "$in_mode" "$dead" "$active"

if [ "$dead" = "1" ]; then
  printf '%s\n' 'CLASSIFICATION=dead-pane' 'HUNG_CLAIM=not-established' 'EXIT_CONTRACT=none; inspect pane death status and bounded non-sensitive history before recovery.'
  exit 5
fi

if [ "$in_mode" = "1" ]; then
  printf '%s\n' 'CLASSIFICATION=tmux-copy-mode' 'HUNG_CLAIM=no' 'WAITING_FOR=navigation-or-exit' 'EXIT_CONTRACT=press q to leave tmux copy mode'
  exit 0
fi

case "$cmd" in
  nano)
    printf '%s\n' \
      'CLASSIFICATION=modal-editor:nano' \
      'HUNG_CLAIM=no' \
      'WAITING_FOR=editor-input' \
      'EXIT_CONTRACT=Ctrl+X; if prompted, N discards changes, or Y then Enter saves the shown filename' \
      'PROMPT_FILE_RULE=A sprint prompt file contains task instructions, not the shell setup commands used to create or launch it.'
    ;;
  less|more)
    printf '%s\n' 'CLASSIFICATION=modal-pager' 'HUNG_CLAIM=no' 'WAITING_FOR=navigation-or-exit' 'EXIT_CONTRACT=press q to leave the pager'
    ;;
  vi|vim|nvim)
    printf '%s\n' 'CLASSIFICATION=modal-editor:vi-family' 'HUNG_CLAIM=no' 'WAITING_FOR=editor-input' 'EXIT_CONTRACT=press Esc, then :q! Enter to discard or :wq Enter to save and exit'
    ;;
  sh|bash|zsh|fish)
    printf '%s\n' 'CLASSIFICATION=shell-ready' 'HUNG_CLAIM=no' 'WAITING_FOR=shell-command' 'EXIT_CONTRACT=not-applicable'
    ;;
  *)
    printf 'CLASSIFICATION=foreground-process:%s\nHUNG_CLAIM=not-established\nWAITING_FOR=application-specific\nEXIT_CONTRACT=inspect the owning workflow before sending keys; do not guess that the process is hung.\n' "$cmd"
    ;;
esac
