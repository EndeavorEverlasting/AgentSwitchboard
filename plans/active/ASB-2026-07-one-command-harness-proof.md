# One-command Synthetic Harness Proof

- Plan: `ASB-2026-07-ONE-COMMAND-HARNESS-PROOF`
- Branch: `feat/one-command-harness-proof`
- Base: `feat/public-plans-startup-readiness`
- Lane: validation / harness proof
- Status: active

## Mission

Provide one offline command that observes the registered AgentSwitchboard harness composition, validates required nodes and event edges, runs bounded safe validators, and emits an honest PASS/SKIP/FAIL matrix plus JSON evidence.

## Event observer model

The harness now has an explicit composition graph. Requests and root commands cascade into the observer; the observer checks contracts, schemas, validators, artifact registration, report rendering, hook hygiene, and optional MCP/LSP readiness; results cascade into JSON and English output artifacts.

A missing required node, dangling edge, disconnected cascade, unsafe validator, or failed required validator is a failure. Optional MCP/LSP readiness is skipped with a precise reason when no offline project index is loaded.

## Safety and proof boundary

The validator is offline and synthetic. It does not launch AgentSwitchboard, GNHF, a game, browser, provider, installer, agent, MCP/LSP service, or deployment surface. It does not probe a network, mutate target repositories, saves, accounts, or customer data, or claim live event delivery.

## Validation

Exact-head Windows and Linux CI remain the final proof gate. Generated `app-harness-validation.json` and `app-harness-validation.md` remain outside Git.
