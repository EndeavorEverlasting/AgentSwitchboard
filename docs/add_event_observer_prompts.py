#!/usr/bin/env python3
"""Add Event Observer prompts to prompts.json"""
import json

with open("prompts.json", "r", encoding="utf-8") as f:
    prompts = json.load(f)

event_observer_prompts = [
    {
        "id": "P61",
        "seq": "61",
        "name": "Event Observer Architecture Designer",
        "type": "BUILD + SAFETY",
        "class": "BUILD / EVENT OBSERVER",
        "sprintRole": "Design and implement a complete Event Observer system with pragmatic registration, emission, and teardown patterns",
        "progress": "YES",
        "useWhen": "The application needs to observe state changes, user actions, system signals, or cross-component communication without tight coupling. Use when Event Listeners are mentioned to rename and redesign them as Event Observers.",
        "inspectFirst": "Existing event patterns, listener registrations, emitter patterns, teardown lifecycle, component boundaries, and any existing Event Listener code that needs renaming.",
        "expectedOutput": "A tracked Event Observer design document or implementation: observer registry, emission contracts, lifecycle management (register/teardown), typed event maps, and a validator that proves observers fire and clean up.",
        "nextStep": "Run P11 to validate the observer contracts, or P12 to hand off the implementation.",
        "proofGate": "Observer registry exists, observers fire on emission, teardown removes observers, no leaked listeners, validator passes.",
        "color": "Rose",
        "copySheet": "P61_COPY_SAFE",
        "category": "standard",
        "copyContent": "DESIGN AND IMPLEMENT EVENT OBSERVER ARCHITECTURE NOW. DO NOT USE THE TERM EVENT LISTENER.\n\nRepo: resolve the current repository from the environment.\nBranch: preserve existing work; use the current safe branch or create an isolated feature branch.\nSprint: Event Observer Architecture Design.\nLane: event system architecture.\nOwned scope: observer registry, emission contracts, lifecycle management, typed event maps, and validators.\nForbidden scope: unrelated feature rewrites, breaking existing public APIs without migration path, secrets.\nExpected artifacts: tracked observer files, passing validators, commit SHA, push or PR evidence.\n\nWHAT AN EVENT OBSERVER IS\nAn Event Observer is a decoupled component that watches for specific signals (state changes, user actions, system events, cross-component messages) and reacts without the emitter knowing who is listening.\n\nEVENT OBSERVER vs EVENT LISTENER\n- Observer: proactive, semantic, lifecycle-aware, typed, composable\n- Listener: passive, anonymous, often leaked, untyped, monolithic\nWe use Observer terminology to enforce lifecycle discipline.\n\nARCHITECTURE REQUIREMENTS\n1. EVENT MAP (typed contract)\n   - Define every event name, payload shape, and source\n   - Use a central EventMap type or schema\n   - No stringly-typed event names in production code\n\n2. OBSERVER REGISTRY\n   - Central place to register observers\n   - Each observer has: event name, handler, priority, context, teardown\n   - Registry supports: register, unregister, emit, listActive\n   - Registry must be testable in isolation\n\n3. EMITTER CONTRACT\n   - Emitters declare which events they emit\n   - Emitters cannot skip teardown\n   - Emitters cannot emit events not in the EventMap\n   - Emitters must provide evidence of emission in tests\n\n4. LIFECYCLE MANAGEMENT\n   - Every observer registration returns a teardown function\n   - Teardown is mandatory: component unmount, page unload, feature toggle off\n   - No fire-and-forget observers in production code\n   - Teardown must be idempotent (safe to call twice)\n\n5. COMPOSABILITY\n   - Observers can be composed: filter, transform, debounce, throttle\n   - Observers can be scoped: component-level, page-level, app-level\n   - Scoped observers auto-teardown when scope exits\n\n6. AMBITIOUS COERCION\n   - Observer patterns must prove they prevent leaked listeners\n   - Observer patterns must prove they handle edge cases: double-emit, rapid teardown, re-registration\n   - Observer patterns must prove they compose without conflicts\n   - Observer patterns must prove they scale: 10+ observers without performance degradation\n\nPRAGMATIC COERCION\n- Start with the simplest observer that works\n- Add one composability feature at a time\n- Prove each feature with a test before adding the next\n- Never skip teardown tests\n- Never skip emission evidence\n\nINSTALLATION PROCEDURE\n1. Inspect: find existing event patterns, listeners, emitters, teardown code\n2. Design: create the EventMap, Registry, Emitter contract\n3. Implement: build registry, typed emitters, lifecycle management\n4. Validate: prove observers fire, teardown works, no leaks\n5. Migrate: rename Event Listeners to Event Observers where found\n6. Document: add observer patterns to SKILLS.md or harness docs\n7. Commit: track all changes, push or open PR\n\nCOMPLETION STANDARD\n- EventMap covers all application events\n- Registry supports register/unregister/emit/listActive\n- Every observer has a teardown function\n- Teardown is idempotent and tested\n- Emission evidence exists for every event type\n- No fire-and-forget observers in production code\n- Event Listeners renamed to Event Observers in docs and code\n- Commit SHA exists, push or PR evidence reported",
        "keywords": [
            "event observer",
            "event listener",
            "event system",
            "observer pattern",
            "emitter",
            "teardown",
            "lifecycle",
            "decoupled",
            "pubsub",
            "signal",
            "reactive"
        ]
    },
    {
        "id": "P62",
        "seq": "62",
        "name": "Event Observer Migration Executor",
        "type": "CLEANUP",
        "class": "CLEANUP / EVENT MIGRATION",
        "sprintRole": "Migrate existing Event Listener code to Event Observer patterns with zero behavioral regression",
        "progress": "YES",
        "useWhen": "The codebase has existing Event Listener implementations that need to be renamed and refactored to Event Observer patterns. Use when there are addEventListener calls, .on() handlers, or anonymous listener registrations without lifecycle management.",
        "inspectFirst": "All addEventListener, .on(), .off(), removeEventListener calls, listener registrations without teardown, anonymous listener functions, and any existing observer patterns.",
        "expectedOutput": "Migrated Event Observer code with: renamed terms, added teardown functions, lifecycle management, typed event maps, and regression tests proving behavior is preserved.",
        "nextStep": "Run P11 to validate the migration, or P08 to prove live behavior is preserved.",
        "proofGate": "All Event Listener references renamed, teardown functions added, regression tests pass, no behavioral changes.",
        "color": "Amber",
        "copySheet": "P62_COPY_SAFE",
        "category": "standard",
        "copyContent": "MIGRATE EVENT LISTENERS TO EVENT OBSERVERS NOW. PRESERVE ALL EXISTING BEHAVIOR.\n\nRepo: resolve the current repository from the environment.\nBranch: preserve existing work; use the current safe branch or create an isolated feature branch.\nSprint: Event Observer Migration.\nLane: event system cleanup.\nOwned scope: all Event Listener code, event registration patterns, teardown lifecycle, and regression tests.\nForbidden scope: behavioral changes, new features, breaking public APIs, secrets.\nExpected artifacts: migrated observer files, regression tests, commit SHA, push or PR evidence.\n\nMIGRATION RULES\n1. RENAME: Every 'Event Listener' becomes 'Event Observer' in code, docs, and comments\n2. PRESERVE: All existing behavior must continue working\n3. ADD TEAROWN: Every observer registration must have a corresponding teardown\n4. TYPE: Add event name typing where possible\n5. TEST: Regression tests must prove behavior is unchanged\n\nMIGRATION PROCEDURE\n1. AUDIT: Find all addEventListener, .on(), listener registrations\n2. CATALOG: List every event name, handler, and context\n3. MIGRATE ONE AT A TIME: Convert one listener to observer, test, commit\n4. VERIFY: Run full test suite after each migration\n5. DOCUMENT: Update docs to use Observer terminology\n\nCOMPLETION STANDARD\n- Zero addEventListener calls remain (replaced with observer.register)\n- Zero anonymous listeners without teardown\n- Zero leaked listeners (teardown called on unmount/unload)\n- All event names typed in EventMap\n- Regression tests pass for every migrated observer\n- Commit SHA exists, push or PR evidence reported",
        "keywords": [
            "event migration",
            "listener to observer",
            "refactor events",
            "event cleanup",
            "teardown migration",
            "lifecycle migration"
        ]
    },
    {
        "id": "P63",
        "seq": "63",
        "name": "Event Observer Cascade Builder",
        "type": "BUILD + ARTIFACT",
        "class": "BUILD / CASCADE EVENTS",
        "sprintRole": "Design and implement cascading Event Observers where one event triggers a chain of observers with dependency management",
        "progress": "YES",
        "useWhen": "The application needs cascading event chains where one event triggers observers that emit further events. Use when building complex workflows, state machines, or multi-step processes that communicate through events.",
        "inspectFirst": "Existing event chains, cascading patterns, state machines, workflow engines, and any implicit cascade patterns in the codebase.",
        "expectedOutput": "Cascading Event Observer system with: ordered execution, dependency graphs, rollback support, cycle detection, and validators proving cascade chains work end-to-end.",
        "nextStep": "Run P11 to validate cascade contracts, or P08 to prove live cascade behavior.",
        "proofGate": "Cascade chains execute in dependency order, cycles are detected and prevented, rollback works, performance is bounded.",
        "color": "Indigo",
        "copySheet": "P63_COPY_SAFE",
        "category": "standard",
        "copyContent": "BUILD CASCADING EVENT OBSERVER CHAINS NOW. PROVE DEPENDENCY ORDER AND ROLLBACK.\n\nRepo: resolve the current repository from the environment.\nBranch: preserve existing work; use the current safe branch or create an isolated feature branch.\nSprint: Event Observer Cascade Build.\nLane: cascading event architecture.\nOwned scope: cascade registry, dependency graphs, ordered execution, rollback support, cycle detection, and validators.\nForbidden scope: unrelated feature rewrites, breaking existing events, secrets.\nExpected artifacts: tracked cascade files, passing validators, commit SHA, push or PR evidence.\n\nWHAT A CASCADE EVENT IS\nA cascade event is a chain: Event A triggers Observer A, which emits Event B, which triggers Observer B, which emits Event C. The chain must be ordered, bounded, and rollback-safe.\n\nCASCADE ARCHITECTURE REQUIREMENTS\n1. CASCADE REGISTRY\n   - Register cascade chains: event -> observer -> emitted event\n   - Each chain entry has: trigger event, handler, emitted event, priority, rollback handler\n   - Registry detects cycles before execution\n   - Registry supports: addChain, removeChain, executeChain, rollbackChain\n\n2. DEPENDENCY GRAPH\n   - Build a directed graph from cascade chains\n   - Detect cycles at registration time (fail fast)\n   - Topological sort for execution order\n   - Parallel execution where dependencies allow\n\n3. ORDERED EXECUTION\n   - Execute observers in dependency order\n   - Wait for async observers before proceeding\n   - Timeout per observer (prevent infinite loops)\n   - Evidence of execution order in tests\n\n4. ROLLBACK SUPPORT\n   - Every cascade chain has a rollback handler\n   - Rollback executes in reverse order\n   - Rollback is idempotent\n   - Rollback evidence is logged\n\n5. CYCLE DETECTION\n   - Detect direct cycles: A -> B -> A\n   - Detect indirect cycles: A -> B -> C -> A\n   - Fail at registration, not at runtime\n   - Report cycle path for debugging\n\n6. AMBITIOUS COERCION\n   - Cascade chains must prove they handle 10+ events without degradation\n   - Cascade chains must prove rollback works after partial failure\n   - Cascade chains must prove cycle detection catches all cycle types\n   - Cascade chains must prove async observers don't block the chain\n\nPRAGMATIC COERCION\n- Start with a simple two-event chain\n- Add one chain link at a time\n- Prove each link with a test before adding the next\n- Never skip rollback tests\n- Never skip cycle detection tests\n\nINSTALLATION PROCEDURE\n1. Inspect: find existing cascading patterns, state machines, workflows\n2. Design: create CascadeRegistry, DependencyGraph, ExecutionEngine\n3. Implement: build registry, graph, executor, rollback\n4. Validate: prove chains execute in order, rollback works, cycles detected\n5. Document: add cascade patterns to SKILLS.md or harness docs\n6. Commit: track all changes, push or open PR\n\nCOMPLETION STANDARD\n- CascadeRegistry supports addChain/removeChain/executeChain/rollbackChain\n- DependencyGraph detects cycles at registration time\n- ExecutionEngine executes in topological order\n- Rollback executes in reverse order and is idempotent\n- All cascade chains have regression tests\n- Performance: 10-event chain completes in bounded time\n- Commit SHA exists, push or PR evidence reported",
        "keywords": [
            "cascade events",
            "event chain",
            "dependency graph",
            "state machine",
            "workflow events",
            "rollback",
            "cycle detection",
            "ordered execution"
        ]
    }
]

prompts.extend(event_observer_prompts)

with open("prompts.json", "w", encoding="utf-8") as f:
    json.dump(prompts, f, indent=2, ensure_ascii=False)

print(f"Added {len(event_observer_prompts)} Event Observer prompts. Total: {len(prompts)}")
