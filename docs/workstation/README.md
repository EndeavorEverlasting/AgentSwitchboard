# Workstation Operator Documentation

Use these guides for workstation, technician, and terminal-client setup. Read the environment-specific guide before executing machine mutations.

| Guide | Audience / workflow | Proof boundary |
|---|---|---|
| [`android-termux.md`](android-termux.md) | Android operator installing Termux, AgentSwitchboard terminal-client files, phone-local tmux, and local Git workflow | Android role ceiling is `terminal-client`; phone-local tmux is `local-shell-only` |
| [`android-ssh-tmux-live-cert.md`](android-ssh-tmux-live-cert.md) | Android + laptop/server operator proving SSH transport and same-host tmux continuity | Separates Windows transport, manual WSL continuity, and repo-owned POSIX/tmux remote preflight |
| [`agent-startup-readiness.md`](agent-startup-readiness.md) | Agent startup/readiness operators | Readiness evidence only; follow its runtime proof boundary |
| [`machine-profile-bootstrap.md`](machine-profile-bootstrap.md) | Machine-profile bootstrap operators | Follow the profile-specific capability/launcher authority |
| [`technician-live-cert-click-guide.md`](technician-live-cert-click-guide.md) | Technician conducting live certification | Operator-visible runtime proof required |
| [`technician-pull-and-run.md`](technician-pull-and-run.md) | Technician pulling reviewed work and running owned validation | Repository/validator evidence is not production/runtime proof |

## Android quick routing

If you have **F-Droid installed but not Termux**, start at [`android-termux.md#part-1--install-termux-from-the-f-droid-app`](android-termux.md#part-1--install-termux-from-the-f-droid-app).

If Termux is installed and you want **phone-local coding**, continue at [`android-termux.md#part-6--phone-local-tmux-code-locally-without-calling-it-remote-continuity`](android-termux.md#part-6--phone-local-tmux-code-locally-without-calling-it-remote-continuity).

If Termux is installed and you want **the same tmux workspace from phone and laptop/server**, use [`android-ssh-tmux-live-cert.md`](android-ssh-tmux-live-cert.md).

## Environment truth rule

For cross-environment work, classify:

```text
frontend -> transport -> workspace host -> orchestration runtime -> agent runtime
```

Repository presence, SSH success, a tmux process, or a matching tmux session name does not promote a lower layer into proof of a higher layer. See `docs/governance/environment-capability-contract.md`.
