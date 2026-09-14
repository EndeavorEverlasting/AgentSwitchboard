#!/usr/bin/env python3
"""Dependency-free FirstMate↔ASB↔PromptKit protocol v1 contract tests."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / ".ai/harness/fm-asb-promptkit-protocol.policy.json"
STATE_MACHINE = ROOT / ".ai/harness/fm-asb-promptkit-rollover-state-machine.json"
SCHEMA_DIR = ROOT / ".ai/harness/schemas/fm-asb-promptkit"
FIXTURES = ROOT / ".ai/harness/fixtures/fm-asb-promptkit"
DOCS_PROTOCOL = ROOT / "docs/architecture/fm-asb-promptkit-protocol-v1.md"
DOCS_UX = ROOT / "docs/harness/context-rollover-ux.md"
ADR_BOUNDARY = ROOT / "docs/architecture/asb-firstmate-runtime-boundary.md"

SCHEMA_FILES = [
    "protocol-envelope.v1.schema.json",
    "agent-observation.v1.schema.json",
    "routing-request.v1.schema.json",
    "routing-decision.v1.schema.json",
    "prompt-dispatch.v1.schema.json",
    "context-transition.v1.schema.json",
]

EVENT_RE = re.compile(r"^evt_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
CORR_RE = re.compile(r"^corr_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
IDEM_RE = re.compile(r"^idem_[a-f0-9]{64}$")
SHA_RE = re.compile(r"^[a-f0-9]{64}$")
GE_RE = re.compile(r"^ge_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
CTX_RE = re.compile(r"^ctx_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def semantic_sha(obj: dict) -> str:
    payload = {k: v for k, v in obj.items() if k not in ("eventId", "createdAt", "idempotency")}
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def idem_key(*parts: str) -> str:
    digest = hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()
    return f"idem_{digest}"


def envelope_ok(msg: dict) -> list[str]:
    errors = []
    for field in ("schema", "eventId", "correlationId", "causationId", "createdAt", "producer", "idempotency"):
        if field not in msg:
            errors.append(f"missing envelope field {field}")
    if errors:
        return errors
    if not EVENT_RE.match(msg["eventId"]):
        errors.append("eventId pattern")
    if not CORR_RE.match(msg["correlationId"]):
        errors.append("correlationId pattern")
    if msg["causationId"] is not None and not EVENT_RE.match(msg["causationId"]):
        errors.append("causationId pattern")
    producer = msg["producer"]
    if producer.get("system") not in ("agentswitchboard", "firstmate", "prompt-kit"):
        errors.append("producer.system")
    idem = msg["idempotency"]
    if not IDEM_RE.match(idem.get("key", "")):
        errors.append("idempotency.key pattern")
    if not SHA_RE.match(idem.get("semanticSha256", "")):
        errors.append("idempotency.semanticSha256 pattern")
    if idem.get("semanticSha256") != semantic_sha(msg):
        errors.append("idempotency.semanticSha256 mismatch")
    return errors


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def routing_decision_semantics(msg: dict) -> list[str]:
    errors = []
    decision = msg["decision"]
    action = decision["routeAction"]
    primary = decision["primaryPrompt"]
    if action in ("KEEP_CURRENT_PROMPT", "SWITCH_PROMPT") and primary is None:
        errors.append("primaryPrompt required for route action")
    if action in ("NO_ROUTE", "BLOCKED") and primary is not None:
        errors.append("primaryPrompt must be null for NO_ROUTE/BLOCKED")
    return errors


def context_transition_semantics(msg: dict) -> list[str]:
    errors = []
    pressure = msg.get("pressure")
    transition = msg["transition"]
    if isinstance(pressure, dict):
        source = pressure.get("observationSource")
        if source in ("estimated", "unavailable"):
            if pressure.get("automaticEligible") is not False:
                errors.append("estimated/unavailable must set automaticEligible=false")
            if transition.get("automatic") is True:
                errors.append("estimated/unavailable forbids automatic transition")
    if msg["state"] == "COMPLETED":
        if msg["checkpoint"]["state"] != "complete":
            errors.append("COMPLETED requires checkpoint.complete")
        if msg["post"] is None:
            errors.append("COMPLETED requires post")
        if msg["verification"] is None:
            errors.append("COMPLETED requires verification")
        if msg["error"] is not None:
            errors.append("COMPLETED requires error=null")
        semantic = msg.get("semantic")
        if isinstance(semantic, dict) and semantic.get("intervention") in ("REGROUND", "REBOOTSTRAP"):
            if msg["post"]["groundingEpisodeId"] == semantic["groundingEpisodeId"]:
                errors.append("REGROUND/REBOOTSTRAP completed must advance groundingEpisodeId")
    return errors


def main() -> None:
    policy = load(POLICY)
    sm = load(STATE_MACHINE)
    assert_true(policy["policyId"] == "agentswitchboard.fm-asb-promptkit-protocol.v1", "policy id")
    assert_true(policy["status"] == "contract-only", "policy must remain contract-only")
    assert_true(sm["stateMachineId"] == "agentswitchboard.context-rollover.v1", "state machine id")
    assert_true(sm["status"] == "contract-only", "state machine must remain contract-only")
    assert_true(DOCS_PROTOCOL.is_file(), "protocol doc missing")
    assert_true(DOCS_UX.is_file(), "ux doc missing")

    for name in SCHEMA_FILES:
        path = SCHEMA_DIR / name
        assert_true(path.is_file(), f"missing schema {name}")
        schema = load(path)
        assert_true("$schema" in schema and schema["$schema"].endswith("2020-12/schema"), f"{name} draft")
        assert_true("$id" in schema, f"{name} $id")

    # Ownership invariants present in policy
    assert_true("crew-scheduler" in policy["mustNotOwn"]["agentswitchboard"], "ASB must not own crew scheduler")
    assert_true("direct-terminal-manipulation" in policy["mustNotOwn"]["agentswitchboard"], "no terminal poke")
    assert_true(policy["semanticRules"]["deliveryPlane"] == "durable-inbox", "durable inbox")
    assert_true(policy["idempotency"]["promptDispatchRetryMustReuseDeliveryId"] is True, "deliveryId reuse")

    # Valid fixtures
    obs = load(FIXTURES / "agent-observation.valid.json")
    req = load(FIXTURES / "routing-request.valid.json")
    dec = load(FIXTURES / "routing-decision.valid.json")
    dispatch = load(FIXTURES / "prompt-dispatch.valid.json")
    ctx = load(FIXTURES / "context-transition.completed.valid.json")

    for label, msg in (
        ("observation", obs),
        ("routing-request", req),
        ("routing-decision", dec),
        ("prompt-dispatch", dispatch),
        ("context-transition", ctx),
    ):
        errs = envelope_ok(msg)
        assert_true(not errs, f"{label} envelope: {errs}")

    assert_true(obs["schema"] == "asb.agent-observation/v1", "obs schema")
    assert_true(obs["output"]["rawIncluded"] is False, "rawIncluded forbidden")
    assert_true(req["constraints"]["rawTranscriptIncluded"] is False, "raw transcript forbidden")
    assert_true(req["routingPolicy"]["crossSurfaceFallbackAllowed"] is False, "no cross-surface")
    assert_true(not routing_decision_semantics(dec), "valid decision semantics")
    assert_true(dispatch["target"]["deliveryPlane"] == "durable-inbox", "dispatch plane")
    assert_true(dispatch["prompt"]["deliveryMode"] == "reference", "preferred reference mode")
    assert_true(dispatch["prompt"]["inlineText"] is None, "reference inlineText null")
    assert_true(not context_transition_semantics(ctx), "valid context semantics")
    assert_true(ctx["post"]["groundingEpisodeId"] != ctx["semantic"]["groundingEpisodeId"], "ge advance")

    # Correlation continuity across the sample chain
    corr = obs["correlationId"]
    assert_true(req["correlationId"] == corr, "request correlation")
    assert_true(dec["correlationId"] == corr, "decision correlation")
    assert_true(dispatch["correlationId"] == corr, "dispatch correlation")
    assert_true(ctx["correlationId"] == corr, "transition correlation")
    assert_true(req["causationId"] == obs["eventId"], "req causation")
    assert_true(dec["causationId"] == req["eventId"], "dec causation")
    assert_true(dispatch["causationId"] == dec["eventId"], "dispatch causation")

    # Idempotency identities
    assert_true(
        obs["idempotency"]["key"]
        == idem_key("asb.agent-observation/v1", obs["source"]["taskId"], obs["source"]["eventKey"]),
        "obs idempotency key",
    )
    assert_true(
        req["idempotency"]["key"]
        == idem_key(
            "prompt-kit.routing-request/v1",
            req["observationEventId"],
            req["mission"]["groundingEpisodeId"],
            req["executionSurface"],
        ),
        "req idempotency key",
    )
    assert_true(
        dec["idempotency"]["key"]
        == idem_key(
            "prompt-kit.routing-decision/v1",
            dec["routingRequestEventId"],
            dec["registry"]["registrySha256"],
        ),
        "dec idempotency key",
    )
    assert_true(
        dispatch["idempotency"]["key"]
        == idem_key(
            "asb.prompt-dispatch/v1",
            dispatch["routingDecisionEventId"],
            dispatch["target"]["firstMateTaskId"],
            dispatch["prompt"]["ref"]["promptSha256"],
        ),
        "dispatch idempotency key",
    )
    assert_true(
        ctx["idempotency"]["key"]
        == idem_key("asb.context-transition/v1", ctx["transitionId"], ctx["state"]),
        "ctx idempotency key",
    )

    # Invalid fixtures must fail semantic rules
    bad_ctx = load(FIXTURES / "context-transition.estimated-automatic.invalid.json")
    bad_ctx_errs = context_transition_semantics(bad_ctx)
    assert_true(any("forbids automatic" in e for e in bad_ctx_errs), f"expected auto forbid, got {bad_ctx_errs}")

    bad_dec = load(FIXTURES / "routing-decision.switch-null-primary.invalid.json")
    bad_dec_errs = routing_decision_semantics(bad_dec)
    assert_true(any("primaryPrompt required" in e for e in bad_dec_errs), f"expected primary rule, got {bad_dec_errs}")

    # State machine shape
    visible = [s["id"] for s in sm["userVisibleStates"]]
    for required in (
        "Healthy",
        "Context getting full",
        "Checkpointing",
        "Ready to continue fresh",
        "Relaunching",
        "Verified & continuing",
        "Needs attention",
    ):
        assert_true(required in visible, f"missing user state {required}")
    event_ids = {e["id"] for e in sm["events"]}
    for required in (
        "pressure.rising.verified",
        "pressure.rising.estimated",
        "checkpoint.failed",
        "rollover.authorized",
        "relaunch.launch-failed-after-stop",
        "post.verify.passed",
    ):
        assert_true(required in event_ids, f"missing event {required}")
    transitions = {(t["from"], t["event"], t["to"]) for t in sm["transitions"]}
    assert_true(("HEALTHY", "pressure.rising.estimated", "CHECKPOINT_PREP") in transitions, "estimated path")
    assert_true(("CHECKPOINTING", "checkpoint.failed", "NEEDS_ATTENTION") in transitions, "checkpoint fail path")
    assert_true(("NEW_CONTEXT", "post.verify.passed", "VERIFIED") in transitions, "verify path")
    assert_true(sm["backendGates"]["tmux"] == "automatic-crew-rollover", "tmux gate")
    assert_true(sm["backendGates"]["Zellij"] == "checkpoint-only", "zellij gate")
    assert_true(sm["scopeGates"]["primary-session"] == "checkpoint-and-fresh-session-packet-only", "primary scope")
    assert_true(sm["firstSuccessorTurn"]["mutationAllowed"] is False, "no immediate mutation")

    # Receipt fixtures
    receipt_dir = FIXTURES / "receipts"
    for name in (
        "pressure-observation.receipt.json",
        "checkpoint.receipt.json",
        "firstmate-relaunch.receipt.json",
        "post-verification.receipt.json",
        "context-transition.aggregate.receipt.json",
        "needs-attention.checkpoint-failed.receipt.json",
        "needs-attention.launch-failed-after-stop.receipt.json",
    ):
        path = receipt_dir / name
        assert_true(path.is_file(), f"missing receipt {name}")
        receipt = load(path)
        assert_true(
            "receiptType" in receipt
            and ("userSummary" in receipt or "userDefaultView" in receipt),
            name,
        )

    checkpoint_fail = load(receipt_dir / "needs-attention.checkpoint-failed.receipt.json")
    assert_true(checkpoint_fail["oldAgentPreserved"] is True, "checkpoint fail preserves agent")
    assert_true(checkpoint_fail["relaunchAttempted"] is False, "checkpoint fail must not relaunch")
    launch_fail = load(receipt_dir / "needs-attention.launch-failed-after-stop.receipt.json")
    assert_true("worktree" in launch_fail["preserved"], "launch fail preserves worktree")

    # Docs mention validator and invariant
    protocol_text = DOCS_PROTOCOL.read_text(encoding="utf-8")
    ux_text = DOCS_UX.read_text(encoding="utf-8")
    assert_true("Test-FmAsbPromptKitProtocolContract.ps1" in protocol_text or "fm-asb-promptkit" in protocol_text, "protocol docs")
    assert_true("durable" in ux_text.lower() and "relaunch" in ux_text.lower(), "ux relaunch language")
    assert_true("Nothing was relaunched" in ux_text, "checkpoint failure copy")
    assert_true("Agent stopped; work is preserved" in ux_text, "launch failure copy")

    boundary = ADR_BOUNDARY.read_text(encoding="utf-8")
    assert_true("fm-asb-promptkit-protocol-v1" in boundary, "boundary ADR cross-link missing")

    print("FM-ASB-PROMPTKIT PROTOCOL CONTRACT: PASS")


if __name__ == "__main__":
    main()
