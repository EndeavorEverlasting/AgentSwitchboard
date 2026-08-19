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


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def rel(path: str) -> Path:
    return ROOT / path


def git_output(*args: str) -> str:
    result = subprocess.run(["git", "-C", str(ROOT), *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def tracked_blob(path: str) -> tuple[str, int]:
    sha = git_output("rev-parse", f"HEAD:{path}")
    size = int(git_output("cat-file", "-s", sha))
    return sha, size


def measure(paths: list[str], chars_per_token: int) -> dict:
    total = sum(rel(p).stat().st_size for p in paths)
    return {
        "files": paths,
        "bytes": total,
        "estimatedTokens": math.ceil(total / chars_per_token),
    }


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

    all_paths: set[str] = set(router["orientation"]["defaultLoad"])
    all_paths.add(router["orientation"]["nextRouter"])
    all_paths.add(router["glossary"]["path"])
    all_paths.add(router["preservedGovernance"]["path"])
    for item in router["domains"] + router["workflows"]:
        all_paths.update(item.get("defaultLoad", []))
        all_paths.update(item.get("onDemand", []))
    for path in sorted(all_paths):
        require(rel(path).is_file(), f"broken-route:{path}")

    deep = router["preservedGovernance"]
    deep_path = rel(deep["path"])
    actual_deep_sha = None
    actual_deep_size = None
    if deep_path.is_file():
        try:
            actual_deep_sha, actual_deep_size = tracked_blob(deep["path"])
            require(actual_deep_size == deep["expectedBytes"], "preserved-governance-size")
            require(actual_deep_sha == deep["expectedGitBlobSha"], "preserved-governance-blob")
        except RuntimeError as exc:
            failures.append(f"preserved-governance-git-object:{exc}")

    agents = rel("AGENTS.md").read_text(encoding="utf-8")
    for token in ("Progressive disclosure reading order", "HARNESS.md", "context.routes.json", "agent-operating-details.md", "SKILLS.md", "CAPABILITIES.md", "TRIGGERS.md", ".ai/agent-contract.json", "plans/plan-registry.json", "public-plan-coordination"):
        require(token in agents, f"agents-routing-token:{token}")

    orientation = measure(router["orientation"]["defaultLoad"], cpt)
    orientation["query"] = router["orientation"]["query"]
    orientation["maxEstimatedTokens"] = router["budgets"]["orientation50k"]["maxEstimatedTokens"]
    orientation["pass"] = orientation["estimatedTokens"] <= orientation["maxEstimatedTokens"]
    require(orientation["pass"], "orientation-budget")
    forbidden = tuple(router["orientation"]["neverDefaultLoad"])
    for path in router["orientation"]["defaultLoad"]:
        require(not any(path == f or path.startswith(f.rstrip("/") + "/") for f in forbidden), f"orientation-preloads-deep:{path}")

    domains = {x["domainId"]: x for x in router["domains"]}
    require(args.domain in domains, f"unknown-domain:{args.domain}")
    selected_domain = domains.get(args.domain)
    domain_measure = {"files": [], "bytes": 0, "estimatedTokens": 0, "query": None, "maxEstimatedTokens": router["budgets"]["domain30kAdditional"]["maxEstimatedTokens"], "pass": False}
    if selected_domain:
        domain_measure = measure(selected_domain["defaultLoad"], cpt)
        domain_measure["query"] = "How does one selected domain work?"
        domain_measure["maxEstimatedTokens"] = router["budgets"]["domain30kAdditional"]["maxEstimatedTokens"]
        domain_measure["pass"] = domain_measure["estimatedTokens"] <= domain_measure["maxEstimatedTokens"]
        require(domain_measure["pass"], "domain-budget")
        unrelated_defaults = {p for d in router["domains"] if d["domainId"] != args.domain for p in d.get("defaultLoad", [])}
        require(not (set(selected_domain["defaultLoad"]) & unrelated_defaults), "domain-loads-unrelated-domain")

    workflows = {x["workflowId"]: x for x in router["workflows"]}
    require(args.workflow in workflows, f"unknown-workflow:{args.workflow}")
    selected_workflow = workflows.get(args.workflow)
    workflow_measure = {"files": [], "bytes": 0, "estimatedTokens": 0, "query": None, "maxEstimatedTokens": router["budgets"]["workflow15kAdditional"]["maxEstimatedTokens"], "pass": False}
    if selected_workflow:
        require(selected_workflow["domainId"] == args.domain, "workflow-domain-mismatch")
        workflow_measure = measure(selected_workflow["defaultLoad"], cpt)
        workflow_measure["query"] = "How do I execute or change one selected workflow/spec?"
        workflow_measure["maxEstimatedTokens"] = router["budgets"]["workflow15kAdditional"]["maxEstimatedTokens"]
        workflow_measure["pass"] = workflow_measure["estimatedTokens"] <= workflow_measure["maxEstimatedTokens"]
        require(workflow_measure["pass"], "workflow-budget")
        required_roles = {
            "tooling/harness/operational/opencode-lsp-setup/workflows/configure.workflow.json",
            ".ai/skills/opencode-lsp-workstation-setup/SKILL.md",
            "tooling/harness/operational/opencode-lsp-setup/artifact-registry.json",
        }
        require(required_roles.issubset(set(selected_workflow["defaultLoad"])), "workflow-missing-spec-skill-artifact-contract")

    configure_spec = read_json(rel("tooling/harness/operational/opencode-lsp-setup/workflows/configure.workflow.json"))
    for key in ("trigger", "inputs", "outputs", "dependencies", "validator", "failurePolicy", "proofCeiling", "handoff"):
        require(bool(configure_spec.get(key)), f"workflow-contract-missing:{key}")

    workflow_index = read_json(rel("tooling/harness/operational/opencode-lsp-setup/workflows.json"))
    require(workflow_index.get("schemaVersion") == 2, "workflow-index-version")
    for record in workflow_index.get("workflows", []):
        spec = record.get("specPath")
        require(bool(spec) and rel(spec).is_file(), f"workflow-index-broken:{record.get('id')}")

    glossary = read_json(rel(router["glossary"]["path"]))
    terms = {x["term"] for x in glossary.get("terms", [])}
    for term in ("50k", "30k", "15k", "canonical owner", "defaultLoad", "onDemand", "proof ceiling", "validator"):
        require(term in terms, f"glossary-missing:{term}")

    baseline = router["baseline"]["simulations"]
    reductions = {
        "orientation50kPercent": round((1 - orientation["bytes"] / baseline["orientation50k"]["bytes"]) * 100, 1),
        "domain30kOpencodeLspPercent": round((1 - domain_measure["bytes"] / baseline["domain30kOpencodeLsp"]["bytes"]) * 100, 1),
        "workflow15kOpencodeLspConfigurePercent": round((1 - workflow_measure["bytes"] / baseline["workflow15kOpencodeLspConfigure"]["bytes"]) * 100, 1),
    }
    require(reductions["orientation50kPercent"] >= 80, "orientation-reduction-not-meaningful")
    require(reductions["domain30kOpencodeLspPercent"] >= 40, "domain-reduction-not-meaningful")
    require(reductions["workflow15kOpencodeLspConfigurePercent"] >= 40, "workflow-reduction-not-meaningful")

    report = {
        "schema": "agentswitchboard.progressive-disclosure-validation.v1",
        "status": "FAIL" if failures else "PASS",
        "router": str(ROUTER_PATH.relative_to(ROOT)).replace("\\", "/"),
        "tokenEstimate": router["estimate"],
        "baseline": baseline,
        "after": {
            "orientation50k": orientation,
            "domain30k": domain_measure,
            "workflow15k": workflow_measure,
        },
        "reductions": reductions,
        "preservedGovernance": {"path": deep["path"], "expectedGitBlobSha": deep["expectedGitBlobSha"], "actualGitBlobSha": actual_deep_sha, "expectedBytes": deep["expectedBytes"], "actualBytes": actual_deep_size},
        "failures": failures,
    }

    if args.output:
        output = Path(args.output).expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"REPORT={output}")
    print(f"PROGRESSIVE_DISCLOSURE={report['status']} 50k={orientation['estimatedTokens']} 30k={domain_measure['estimatedTokens']} 15k={workflow_measure['estimatedTokens']} estimated_tokens")
    if failures:
        for failure in failures:
            print(f"FAIL={failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
