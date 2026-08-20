#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ROUTER_PATH = ROOT / "tooling/harness/context/context.routes.json"
WORKFLOW_INDEX_PATH = ROOT / "tooling/harness/operational/opencode-lsp-setup/workflows.json"
CANONICAL_GOVERNANCE_PATH = "docs/governance/agent-operating-details.md"
CANONICAL_GOVERNANCE_BLOB = "c94b797bef04942636af61b980c478919710e067"
CANONICAL_GOVERNANCE_BYTES = 27896
REQUIRED_WORKFLOW_KEYS = ("trigger", "inputs", "outputs", "dependencies", "validator", "failurePolicy", "proofCeiling", "handoff")
REQUIRED_WORKFLOW_SHARED_LOAD = {
    ".ai/skills/opencode-lsp-workstation-setup/SKILL.md",
    "tooling/harness/operational/opencode-lsp-setup/artifact-registry.json",
}


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def rel(path: str) -> Path:
    return ROOT / path


def git_output(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(ROOT), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def tracked_blob(path: str) -> tuple[str, int]:
    sha = git_output("rev-parse", f"HEAD:{path}")
    size = int(git_output("cat-file", "-s", sha))
    return sha, size


def measure(paths: list[str], chars_per_token: int) -> dict:
    total = 0
    missing: list[str] = []
    for path in paths:
        target = rel(path)
        if target.is_file():
            total += target.stat().st_size
        else:
            missing.append(path)
    return {
        "files": paths,
        "missing": missing,
        "bytes": total,
        "estimatedTokens": math.ceil(total / chars_per_token),
    }


def reduction_percent(after_bytes: int, baseline_bytes: int) -> float:
    if baseline_bytes <= 0:
        return 0.0
    return round((1 - after_bytes / baseline_bytes) * 100, 1)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate AgentSwitchboard progressive-disclosure routing and context budgets.")
    parser.add_argument("--domain", default="opencode-lsp")
    parser.add_argument("--workflow", default="opencode-lsp.configure")
    parser.add_argument("--output")
    args = parser.parse_args()

    failures: list[str] = []
    router = read_json(ROUTER_PATH)
    cpt = int(router["estimate"]["charsPerEstimatedToken"])

    def require(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    require(router.get("routerId") == "agentswitchboard.progressive-disclosure.v1", "router-id")
    require(cpt == 4, "token-estimate-policy")

    deep = router.get("preservedGovernance", {})
    require(deep.get("path") == CANONICAL_GOVERNANCE_PATH, "preserved-governance-route-path")
    require(deep.get("expectedGitBlobSha") == CANONICAL_GOVERNANCE_BLOB, "preserved-governance-route-blob")
    require(deep.get("expectedBytes") == CANONICAL_GOVERNANCE_BYTES, "preserved-governance-route-size")

    all_paths: set[str] = set(router["orientation"]["defaultLoad"])
    all_paths.add(router["orientation"]["nextRouter"])
    all_paths.add(router["glossary"]["path"])
    all_paths.add(CANONICAL_GOVERNANCE_PATH)
    for item in router["domains"] + router["workflows"]:
        all_paths.update(item.get("defaultLoad", []))
        all_paths.update(item.get("onDemand", []))
    for path in sorted(all_paths):
        require(rel(path).is_file(), f"broken-route:{path}")

    actual_deep_sha = None
    actual_deep_size = None
    if rel(CANONICAL_GOVERNANCE_PATH).is_file():
        try:
            actual_deep_sha, actual_deep_size = tracked_blob(CANONICAL_GOVERNANCE_PATH)
            require(actual_deep_size == CANONICAL_GOVERNANCE_BYTES, "preserved-governance-size")
            require(actual_deep_sha == CANONICAL_GOVERNANCE_BLOB, "preserved-governance-blob")
        except RuntimeError as exc:
            failures.append(f"preserved-governance-git-object:{exc}")

    agents = rel("AGENTS.md").read_text(encoding="utf-8")
    for token in (
        "Progressive disclosure reading order", "HARNESS.md", "context.routes.json",
        "agent-operating-details.md", "SKILLS.md", "CAPABILITIES.md", "TRIGGERS.md",
        ".ai/agent-contract.json", "plans/plan-registry.json", "public-plan-coordination",
    ):
        require(token in agents, f"agents-routing-token:{token}")

    orientation = measure(router["orientation"]["defaultLoad"], cpt)
    orientation["query"] = router["orientation"]["query"]
    orientation["maxEstimatedTokens"] = router["budgets"]["orientation50k"]["maxEstimatedTokens"]
    orientation["pass"] = not orientation["missing"] and orientation["estimatedTokens"] <= orientation["maxEstimatedTokens"]
    require(orientation["pass"], "orientation-budget-or-route")
    forbidden = tuple(router["orientation"]["neverDefaultLoad"])
    for path in router["orientation"]["defaultLoad"]:
        require(not any(path == item or path.startswith(item.rstrip("/") + "/") for item in forbidden), f"orientation-preloads-deep:{path}")

    domains = {item["domainId"]: item for item in router["domains"]}
    require(args.domain in domains, f"unknown-domain:{args.domain}")
    selected_domain = domains.get(args.domain)
    domain_measure = {
        "files": [], "missing": [], "bytes": 0, "estimatedTokens": 0, "query": None,
        "maxEstimatedTokens": router["budgets"]["domain30kAdditional"]["maxEstimatedTokens"], "pass": False,
    }
    if selected_domain:
        domain_measure = measure(selected_domain["defaultLoad"], cpt)
        domain_measure["query"] = "How does one selected domain work?"
        domain_measure["maxEstimatedTokens"] = router["budgets"]["domain30kAdditional"]["maxEstimatedTokens"]
        domain_measure["pass"] = not domain_measure["missing"] and domain_measure["estimatedTokens"] <= domain_measure["maxEstimatedTokens"]
        require(domain_measure["pass"], "domain-budget-or-route")
        unrelated_defaults = {
            path for domain in router["domains"] if domain["domainId"] != args.domain
            for path in domain.get("defaultLoad", [])
        }
        require(not (set(selected_domain["defaultLoad"]) & unrelated_defaults), "domain-loads-unrelated-domain")

    workflow_index = read_json(WORKFLOW_INDEX_PATH) if WORKFLOW_INDEX_PATH.is_file() else {}
    require(workflow_index.get("schemaVersion") == 2, "workflow-index-version")
    canonical_workflows = {
        f"opencode-lsp.{record['id']}": record
        for record in workflow_index.get("workflows", [])
        if record.get("id") and record.get("specPath")
    }
    routed_workflows = {item["workflowId"]: item for item in router["workflows"]}
    require(set(canonical_workflows) == set(routed_workflows), "workflow-router-index-parity")
    for workflow_id, record in canonical_workflows.items():
        require(rel(record["specPath"]).is_file(), f"workflow-index-broken:{workflow_id}")

    require(args.workflow in routed_workflows, f"unknown-workflow:{args.workflow}")
    selected_workflow = routed_workflows.get(args.workflow)
    workflow_measure = {
        "files": [], "missing": [], "bytes": 0, "estimatedTokens": 0, "query": None,
        "maxEstimatedTokens": router["budgets"]["workflow15kAdditional"]["maxEstimatedTokens"], "pass": False,
    }
    selected_spec_path = None
    selected_baseline_id = None
    if selected_workflow:
        require(selected_workflow["domainId"] == args.domain, "workflow-domain-mismatch")
        workflow_measure = measure(selected_workflow["defaultLoad"], cpt)
        workflow_measure["query"] = selected_workflow.get("query") or "How do I execute or change one selected workflow/spec?"
        workflow_measure["maxEstimatedTokens"] = router["budgets"]["workflow15kAdditional"]["maxEstimatedTokens"]
        workflow_measure["pass"] = not workflow_measure["missing"] and workflow_measure["estimatedTokens"] <= workflow_measure["maxEstimatedTokens"]
        require(workflow_measure["pass"], "workflow-budget-or-route")

        canonical_record = canonical_workflows.get(args.workflow)
        require(canonical_record is not None, "workflow-not-in-canonical-index")
        if canonical_record:
            selected_spec_path = canonical_record["specPath"]
            required_load = set(REQUIRED_WORKFLOW_SHARED_LOAD) | {selected_spec_path}
            require(required_load.issubset(set(selected_workflow["defaultLoad"])), "workflow-missing-spec-skill-artifact-contract")
            workflow_spec_candidates = [path for path in selected_workflow["defaultLoad"] if path.endswith(".workflow.json")]
            require(workflow_spec_candidates == [selected_spec_path], "workflow-route-spec-mismatch")
            if rel(selected_spec_path).is_file():
                selected_spec = read_json(rel(selected_spec_path))
                expected_id = canonical_record["id"]
                require(selected_spec.get("workflowId") == expected_id, "workflow-spec-id-mismatch")
                for key in REQUIRED_WORKFLOW_KEYS:
                    require(bool(selected_spec.get(key)), f"workflow-contract-missing:{expected_id}:{key}")

        selected_baseline_id = selected_workflow.get("baselineId")
        require(bool(selected_baseline_id), "workflow-baseline-id-missing")

    glossary_path = rel(router["glossary"]["path"])
    if glossary_path.is_file():
        glossary = read_json(glossary_path)
        terms = {item["term"] for item in glossary.get("terms", [])}
        for term in ("50k", "30k", "15k", "canonical owner", "defaultLoad", "onDemand", "proof ceiling", "validator"):
            require(term in terms, f"glossary-missing:{term}")

    baseline = router["baseline"]["simulations"]
    orientation_baseline = baseline.get("orientation50k", {})
    domain_baseline = baseline.get("domain30kOpencodeLsp", {})
    workflow_baseline = baseline.get(selected_baseline_id or "", {})
    require(bool(orientation_baseline.get("bytes")), "orientation-baseline-missing")
    require(bool(domain_baseline.get("bytes")), "domain-baseline-missing")
    require(bool(workflow_baseline.get("bytes")), "workflow-baseline-missing")

    reductions = {
        "orientation50kPercent": reduction_percent(orientation["bytes"], int(orientation_baseline.get("bytes", 0))),
        "domain30kOpencodeLspPercent": reduction_percent(domain_measure["bytes"], int(domain_baseline.get("bytes", 0))),
        "workflow15kSelectedPercent": reduction_percent(workflow_measure["bytes"], int(workflow_baseline.get("bytes", 0))),
    }
    require(reductions["orientation50kPercent"] >= 80, "orientation-reduction-not-meaningful")
    require(reductions["domain30kOpencodeLspPercent"] >= 40, "domain-reduction-not-meaningful")
    require(reductions["workflow15kSelectedPercent"] >= 40, "workflow-reduction-not-meaningful")

    report = {
        "schema": "agentswitchboard.progressive-disclosure-validation.v1",
        "status": "FAIL" if failures else "PASS",
        "router": str(ROUTER_PATH.relative_to(ROOT)).replace("\\", "/"),
        "tokenEstimate": router["estimate"],
        "selection": {
            "domainId": args.domain,
            "workflowId": args.workflow,
            "workflowSpec": selected_spec_path,
            "workflowBaselineId": selected_baseline_id,
        },
        "baseline": baseline,
        "after": {
            "orientation50k": orientation,
            "domain30k": domain_measure,
            "workflow15k": workflow_measure,
        },
        "reductions": reductions,
        "preservedGovernance": {
            "path": CANONICAL_GOVERNANCE_PATH,
            "expectedGitBlobSha": CANONICAL_GOVERNANCE_BLOB,
            "actualGitBlobSha": actual_deep_sha,
            "expectedBytes": CANONICAL_GOVERNANCE_BYTES,
            "actualBytes": actual_deep_size,
        },
        "failures": failures,
    }

    if args.output:
        output = Path(args.output).expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"REPORT={output}")
    print(
        f"PROGRESSIVE_DISCLOSURE={report['status']} "
        f"50k={orientation['estimatedTokens']} 30k={domain_measure['estimatedTokens']} "
        f"15k={workflow_measure['estimatedTokens']} estimated_tokens workflow={args.workflow}"
    )
    if failures:
        for failure in failures:
            print(f"FAIL={failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
