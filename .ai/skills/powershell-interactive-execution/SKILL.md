---
id: powershell-interactive-execution
version: 2.0.0
status: canonical
---

# PowerShell Interactive Execution

## Trigger

Trigger ID: `powershell.interactive-snippet`

Select this skill only when executable PowerShell is intended for interactive copy/paste or direct entry at a PowerShell prompt. A saved `.ps1` implementation, explanatory prose, terminal output, or another shell does not activate this skill.

The generic presentation layer is owned by `operator-command-envelope`. Repository identity and safe branch/worktree selection are owned by `repo-intake` and `bounded-sprint`. This skill owns PowerShell grammar and interactive submission boundaries only.

## Inputs

- exact target shell: Windows PowerShell 5.1 or PowerShell 7;
- delivery mode: `interactive-copy-paste` or `script-file`;
- command text or candidate artifact path;
- intended submission boundary: one physical line, one outer script block, or a saved file;
- native commands whose exit codes must be preserved.

## Preconditions

- The target shell is PowerShell.
- The operator is expected to execute the artifact interactively when `deliveryMode=interactive-copy-paste`.
- Repository identity, authority, and mutation scope have already been resolved by the owning workflow.
- The artifact is validated before it is presented as copy-ready.

Repository and path selection remain delegated. When the final artifact itself must change directory, it validates the path and uses `Set-Location -LiteralPath` before repository commands. It never embeds a hardcoded workstation username.

## Procedure

1. Prefer a repository-owned `.cmd` or `.ps1` entrypoint over a long interactive bootstrap.
2. Prefer guard clauses when later logic does not require a continuation keyword.
3. Keep each compound statement in the same syntactic submission. Never split `if`/`elseif`/`else` or `try`/`catch`/`finally` across separate interactive submissions.
4. Keep every continuation keyword attached to the preceding closing brace on the same physical line: `} elseif (...) {`, `} else {`, `} catch {`, and `} finally {`. Never instruct the operator to submit a closing `}` and then enter the continuation later.
5. When a multiline compound statement is unavoidable, enclose the complete statement in one outer `& { ... }` script block so PowerShell cannot execute the first completed inner block before the rest of the paste arrives.
6. A one-physical-line compound statement is acceptable when readable and bounded.
7. Capture `$LASTEXITCODE` immediately after a native command when later logic depends on it.
8. Validate the final candidate through `scripts/Test-SkillFactoringContracts.ps1 -CandidatePath <path>`.

## Safe forms

Guard clause with no continuation dependency:

```powershell
if (-not $repo) {
    throw 'Repository could not be resolved.'
}
$head = (& git.exe -C $repo rev-parse HEAD).Trim()
```

One physical line:

```powershell
if($a){$x=1}elseif($b){$x=2}else{$x=3}
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

## Outputs

- one syntactically complete interactive PowerShell artifact;
- no detached `elseif`, `else`, `catch`, or `finally` submission;
- explicit submission-boundary classification;
- immediate native-command exit-code handling;
- deterministic validation report when a candidate artifact is supplied.

## Guardrails

- A multiline interactive compound statement must be one outer `& { ... }` block.
- Continuation keywords must remain on the same physical line as the preceding closing brace.
- Multiple code fences or commands must not divide one compound statement.
- Script-file syntax is not falsely rejected as interactive syntax.
- Shell prompts, transcripts, and diagnostics remain the responsibility of `operator-command-envelope` and its validator.
- Application logic remains in scripts, modules, schemas, registries, and workflows—not in this skill.

## Owning files

- `.ai/skills/powershell-interactive-execution/SKILL.md`
- `tooling/skills/harness/command-delivery/skill-factoring.registry.json`
- `tooling/skills/skill_factoring_contracts.py`
- `scripts/Test-SkillFactoringContracts.ps1`
- `tests/test_skill_factoring_contracts.py`

## Deterministic validation

```powershell
python -m unittest tests.test_skill_factoring_contracts
pwsh -NoLogo -NoProfile -File scripts/Test-SkillFactoringContracts.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-SkillFactoringContracts.ps1
```

Validate one handoff artifact:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-SkillFactoringContracts.ps1 -CandidatePath '<handoff.md>' -CandidateDeliveryMode interactive-copy-paste
```

## Forbidden scope

- No standalone `elseif`, `else`, `catch`, or `finally` command is permitted in an interactive sequence.
- One compound statement is split across multiple interactive submissions or code fences.
- A multiline compound statement with continuation keywords is emitted without an outer `& { ... }` block.
- A continuation keyword starts a new physical line after the preceding block closes.
- The skill claims repository selection, runtime proof, provider routing, or product behavior ownership.

## Stop and escalate

Stop and rewrite the artifact when the submission boundary is ambiguous, a continuation keyword can become detached, the target shell is uncertain, or safe execution would require repository/path guessing or destructive recovery. Preserve state and emit one complete repository-owned script or one atomic PowerShell submission instead.

## Proof ceiling

This skill and its validator prove interactive PowerShell syntax-unit and submission-boundary safety for the validated artifact. They do not prove the command succeeds, mutates the intended state, or produces runtime behavior on the operator machine.
