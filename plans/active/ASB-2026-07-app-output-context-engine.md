# App Output Context Engine

This sprint builds a deterministic offline harness component that converts supplied application, agent, tool, or validator output into compact prompt-kit-aware instructions.

The engine reads text, JSON, or JSONL; hashes but does not copy the raw input; redacts common credentials and private identifiers; classifies failure and warning signals; ranks prompts only inside the requested execution surface; and emits schema-backed JSON plus an English report.

The full prompt-kit snapshot remains owned by the separate prompt-registry consumer delivery. This branch validates the generic registry interface with a small public fixture.

Proof is limited to offline parsing, redaction, deterministic ranking, artifact rendering, and repository contract registration. No source application, provider, prompt, repository task, launcher, or target behavior is executed or proven.
