---
id: powershell-interactive-execution
version: 1.0.1
status: canonical
---

# PowerShell Interactive Execution

## Trigger

Use whenever PowerShell commands are intended to be pasted or entered interactively, especially when the operator may submit the snippet one block at a time.

## Inputs

- intended PowerShell version and execution domain;
- target repository or working directory;
- whether the artifact will be pasted interactively, saved as a script, or executed as one complete script block;
- external commands whose exit codes must be preserved;
- owned mutation and validation scope.

## Procedure

1. Resolve, validate, and enter the intended directory before Git, installation, validation, or implementation logic.
2. For interactive snippets, avoid `else`, `elseif`, `catch`, and `finally` when a guard clause or second independent condition is clear.
3. When a compound construct is necessary, emit it in the same syntactic submission as the block it continues. Keep `} else {`, `} elseif (...) {`, `} catch {`, and `} finally {` attached to the preceding block. Prefer wrapping the entire runnable snippet in `& { ... }` so the operator pastes it once.
4. Never instruct the operator to submit a closing `}` and then paste `else {` as a later command. PowerShell executes the completed first statement immediately, leaving the later keyword syntactically orphaned.
5. Prefer guard clauses:

```powershell
if (-not $Condition) {
    throw "Required condition was not met."
}

# Continue only after the guard passes.
```

6. When selecting between branches interactively, compute a value or use two explicit conditions when that is clearer than a compound block.
7. Capture `$LASTEXITCODE` immediately after a native command when later logic depends on it.
8. Avoid fragile line-continuation backticks when a single-line command, splatting, an argument array, or a complete script block is practical.
9. Preserve existing work before branch, worktree, merge, rebase, reset, or cleanup operations.
10. Label the shell context and provide the exact expected next state.

## Outputs

- a directory-first PowerShell snippet;
- no detached continuation keyword in an interactive sequence;
- explicit native-command exit handling;
- bounded validation and final-state checks;
- one exact next command when follow-up is required.

## Deterministic validation

A user-facing interactive PowerShell artifact must pass these checks:

- directory resolution and `Set-Location -LiteralPath` occur before repository logic;
- no snippet boundary occurs between `}` and `else`, `elseif`, `catch`, or `finally`;
- a necessary compound construct is delivered as one complete block, preferably `& { ... }`;
- native exit codes are captured before another native command can overwrite them;
- destructive Git operations are absent unless explicitly authorized;
- paths use `$HOME`, `$env:LOCALAPPDATA`, `$PSScriptRoot`, or another validated variable rather than a hardcoded username.

## Forbidden scope

- No standalone `else`, `elseif`, `catch`, or `finally` command in an interactive sequence.
- No reliance on the inherited working directory.
- No hardcoded workstation username when variables are available.
- No reset, discard, force-push, or branch deletion as an incidental recovery step.
- No claim that a multiline example is safe to paste piecemeal when syntax requires one submission.

## Stop and escalate

Stop and rewrite the artifact when interactive submission boundaries are ambiguous, when a continuation keyword could become detached, or when branch recovery would require destructive Git. Preserve the current state and provide one safe, complete script block instead.
