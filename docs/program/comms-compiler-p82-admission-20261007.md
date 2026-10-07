# P82 Experiment Admission Record — CommsCompiler MVP

Date: 2026-10-07

## Selected thesis

A declarative project adapter plus a deterministic pre-render compiler can catch the known completeness and topic-separation failures that recur when a drafting model is asked to recover project truth and write prose in one step.

## Direct repository fact

AgentSwitchboard is the repository-family policy/routing/evidence owner and already uses deterministic schemas, registries, static gates, and synthetic fixtures as guardrails around agent judgment.

## Independent corroborating signal

The H&H communications workflow required a 54-item ticket-alignment message with exact status grouping and only ticket identity/classification detail, while badge renewals had to remain a separate communication. The recurring failure class was omission or excess detail despite the authoritative evidence already existing.

## Alternatives dispositioned

- Put the service inside H&H: rejected for this experiment because it would couple the writer to one project.
- Put the service inside SysAdminSuite: rejected as canonical ownership; SAS is a useful report-rendering prior-art source but is a child/domain repository.
- Build Gmail/Drive integration first: rejected because it tests provider plumbing before the highest-risk correctness question.
- Build an LLM style prompt first: rejected because prose quality cannot compensate for an incomplete fact set.

## Prior falsification / known failure

Freeform drafting without a deterministic coverage gate has repeatedly allowed missing in-scope items, over-detailed rows, and unrelated-topic mixing. The experiment does not treat another prompt rewrite as sufficient prevention.

## Primary empirical uncertainty

Can the smallest real adapter/compiler slice reject representative omission, duplicate/count-drift, and topic-leak faults while accepting the complete ticket-alignment population, without embedding private operational data or project-specific prose in the compiler?

## Falsifiable hypothesis

Given one synthetic H&H ticket-alignment workload with 54 items and expected status totals OPEN=17, PENDING=7, ESCALATED=1, DONE=29:

1. the compiler will PASS the complete packet and authorize only item ID + classification for rendering;
2. it will FAIL an omitted-item packet;
3. it will FAIL duplicate identity;
4. it will FAIL status-count drift;
5. it will FAIL badge-renewal topic leakage;
6. the same valid input will produce byte-equivalent canonical JSON content after key sorting;
7. tracked adapter/fixture content will contain no live incident number, Drive URL, or email address.

## Baseline / comparator

Baseline: an ungated drafting path has no deterministic rejection mechanism and therefore detects 0/4 seeded structural faults before prose generation.

Comparator: CommsCompiler must detect 4/4 seeded structural faults while accepting the valid fixture.

## Bounded prototype boundary

Owned:

- project-adapter schema;
- deterministic compiler/validator;
- first `hh-fieldops` adapter;
- one synthetic 54-item fixture;
- focused regression test;
- architecture/wayfinding registration.

Forbidden:

- live Drive/Gmail access or mutation;
- LLM prose generation;
- real ticket IDs or customer/private evidence;
- changes to H&H or SysAdminSuite repositories;
- merge/deployment claims.

## Measurement plan

Run `python tests/test_comms_compiler.py`. Record positive-fixture result, seeded-fault detection count, baseline detection count, deterministic repeatability, and privacy scan result. Then run the repository automated-test floor after the new gate is registered.

## Decision rule

- **PROMOTE**: valid fixture PASS, compiler detects 4/4 seeded faults, baseline detects 0/4, deterministic repeatability passes, privacy scan passes, and repository static floor remains green. Next route: P07 for a read-only live source adapter.
- **WEAKEN**: compiler catches only a subset or requires project-specific prose/hard-coded ticket IDs; narrow the claim and retain only proven gates.
- **REJECT**: adapter/compiler cannot distinguish valid vs seeded faulty packets without becoming the full application or leaking private operational truth.
- **INCONCLUSIVE**: test harness/fixture is defective but the same thesis remains repairable; repair once and rerun before changing the thesis.

## Measured result

Focused prototype: PASS.

- valid 54-item fixture: PASS;
- seeded structural faults detected: 4/4;
- ungated baseline structural faults detected: 0/4;
- deterministic repeatability: PASS;
- tracked adapter/fixture privacy scan: PASS;
- repository automated-test floor: pending branch integration/CI.

P82 disposition remains **INCONCLUSIVE** until the repository floor is green. The thesis is not promoted on focused proof alone.
