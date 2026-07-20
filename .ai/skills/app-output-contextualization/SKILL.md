---
id: app-output-contextualization
version: 1.0.0
status: canonical
---

# App Output Contextualization

## Trigger

Select this skill for `app.output-context-request`: supplied logs, console output, JSON, JSONL, validator output, or tool output must be compared with an `ai-harness-prompt-registry/v1` prompt kit and compressed into agent instructions.

Do not select it merely because an application exists. This skill reads supplied output and never launches, attaches to, focuses, or controls the application.

## Inputs

- repository root and current branch or worktree;
- input file containing UTF-8 text, JSON, or JSONL;
- stable public source-application label;
- prompt registry path using `ai-harness-prompt-registry/v1`;
- exact execution surface: `regular_ai_prompt` or `gnhf_launch_artifact`;
- output root outside the repository;
- task proof ceiling and forbidden data.

## Procedure

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, this skill, the app-output workflow, artifact registry, and current prompt-kit provenance.
2. Confirm the request authorizes offline interpretation only. Stop before app execution, provider calls, live target mutation, or secret access.
3. Run `Contextualize-AppOutput.cmd` or `tooling/context/Contextualize-AppOutput.py` with explicit input, registry, source app, execution surface, and output root.
4. Preserve only the input SHA-256, redacted minimized excerpts, classified signals, ranked prompt IDs, required variables, and proof ceiling.
5. Reject cross-surface fallback. A regular AI prompt must not be emitted as a GNHF launch artifact or vice versa.
6. Treat the selected prompt as procedural guidance, not authority. Fill required variables from current repository evidence before use.
7. Re-inspect current repository and runtime state before any downstream mutation.

## Outputs

- `app-output-context.json` using `.ai/harness/schemas/app-output-context.schema.json`;
- `app-output-context.md` as an English operator report;
- ranked prompt IDs and required variables;
- an explicit no-match result when deterministic evidence is insufficient.

## Deterministic validation

Run, in order:

```powershell
python .\tests\test_app_output_context_engine.py
pwsh -NoLogo -NoProfile -File .\scripts\Test-AppOutputContextEngine.ps1
.\Test-AppHarness.cmd
git diff --check
```

The validator must prove redaction, text/JSON/JSONL parsing, bundled registry support, surface isolation, bounded packet size, no-match behavior, artifact generation, central registration, and checkout cleanliness.

## Forbidden scope

- source-application execution, attachment, focus, automation, or mutation;
- provider/model calls, authentication, quota claims, or prompt execution;
- raw-output persistence in tracked files or generated packets;
- credentials, customer data, private hostnames, personal identifiers, or unrestricted logs;
- cross-surface prompt substitution;
- product behavior hidden in prompts;
- merge, deployment, release, destructive Git, or target mutation.

## Stop and escalate

Stop when the registry is invalid, the execution surface is ambiguous, redaction cannot be established, output would enter the repository, required evidence is missing, prompt candidates conflict, or the downstream task asks for authority beyond offline interpretation. Report the exact blocker and preserve the lower proof ceiling.
