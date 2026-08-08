# ASB Wayfinder Harness

Wayfinder is ASB's ambiguity-resolution workflow for work that is too large or uncertain for one bounded session. It is adapted from Matt Pocock's Wayfinder ecosystem at the pinned donor commit recorded in `tooling/harness/operational/contributions/wayfinder-public-plan.contribution.json`.

The purpose is not to give a model more discretion. The purpose is to **move decisions out of transient model context and into typed, reviewable tracker artifacts with deterministic workflow gates**.

## When to use it

Use Wayfinder when both are true:

1. the destination requires more than one bounded agent session; and
2. you cannot yet state the safe executable route because important decisions/investigations are still hidden by fog.

If the path is already clear, skip Wayfinder and use a normal bounded sprint/public-plan workflow.

## Authority map

| Surface | Owns | Does not own |
|---|---|---|
| `.ai/skills/wayfinder/SKILL.md` | Wayfinder procedure and ticket routing | tracker state, human decisions, implementation |
| tracker map | low-resolution destination/notes/decision pointers/fog/scope index | full decision details |
| tracker child decision ticket | exact question, blockers, claim, resolution, asset pointers | destination implementation slices |
| `plans/` public plan | repository ownership/collision/delivery/proof/handoff mirror | Wayfinder question/answer store |
| temporary specification | synthesis of already-settled decisions | primary decision rationale |
| `to-tickets` / `bounded-sprint` | implementation decomposition/execution after clarity | ambiguity-resolution decisions |
| `third_party/mattpocock-skills/<commit>/` | immutable donor-source evidence | ASB runtime behavior |

A decision must have **one primary owner**. The map/public plan may gist and link a ticket; they must not duplicate its full answer.

## Ticket types are gates

### Research — AFK

Use `research`. The ticket cannot resolve without a concrete findings artifact and at least one primary source. Independent research tickets may run in parallel when the execution surface supports safe isolation.

### Prototype — HITL

Use `prototype`. The ticket cannot resolve merely because code ran. It needs a runnable throwaway artifact and an observed human reaction/verdict. Prototype source stays out of production authority; later implementation ports the validated decision through normal tests/review.

### Grilling — HITL

Use `grilling` and `domain-modeling`. The agent may research facts and recommend answers; the human owns choices. The ticket cannot resolve without actual human response evidence. Domain terms/ADRs are updated when they truly settle.

### Task — AFK or HITL

A task is a prerequisite action that unblocks a later decision: provisioning access, moving data so its shape can be inspected, signing up for a service so its API can be evaluated, and similar work. A checklist does not prove completion. Leave the ticket open until the prerequisite is actually done.

## Chart mode

1. Settle the destination through grilling/domain-modeling.
2. Explore breadth-first. If no real fog exists and the whole route fits one bounded session, exit Wayfinder.
3. Create the map.
4. Create only the decision tickets whose questions can already be stated precisely.
5. Create ticket identities first, then wire parent/blocking relationships in a second pass.
6. Keep coarse future uncertainty in `Not yet specified`.
7. Dispatch independent research tickets when a real subagent/execution surface exists.
8. Update the public-plan coordination mirror.
9. **Stop.** Charting does not hand-resolve prototype, grilling, or task tickets and does not implement the destination.

## Work mode

1. Load the map, not every ticket.
2. Query the live frontier: open child tickets with no open blockers and no assignee.
3. Choose a named eligible ticket or the first frontier ticket.
4. **Claim it before work.** On GitHub the assignee is the claim.
5. Run the exact type gate.
6. Resolve at most one non-research ticket in the session.
7. Post the resolution on the ticket, close it, and add only a linked one-line gist to the map.
8. Recompute fog/blockers/scope; create newly precise tickets and wire them after creation.
9. Update the public-plan mirror and stop.

## GitHub adapter

`tooling/harness/wayfinder/github_tracker.py` constructs the GitHub operations. It prefers current native GitHub surfaces:

- map issue label `wayfinder:map`;
- child issue creation with a parent relationship;
- `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task` labels;
- native `blocked_by` issue dependencies;
- assignee-based claim;
- resolution comment + close;
- `wayfinder:spec` for the temporary specification.

The repository currently needs these labels created before first live use. The adapter's `ensure_labels()` method owns that setup when an authenticated `gh` runtime is explicitly authorized. Static/hosted tests only prove command construction, not repository permissions or feature availability.

## Specification lifecycle

When all required decision tickets are resolved and `Not yet specified` is empty, `to-spec` may publish an implementation-ready specification. It must link the source map and decision tickets and declare lifecycle `temporary-until-implementation`.

After implementation is accepted, retire/archive or remove the spec according to tracker policy. **Do not delete the closed decision tickets.** The durable value is the decision history; the spec is a temporary compression layer for execution.

`to-tickets` runs after clarity and produces tracer-bullet implementation tickets. Those tickets are not Wayfinder decision tickets and should not carry `wayfinder:<type>` semantics.

## Source integrity

Imported donor files live under:

`third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/`

They include Wayfinder, research, prototype, grilling, domain-modeling, to-spec, to-tickets, GitHub/local tracker doctrine, and the MIT license. `tests/test_wayfinder_harness.py` recomputes Git blob hashes and fails if an imported source changes.

Do not edit snapshots in place. A donor refresh creates a new pinned snapshot directory and contribution review.

## Validation

From a checkout with Python and PowerShell:

```powershell
python -m pip install --disable-pip-version-check -r tooling/harness/operational/contributions/requirements-wayfinder-public-plan.txt
python tests/test_wayfinder_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-WayfinderHarness.ps1
python tests/test_wayfinder_public_plan_contribution.py
pwsh -NoLogo -NoProfile -File scripts/Test-WayfinderPublicPlanContribution.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-PublicPlanContracts.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git diff --check
```

The hosted workflow repeats the Wayfinder/public-plan gates on Windows and Linux.

## Proof ceiling

Green static/hosted validation proves imported-source integrity, ASB ownership/routing, schemas, deterministic ticket gates, HITL evidence requirements, frontier/spec-readiness algorithms, GitHub command construction, and public-plan separation.

It does **not** prove:

- GitHub sub-issues/dependencies/labels are available with the current operator's permissions;
- an actual ticket was claimed/resolved correctly in a live repository;
- a human approved a prototype or answered a grilling decision;
- research conclusions are correct beyond their cited evidence;
- the prototype is useful;
- the resulting specification or implementation is good;
- destination code was built, merged, deployed, or accepted.

Those claims require their owning live/runtime artifacts.
