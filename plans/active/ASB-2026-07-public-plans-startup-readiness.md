# Public Plans and Startup Readiness

**Plan ID:** `ASB-2026-07-PUBLIC-PLANS-STARTUP`  
**Status:** active  
**Branch:** `feat/public-plans-startup-readiness`

## Mission

Make `plans/` the public coordination surface for agents and make AgentSwitchboard startup explain which local agents are adapter-ready, blocked, or still require runtime verification.

## Delivered in this branch

- public plan registry and schema;
- canonical public-plan coordination skill, capabilities, and triggers;
- read-only startup readiness JSON and English report;
- root `AgentSwitchboard.cmd` startup launcher;
- deterministic fixtures, validators, and Windows/Linux CI;
- reusable child-repository plan template.

## Remaining rollout

`ROLLOUT-01` propagates the plan directory through separate child-repository pull requests. The template is ready, but each child remains authoritative for local specialization and acceptance.

## Proof boundary

Repository and fixture evidence cannot prove provider authentication, quota, hosted response, or operator acceptance. Startup reports intentionally say `verification-required` when those facts were not locally and safely observed.
