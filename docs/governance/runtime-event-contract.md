# Runtime Event Contract

Machine-readable authority: `.ai/harness/runtime-event-contract.policy.json`.

This contract governs any AgentSwitchboard feature that claims to emit, observe, route, handle, cascade, or record runtime events. It extends the commit-required harness doctrine; it does not replace task-specific execution contracts or grant runtime authority.

## Required event chain

Every runtime event path must register and prove the composition it claims:

`event source -> typed event envelope -> observer or listener -> handler -> emitted successor event -> artifact or evidence sink`

The runtime topology registry must name every participating source, observer, handler, sink, event type, and directed edge. Unregistered nodes or edges are outside the proof boundary and may not be described as covered.

## Typed envelope

Every event uses the closed schema `.ai/harness/schemas/runtime-event-envelope.schema.json` and includes:

- schema version;
- unique event ID;
- stable event type;
- registered source node and component;
- UTC occurrence time;
- correlation ID;
- causation ID or null for a root;
- monotonic sequence within the correlation chain;
- minimized payload;
- sensitivity and redaction metadata.

An emitted envelope is immutable. Observers and handlers may derive new evidence or successor events, but they must not rewrite the original event identity, source, time, payload, correlation, or causation.

## Correlation and causation

A root event starts a chain:

- `correlationId == eventId`;
- `causationId == null`;
- `sequence == 0`.

A successor event continues its parent chain:

- it receives a new event ID;
- it inherits the parent correlation ID;
- its causation ID equals the parent event ID;
- its sequence is greater than the parent sequence.

An orphaned successor, rewritten correlation ID, missing parent, duplicate event ID, or non-advancing sequence is a contract failure.

## Observer, handler, and sink responsibilities

- A source emits one immutable typed envelope.
- An observer records receipt and dispatches the same envelope without mutation.
- A handler reports its decision and may emit zero or more typed successor events.
- A successor event preserves the correlation chain and identifies its immediate cause.
- An evidence sink records enough structured data to reconstruct the declared cascade without collecting secrets or unnecessary payloads.

Observer or handler failure must be represented as evidence. Silent loss, swallowed exceptions, and success claims without a terminal event or explicit failure event are invalid.

## Topology registration

`.ai/harness/runtime-event-topology.json` is the machine-readable registry for runtime composition. Every required node has a registered kind and every required edge names its source, destination, relationship, and event type.

The initial registry is `contract-only`. It proves doctrine shape and synthetic fixture connectivity only. Product implementations must add their actual nodes and edges through reviewed tracked changes before claiming coverage.

## Proof promotion

Proof advances in bounded stages:

1. **Contract** — schemas, policy, topology, and validators pass.
2. **Synthetic cascade** — deterministic fixtures prove root and successor causality.
3. **Runtime observed** — an authorized runtime lane captures emitted, observed, handled, successor, and sink evidence for one correlation chain.
4. **Live target** — separately authorized target evidence proves the same chain in its intended environment.

Static topology does not prove runtime delivery. Synthetic fixtures do not prove application execution. Process exit alone does not prove a cascade. A runtime completion claim requires correlated artifacts showing the source event, observer receipt, handler decision, successor event or explicit terminal result, and evidence-sink record.

## Action-commitment rule

A prompt, title, mission, or expected output that claims it will build, install, repair, configure, or prove an event listener, observer, trigger cascade, handoff, or runtime event path must require corresponding tracked implementation and evidence.

A valid execution contract names the affected nodes and edges, mutates deterministic code or contracts, validates the event envelope and topology, records commit or GitHub evidence, and states the achieved proof level and ceiling. A rewritten prompt, architecture note, plan, or handoff is not a substitute for requested implementation.

## Safety and data boundaries

- Do not place credentials, tokens, customer data, private hostnames, or raw sensitive payloads in event fixtures, public plans, or tracked evidence.
- Minimize and redact payloads before evidence capture.
- Runtime execution requires an explicitly authorized runtime lane.
- External target, account, save, deployment, merge, or release mutation requires separate explicit authority.
- Generated event evidence is untracked and operator-controlled unless a repository-specific public fixture is deliberately reviewed.

## Validation

Run:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-RuntimeEventContract.ps1
```

Then run the aggregate offline observer:

```powershell
.\Test-AppHarness.cmd
```

These checks prove the tracked contract and synthetic causality fixtures only. They never launch AgentSwitchboard or claim runtime delivery.
