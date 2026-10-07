# CommsCompiler MVP contract

| Field | Value |
|---|---|
| Owner | AgentSwitchboard |
| Status | bounded P82 prototype / first implementation slice |
| First adapter | `hh-fieldops-v1` |
| Proof ceiling | deterministic contract + synthetic fixture only |

## Purpose

CommsCompiler is a cross-project communications service that separates evidence compilation from prose generation. A project adapter declares authoritative logical sources, supported communication intents, completeness rules, renderable fields, and separation/privacy constraints. The compiler must fail before prose generation when the evidence packet is incomplete, internally inconsistent, or contains a forbidden topic.

The MVP intentionally stops before live source retrieval or prose generation. It answers one question: can a small declarative adapter plus a deterministic compiler prevent known omission and topic-leak classes before an LLM is allowed to write?

## Pipeline boundary

```text
project evidence -> project adapter -> deterministic fact compilation -> PASS/FAIL render contract -> future prose renderer
```

The MVP owns only the middle two steps. It does not read Google Drive, send Gmail, call an LLM, update a ticket system, or claim that any communication was sent.

## Project adapter contract

A project adapter must declare:

- stable project ID and aliases;
- a logical entry point and authoritative source roles;
- supported communication intents;
- identity, classification, and status fields for population-bearing intents;
- required statuses and evidence sources;
- allowed render fields;
- forbidden cross-topic leakage;
- privacy constraints for tracked adapters and fixtures.

Logical locators are intentional. Public AgentSwitchboard contracts must not embed private Drive URLs, customer identifiers, credentials, or live operational evidence.

## First adapter: H&H Field Operations

`tooling/comms/adapters/hh-fieldops.v1.json` implements the first project adapter for the `ticket_alignment` intent. It preserves the communication rule learned from the October ticket-classification workflow:

- every in-scope tracked item must be represented;
- item identity must be unique;
- status totals must match the declared expected population;
- rendered item detail is limited to item ID plus classification;
- badge-renewal material is a separate communication and must not leak into ticket alignment.

The repository fixture is synthetic. It preserves only the measured shape (54 items grouped 17/7/1/29) and generic classification taxonomy; it contains no live ticket identifiers, Drive links, contact data, or private evidence.

## Compiler result

`tooling/comms/comms_compiler.py` emits `agentswitchboard.comms-compiled-facts/v1` with:

- PASS/FAIL;
- project, adapter, and intent identity;
- observed population and status counts;
- an allowed-field render contract;
- `proseGenerationAuthorized`;
- deterministic violation codes;
- an explicit proof ceiling.

A future prose renderer may consume only a PASS result. A FAIL result is a hard pre-render stop, not a suggestion to improvise around missing evidence.

## MVP non-goals

- no live Google Drive adapter;
- no Gmail draft/send integration;
- no Teams renderer;
- no LLM or prompt selection;
- no automatic recipient inference;
- no cross-project source reconciliation beyond the supplied evidence packet;
- no claim that synthetic/static proof establishes live drafting quality.

## Next promotion boundary

If the P82 measurement promotes this slice, the next bounded implementation owner is P07: add a source-adapter interface and one read-only live H&H evidence loader while preserving this deterministic compiler as the pre-render gate. Prose generation should remain a separate downstream renderer so source correctness and communication style cannot silently collapse into one opaque step.
