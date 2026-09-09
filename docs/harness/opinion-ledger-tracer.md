# Opinion ledger tracer

The opinion ledger tracer is an optional AgentSwitchboard operational-harness component for retaining reusable engineering judgments without turning chat history into repository law or creating another product prematurely.

## What it owns

The tracer owns only local candidate opinions and deterministic `record` / `search` behavior. Candidate entries are always:

- `local-only`;
- `candidate`;
- `advisory_only=true`;
- `execution_authority=false`;
- unpromoted.

The tracer does **not** own unfinished work, personal accomplishment history, sensitive health history, current provider/runtime facts, credentials, or canonical engineering doctrine.

## Why this is separate from the work queue

`.ai/WORK_QUEUE.md` answers what unfinished AgentSwitchboard work exists and who owns it. The opinion tracer answers which reusable judgments may be worth recalling later. Recording an opinion never creates, closes, claims, or reprioritizes a work-queue item.

## Why this is separate from personal accomplishment history

A personal accomplishment ledger answers what the operator actually completed over time. That human history may consume repository evidence, but AgentSwitchboard does not need to ingest or publish it in order to remember engineering judgments. Keeping the two systems separate reduces privacy leakage and prevents a control-plane harness from becoming a personal diary.

## Candidate-to-authority promotion

The promotion path is deliberately reviewed:

`source/chat/operator evidence -> local candidate opinion -> later review -> actual canonical doctrine/skill/ADR/spec/validator/implementation owner`

A candidate is never self-promoting. Once a principle is promoted into a canonical owner, later agents should use that owner rather than treating the candidate ledger as a competing authority.

## Storage resolution

The runner resolves state in this order:

1. explicit `--state-root`;
2. `AGENTSWITCHBOARD_OPINION_STATE_ROOT`;
3. native OS state location.

Windows requires `%LOCALAPPDATA%` and fails closed if it is unavailable rather than inventing a Desktop, OneDrive, or repository location.

Default Windows file:

`%LOCALAPPDATA%\AgentSwitchboard\opinion-ledger\opinions.jsonl`

Default POSIX file:

`${XDG_STATE_HOME:-~/.local/state}/agentswitchboard/opinion-ledger/opinions.jsonl`

Candidate content is generated evidence and is not tracked.

## Commands

Resolve the path without creating state:

```text
python tooling/harness/operational/opinion-ledger/opinion_ledger.py state-root
```

Record a candidate:

```text
python tooling/harness/operational/opinion-ledger/opinion_ledger.py record --text "Prefer evidence-backed fixed points over first-green stopping." --scope "repository execution" --source-type operator --confidence high --tag evidence
```

Search candidates:

```text
python tooling/harness/operational/opinion-ledger/opinion_ledger.py search --query "fixed points"
```

The search is intentionally literal and dependency-free in v1. SQLite/FTS, semantic/vector search, MCP, remote sync, and Drive integration remain later decisions that require evidence of tracer reuse.

## Failure behavior

- invalid input fails before a ledger file is created;
- malformed JSONL fails closed during search;
- semantically invalid entries fail closed rather than being skipped;
- unavailable Windows state authority blocks default-path resolution;
- no failure authorizes a repository fallback path or remote sync.

## Validation

```text
python -m unittest tests.test_opinion_ledger_tracer -v
```

Changes to the operational manifest or router must also pass the existing operational-harness gates. Changes to `.ai/WORK_QUEUE.md` must pass the repository-work-ledger gates.

## Proof ceiling

Repository tests can prove local record/search behavior, state-path resolution, corrupt-state rejection, routing and contract boundaries. They cannot prove that an opinion is correct, that future agents will apply it wisely, that any provider has persistent memory, or that a candidate deserves promotion.
