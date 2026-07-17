# Cross-domain GNHF Runtime Contract

This contract separates terminal presentation from process compatibility. A command being visible on `PATH` does not prove that it is native to the shell domain that will execute it.

## Supported execution domains

| Runtime path | Status | Contract |
|---|---|---|
| WezTerm → WSL Ubuntu → tmux → WSL-native Git, Node, GNHF, and OpenCode | Supported for the workstation live-proof lane | Every executable must resolve inside the Linux filesystem, the tmux/WezTerm geometry must be usable, and GNHF output is captured to a bounded log rather than treated as pixel-level GUI proof. |
| WezTerm → native Windows PowerShell → Windows AgentSwitchboard → Windows GNHF and Windows agent CLIs | Supported by Windows-native desktop and fleet lanes | Keep the process tree in the Windows domain. Do not route the interactive Windows TUI back through WSL tmux. |
| WSL tmux → Windows-mounted GNHF or agent wrapper under `/mnt/<drive>/...` | Blocked for the WSL GNHF proof | Windows PATH inheritance and compatibility wrappers do not establish a WSL-native Node or terminal backend. The proof is blocked before GNHF starts. |
| WSL → explicit Windows bridge for a bounded noninteractive probe | Conditional | The owning workflow must declare the bridge, capture a typed result, avoid interactive TUI claims, and never promote process exit alone to behavior proof. |

## Why the guard exists

A mixed-domain interactive run can start successfully and still fail when the agent backend tries to create a shell, locate `git`, invoke `npm`, or open a worktree file. Typical evidence includes `terminal/create`, `ENOENT`, `Error handling request`, malformed JSON-RPC output, missing-file errors, or a visually corrupted TUI.

Those signals are runtime failures even when GNHF itself returns exit code zero.

The live-proof lane therefore requires:

- WSL-native `git`, `node`, `gnhf`, and `opencode` paths;
- no required executable resolving through `/mnt/<drive>/...` or a Windows script/executable suffix;
- a WezTerm/tmux client and pane at least `80x24` and below the absurd-geometry ceiling;
- log-captured, noninteractive GNHF presentation for deterministic proof;
- rejection of terminal-spawn or filesystem-backend errors found in the GNHF log;
- an exact committed disposable proof artifact.

## Commit proof and failed worktrees

No commit means no successful sprint. Exit code zero, route selection, token use, generated notes, or uncommitted file edits are not substitutes for a commit ahead of the base.

When a route leaves changes without a commit, automatic fallback must remain blocked until the preserved worktree is inspected. A second model must not inherit unknown partial state merely because another provider is available.

## SysAdminSuite boundary

AgentSwitchboard owns execution-domain detection, terminal compatibility evidence, route classification, and the machine-readable handoff. SysAdminSuite should consume that handoff before launching workstation mutation or runtime-proof lanes, while retaining authority over its own host safety, validators, deployment doctrine, and production evidence.

A future SysAdminSuite adoption sprint should reject handoffs that lack a native-domain toolchain result, usable terminal geometry where a TUI is required, clean commit proof, and an explicit proof ceiling.
