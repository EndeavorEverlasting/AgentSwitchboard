# WSL Workstation Agent Contract

This subtree owns Windows-to-WSL workstation setup, repair, proof, and operator-facing automation.

## Read first

For OpenCode free-default repair work, read in this order:

1. `tooling/wsl/AGENTS.md`
2. `tooling/wsl/harness/opencode-free-defaults/CODEBASE_MAP.md`
3. `tooling/wsl/harness/opencode-free-defaults/workflow.json`
4. `.ai/skills/opencode-free-defaults-repair/SKILL.md`
5. `tooling/wsl/Invoke-OpenCodeFreeDefaultsRepair.ps1`
6. `tooling/wsl/Set-OpenCodeFreeDefaults.ps1`
7. `tooling/wsl/tmux-gnhf-workstation.example.json`
8. focused validators and current PR evidence

## Trigger

Route to the OpenCode free-default repair workflow when the operator asks to install, repair, reapply, verify, or recover the managed OpenCode configuration used by WezTerm, WSL Ubuntu, or tmux.

## Required sprint identity

Name:

- repository;
- branch or worktree;
- PR or sprint;
- lane;
- owned scope;
- forbidden scope;
- expected artifacts;
- validation order.

## Operating rules

- Use the repository-owned entrypoint. Do not reconstruct the successful recovery transcript by hand.
- Resolve and enter the repository before Git or installation work.
- Preserve dirty or divergent checkouts. Use an isolated detached worktree for the validated remote head.
- Verify that a supplied commit belongs to the selected remote branch before execution.
- Never reset, clean, delete, rebase, or force-push as part of workstation recovery.
- Never execute a Windows-mounted Bash script directly; normalize to LF and stage it inside WSL.
- Treat missing `jq` as a declared Ubuntu dependency and install it only through the manifest-authorized bounded dependency path.
- Do not read, print, move, or modify provider credentials.
- The managed ordinary OpenCode lane may expose only the reviewed free-model allowlist. Paid model selection requires a separate explicit route.
- Produce machine-readable run context and artifact registry, an English operator report, and a compressed final handoff for every apply or plan run.
- Local runtime outputs belong under `%LOCALAPPDATA%\AgentSwitchboard\OpenCodeFreeDefaults\runs\`; do not commit them.
- Process exit zero is not enough. Independently read back the effective OpenCode model, small model, sharing state, and whitelist.

## Known traps

- A detached interactive PowerShell `else`, `elseif`, `catch`, or `finally` is invalid after the preceding statement was submitted. User-facing examples must use a complete script block or guard clauses.
- Windows Git line-ending conversion can corrupt Bash options.
- A free model configured globally can still be overridden by an explicit OpenCode `--model` or process-local `OPENCODE_CONFIG_CONTENT`.
- A successful configuration write does not prove provider authentication or hosted-model availability.

## Validation order

1. PowerShell parser and JSON/schema parsing;
2. `tooling/wsl/Test-OpenCodeFreeDefaultsHarness.ps1`;
3. `tooling/wsl/tests/test_opencode_free_defaults_harness.py`;
4. existing OpenCode transport and workstation contracts;
5. `git diff --check` and final Git review;
6. exact-head CI.

## Completion contract

Report files changed, validation commands and exact results, commit SHA, push and PR state, local artifact paths when observed, proof level, proof ceiling, final Git state, and one exact next command.
