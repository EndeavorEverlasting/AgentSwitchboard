---
id: powershell-interactive-execution
version: 1.1.0
status: canonical
---

# PowerShell Interactive Execution

## Trigger

Use whenever executable PowerShell is intended for interactive copy/paste or direct entry at a PowerShell prompt. A saved `.ps1` implementation, explanatory prose, terminal output, or another shell does not activate this skill by itself.

Use this skill especially when the operator may submit a snippet one block at a time, when native commands must preserve `$LASTEXITCODE`, or when a prior terminal failure involved detached `else`, `elseif`, `catch`, or `finally` syntax.

`operator-command-delivery` owns the generic executable/operator command boundary. This skill owns PowerShell grammar, submission boundaries, and immediate native exit-code capture.

## Inputs

- exact target shell: Windows PowerShell 5.1 or PowerShell 7;
- delivery mode: `interactive-copy-paste` or `script-file`;
- target repository or working directory;
- command text or candidate artifact path;
- intended submission boundary: one physical line, one outer script block, or a saved file;
- native commands whose exit codes must be preserved;
- owned mutation and validation scope.

## Procedure

1. **Prefer a repository-owned `.cmd` or `.ps1` entrypoint** over a long interactive bootstrap whenever one exists.
2. Resolve, validate, and enter the intended directory before Git, installation, validation, or implementation logic. Use `Set-Location -LiteralPath` when the artifact itself must change directory.
3. For interactive snippets, prefer guard clauses when later logic does not require a continuation keyword.
4. Keep each compound statement in the same syntactic submission. Never split `if`/`elseif`/`else` or `try`/`catch`/`finally` across separate interactive submissions.
5. Keep every continuation keyword attached to the preceding closing brace in the same parsed statement: `} elseif (...) {`, `} else {`, `} catch {`, and `} finally {`. **Never instruct the operator to submit a closing `}` and then enter `else`, `elseif`, `catch`, or `finally` as a later command.**
6. When a multiline compound statement is unavoidable, enclose the complete statement in one outer `& { ... }` block so PowerShell cannot execute the first completed inner block before the rest of the paste arrives.
7. A one-physical-line compound statement is acceptable only when it remains readable and bounded. Do not compress a large workflow into a giant one-liner just to avoid multiline syntax.
8. Capture `$LASTEXITCODE` **immediately after each native command** when later logic depends on it. Do not run another native command first.
9. Avoid fragile line-continuation backticks when a single command, splatting, an argument array, a repository-owned script, or one complete script block is practical.
10. Preserve existing work before branch, worktree, merge, rebase, reset, or cleanup operations. Never make destructive Git recovery incidental to command delivery.
11. Label the shell context and provide the exact expected next state or artifact.

## Safe forms

Guard clause with no continuation dependency:

```powershell
$repo = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $repo) {
    throw 'Repository could not be resolved.'
}
Set-Location -LiteralPath (($repo -join '').Trim())
```

Atomic multiline compound statement:

```powershell
& {
    if ($a) {
        $x = 1
    } elseif ($b) {
        $x = 2
    } else {
        $x = 3
    }
}
```

Immediate native exit-code capture:

```powershell
& git fetch --no-tags origin main
$fetchExit = $LASTEXITCODE
if ($fetchExit -ne 0) {
    throw "git fetch failed with exit code $fetchExit"
}
```

## Outputs

- repository-owned launcher when one already exists, otherwise one syntactically complete PowerShell artifact;
- explicit `interactive-copy-paste` versus `script-file` delivery boundary;
- no detached `elseif`, `else`, `catch`, or `finally` submission;
- immediate native-command exit handling where required;
- bounded validation and final-state checks;
- one exact next command when follow-up is required.

## Deterministic validation

A user-facing interactive PowerShell artifact must satisfy these checks:

- directory resolution and `Set-Location -LiteralPath` occur before repository logic when the command changes directory;
- no snippet boundary occurs between `}` and `else`, `elseif`, `catch`, or `finally`;
- a necessary multiline compound construct is delivered as one complete block, preferably `& { ... }`;
- native exit codes are captured before another native command can overwrite them;
- a tracked `.cmd`/`.ps1` is preferred when it already owns the workflow;
- destructive Git operations are absent unless explicitly authorized;
- paths use `$HOME`, `$env:LOCALAPPDATA`, `$PSScriptRoot`, or another validated variable rather than a hardcoded username.

Repository regression:

```powershell
python -m unittest tests.test_powershell_interactive_execution_skill
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git --no-pager diff --check
```

## Forbidden scope

- No standalone `else`, `elseif`, `catch`, or `finally` command in an interactive sequence.
- No claim that a multiline example is safe to paste piecemeal when syntax requires one submission.
- No giant interactive bootstrap when an equivalent tracked launcher already exists.
- No reliance on the inherited working directory when repository identity matters.
- No hardcoded workstation username when variables are available.
- No native command whose exit code is inspected only after another native command ran.
- No reset, discard, force-push, stash, clean, or branch deletion as an incidental recovery step.
- No ownership claim over repository selection, runtime proof, provider routing, or product behavior.

## Stop and escalate

Stop and rewrite the artifact when interactive submission boundaries are ambiguous, a continuation keyword could become detached, the target shell or delivery mode is uncertain, native exit-code ownership is unclear, or safe execution would require repository/path guessing or destructive recovery. Prefer one complete repository-owned script or one atomic PowerShell submission.

## Proof ceiling

This skill proves PowerShell syntax-unit, submission-boundary, and immediate native-exit-code delivery rules for validated artifacts. It does not prove the command succeeds, mutates the intended state, or produces runtime behavior on the operator machine.
