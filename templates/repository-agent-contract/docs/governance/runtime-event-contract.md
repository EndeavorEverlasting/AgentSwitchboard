# Runtime Event Contract

Canonical source: `EndeavorEverlasting/AgentSwitchboard`
Pinned contract version: `REPLACE_CONTRACT_VERSION`
Policy: `.ai/harness/runtime-event-contract.policy.json`

Runtime event work registers this chain:

`event source -> typed event envelope -> observer or listener -> handler -> emitted successor event -> artifact or evidence sink`

A root event uses its event ID as correlation ID, has no causation ID, and starts at sequence zero. A successor uses a new event ID, inherits correlation, identifies its parent event as causation, and advances sequence.

Emitted envelopes are immutable. Every source, observer, handler, sink, event type, and edge belongs in the repository's machine-readable runtime topology.

Static topology does not prove runtime delivery. Synthetic fixtures do not prove application execution. A runtime claim requires correlated source, observer, handler, successor or terminal, and sink evidence from an authorized runtime lane.

A request that claims an event listener, observer, trigger cascade, or runtime event path requires corresponding tracked implementation, validation, commit or GitHub evidence, and an honest proof ceiling. A plan or rewritten prompt is not a substitute.

Validate with `scripts/Test-RuntimeEventContract.ps1`. Local rules may strengthen this doctrine. They may not weaken it.
