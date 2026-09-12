---
id: opinion-ledger-tracer
status: experimental
owner: tooling/harness/operational/opinion-ledger
---

# Opinion Ledger Tracer

## Trigger

Use this skill when an operator wants a reusable engineering judgment, preference, correction, or decision to remain searchable for later AgentSwitchboard sessions without promoting that judgment to repository law.

Use it for candidate statements such as "prefer bounded evidence over process-exit confidence" or "phone UX should use native interaction paths." Do not use it for unfinished repository work, personal accomplishment history, sensitive health history, credentials, or current tool/schema facts that must be grounded from their canonical source.

## Authority boundary

- `AGENTS.md` and current canonical repository owners outrank every opinion candidate.
- `.ai/WORK_QUEUE.md` remains the unfinished-work coordination ledger.
- Candidate opinions are advisory context only. They never grant execution, mutation, deployment, credential, provider, merge, or approval authority.
- Raw chat can supply evidence for a candidate, but chat memory is not canonical repository truth.
- Promotion is a separate reviewed change to the real doctrine, skill, ADR/spec, validator, policy, or implementation owner.

## Storage

The runner derives a local state path; it never stores candidate content in Git by default.

Windows:

`%LOCALAPPDATA%\AgentSwitchboard\opinion-ledger\opinions.jsonl`

POSIX:

`${XDG_STATE_HOME:-~/.local/state}/agentswitchboard/opinion-ledger/opinions.jsonl`

For deterministic isolation, pass `--state-root` or set `AGENTSWITCHBOARD_OPINION_STATE_ROOT`. Do not replace an unavailable Windows `LOCALAPPDATA` with an invented Desktop, OneDrive, or repository path.

## Procedure

1. Resolve the verified AgentSwitchboard repository root through the current harness/repository context. Do not assume the current working directory, Desktop, OneDrive, or a remembered clone path.
2. Read current repository law and the owning source for the subject before recording an opinion as reusable context.
3. Keep the candidate concise and scoped. Do not record secrets or sensitive personal material.
4. Invoke the canonical runner by its absolute path so the command is independent of the caller's current directory:

```text
python "<verified-AgentSwitchboard-root>/tooling/harness/operational/opinion-ledger/opinion_ledger.py" record --text "<opinion>" --scope "<scope>" --source-type operator --confidence medium --tag "<tag>"
```

5. Search later through the same verified runner path:

```text
python "<verified-AgentSwitchboard-root>/tooling/harness/operational/opinion-ledger/opinion_ledger.py" search --query "<literal query>"
```

6. Treat results as candidate context. Re-check current source truth before acting.
7. If a candidate repeatedly proves useful and should become repository behavior, open a separate reviewed change against the actual canonical owner. Do not mutate canonical doctrine automatically from this tracer.

## Outputs

- local untracked `opinions.jsonl` under the resolved state root;
- JSON command output containing the resolved local path and candidate/search result;
- no tracked opinion content and no remote synchronization.

## Deterministic validation

Run repository tests from the verified AgentSwitchboard root, then exercise the runner by absolute path:

```text
python -m unittest tests.test_opinion_ledger_tracer -v
python "<verified-AgentSwitchboard-root>/tooling/harness/operational/opinion-ledger/opinion_ledger.py" --state-root <temp-path-outside-repo> state-root
```

Operational-harness and repository-work-ledger validators remain owning regression gates when their surfaces change.

## Forbidden scope

- no personal accomplishment or health-history ingestion;
- no passwords, tokens, keys, recovery codes, or private credentials;
- no tracked opinion content;
- no SQLite, FTS, vector store, MCP server, GitHub sync, or Drive sync in tracer v1;
- no automatic promotion to doctrine;
- no opinion-based tool/argument/schema authority;
- no execution or mutation authorization from an opinion;
- no competing work queue or replacement for repository evidence.

## Stop and escalate

Stop and use the canonical source instead when the requested memory is actually a current technical fact, permission, credential, live runtime state, deployment state, or unresolved repository task. Stop rather than record sensitive personal material when a narrower private system owns it.
