#!/usr/bin/env python3
"""Cross-platform repository-family harness validator for AgentSwitchboard.

This validator re-implements the deterministic checks from
scripts/Test-RepositoryFamilyHarness.ps1 in pure Python so the harness
contract can be exercised on Linux, macOS, or any environment without
PowerShell installed. It does not replace the PowerShell validator; it
complements it.

Run directly:
    python3 scripts/validate_harness.py

Exit code 0 when all checks pass; 1 otherwise.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent

REQUIRED_FILES = [
    "CODEBASE_MAP.md",
    ".ai/harness/manifest.json",
    ".ai/harness/repository-family.registry.json",
    ".ai/harness/artifact-registry.json",
    ".ai/harness/operator-report.template.md",
    ".ai/harness/workflows/repository-family-intake.workflow.json",
    ".ai/harness/schemas/repository-family-registry.schema.json",
    ".ai/harness/schemas/run-context.schema.json",
    ".ai/harness/schemas/repository-family-status.schema.json",
    ".ai/harness/schemas/final-handoff.schema.json",
    "scripts/Get-RepositoryFamilyHarnessStatus.ps1",
    "scripts/Test-RepositoryFamilyHarness.ps1",
]

EXPECTED_REPOSITORIES = [
    "EndeavorEverlasting/AgentSwitchboard",
    "EndeavorEverlasting/BlacksmithGuild",
    "EndeavorEverlasting/web-excel-repair-triage",
    "EndeavorEverlasting/SysAdminSuite",
]

WORKFLOW_FORBIDDEN_TOKENS = [
    "clone",
    "fetch",
    "push",
    "merge",
    "provider invocation",
    "live target mutation",
]


def _path_inside_repo(relative: str) -> Path:
    return REPO_ROOT / relative


def _load_json(relative: str) -> tuple[bool, Any | None, str]:
    path = _path_inside_repo(relative)
    if not path.is_file():
        return False, None, f"{relative}: file is missing"
    try:
        with path.open("r", encoding="utf-8-sig") as fh:
            return True, json.load(fh), ""
    except json.JSONDecodeError as exc:
        return False, None, f"{relative}: {exc}"


def _is_relative_path(value: str) -> bool:
    if not value or value.strip() != value:
        return False
    if os.path.isabs(value):
        return False
    if re.search(r"(^|[/\\])\.\.([/\\]|$)", value):
        return False
    return True


class HarnessValidator:
    def __init__(self) -> None:
        self.passes: list[str] = []
        self.failures: list[str] = []

    def _check(self, name: str, passed: bool, message: str = "") -> None:
        if passed:
            self.passes.append(name)
        else:
            self.failures.append(f"{name}: {message}" if message else name)

    def run(self) -> int:
        self._check_required_files()

        manifest_ok, manifest, manifest_err = _load_json(".ai/harness/manifest.json")
        self._check("manifest/load", manifest_ok, manifest_err)
        if manifest_ok:
            self._check_manifest(manifest)

        registry_ok, registry, registry_err = _load_json(".ai/harness/repository-family.registry.json")
        self._check("registry/load", registry_ok, registry_err)
        if registry_ok:
            self._check_registry(registry)
            self._check_registry_hygiene(registry)

        artifact_ok, artifacts, artifact_err = _load_json(".ai/harness/artifact-registry.json")
        self._check("artifact-registry/load", artifact_ok, artifact_err)
        if artifact_ok:
            self._check_artifact_registry(artifacts)

        workflow_ok, workflow, workflow_err = _load_json(".ai/harness/workflows/repository-family-intake.workflow.json")
        self._check("workflow/load", workflow_ok, workflow_err)
        if workflow_ok:
            self._check_workflow(workflow)

        self._check_schemas()
        self._check_powershell_parse()

        self._print_report()
        return 0 if not self.failures else 1

    def _check_required_files(self) -> None:
        for relative in REQUIRED_FILES:
            self._check(
                f"required-file/{relative}",
                _path_inside_repo(relative).is_file(),
                "required harness file is missing",
            )

    def _check_manifest(self, manifest: dict[str, Any]) -> None:
        self._check("manifest/schema-version", manifest.get("schemaVersion") == 1, "expected schemaVersion 1")
        self._check(
            "manifest/harness-id",
            manifest.get("harnessId") == "agentswitchboard.repository-family-harness.v1",
            "unexpected harnessId",
        )
        self._check(
            "manifest/canonical-repository",
            manifest.get("canonicalRepository") == "EndeavorEverlasting/AgentSwitchboard",
            "unexpected canonical repository",
        )
        self._check(
            "manifest/untracked-evidence",
            manifest.get("generatedEvidence", {}).get("tracked") is False,
            "generated family evidence must remain untracked",
        )
        self._check(
            "manifest/no-implicit-hooks",
            manifest.get("localHooks", {}).get("enabled") is False,
            "local hooks must remain disabled in the first slice",
        )
        entrypoints = manifest.get("entrypoints", {})
        for prop in [
            "agentRules",
            "codebaseMap",
            "skillsCatalog",
            "familyRegistry",
            "artifactRegistry",
            "workflow",
            "statusProbe",
            "validator",
            "operatorReportTemplate",
            "finalHandoffSchema",
        ]:
            value = entrypoints.get(prop, "")
            self._check(
                f"manifest/entrypoint/{prop}",
                _is_relative_path(value) and value != "",
                "entrypoint must be a non-empty repository-relative path",
            )

    def _check_registry(self, registry: dict[str, Any]) -> None:
        self._check("registry/schema-version", registry.get("schemaVersion") == 1, "expected schemaVersion 1")
        self._check(
            "registry/registry-id",
            registry.get("registryId") == "agentswitchboard.repository-family.v1",
            "unexpected registryId",
        )
        self._check(
            "registry/canonical-repository",
            registry.get("canonicalRepository") == "EndeavorEverlasting/AgentSwitchboard",
            "unexpected canonical repository",
        )
        self._check(
            "registry/default-branch-authority",
            registry.get("defaultBranchAuthorityRequired") is True,
            "default branch authority must be required",
        )

        repositories = registry.get("repositories", [])
        self._check("registry/repository-count", len(repositories) == 4, "registry must contain exactly four repositories")

        actual_names = [r.get("fullName") for r in repositories]
        for expected in EXPECTED_REPOSITORIES:
            self._check(
                f"registry/repository/{expected}",
                expected in actual_names,
                "required repository is not registered",
            )
        self._check(
            "registry/unique-repositories",
            len(set(actual_names)) == len(actual_names),
            "repository names must be unique",
        )

        canonical = [r for r in repositories if r.get("role") == "canonical-root"]
        self._check("registry/single-canonical-root", len(canonical) == 1, "exactly one canonical root is required")
        if len(canonical) == 1:
            self._check(
                "registry/canonical-root-identity",
                canonical[0].get("fullName") == "EndeavorEverlasting/AgentSwitchboard",
                "AgentSwitchboard must be the canonical root",
            )
            for required_path in canonical[0].get("requiredPaths", []):
                self._check(
                    f"registry/self-path/{required_path}",
                    _path_inside_repo(required_path).exists(),
                    "AgentSwitchboard required path is missing on this branch",
                )

        entrypoint_props = [
            "agentRules",
            "codebaseMap",
            "skillRoots",
            "workflowRoots",
            "runContextAuthorities",
            "artifactRegistryAuthorities",
            "validatorEntrypoints",
            "operatorReportAuthorities",
            "handoffAuthorities",
            "readOnlyIntelligence",
        ]
        for repository in repositories:
            repo_id = repository.get("id") or "unknown"
            self._check(f"registry/{repo_id}/id", bool(repo_id and repo_id != "unknown"), "repository id is missing")
            self._check(
                f"registry/{repo_id}/directory-names",
                len(repository.get("directoryNames", [])) > 0,
                "at least one local directory name is required",
            )
            self._check(
                f"registry/{repo_id}/required-paths",
                len(repository.get("requiredPaths", [])) > 0,
                "requiredPaths must not be empty",
            )
            self._check(
                f"registry/{repo_id}/validators",
                len(repository.get("validationCommands", [])) > 0,
                "validationCommands must not be empty",
            )
            self._check(
                f"registry/{repo_id}/untracked-output",
                repository.get("generatedOutputPolicy", {}).get("tracked") is False,
                "generated output must remain untracked",
            )
            proof_ceiling = repository.get("proofCeiling", "")
            self._check(
                f"registry/{repo_id}/proof-ceiling",
                bool(proof_ceiling) and re.search(r"only|Only", proof_ceiling) is not None,
                "proof ceiling must explicitly limit claims",
            )
            for path in repository.get("requiredPaths", []):
                self._check(
                    f"registry/{repo_id}/required-path/{path}",
                    _is_relative_path(path),
                    "required path must be repository-relative",
                )
            entrypoints = repository.get("entrypoints", {})
            for prop in entrypoint_props:
                value = entrypoints.get(prop)
                if prop == "codebaseMap":
                    self._check(
                        f"registry/{repo_id}/entrypoint/{prop}",
                        _is_relative_path(value) if value else False,
                        "codebase map must be repository-relative",
                    )
                else:
                    values = value if isinstance(value, list) else [value]
                    self._check(
                        f"registry/{repo_id}/entrypoint/{prop}",
                        len(values) > 0 and all(_is_relative_path(v) for v in values if v),
                        "entrypoint must be repository-relative and non-empty",
                    )

    def _check_registry_hygiene(self, registry: dict[str, Any]) -> None:
        raw_path = _path_inside_repo(".ai/harness/repository-family.registry.json")
        raw = raw_path.read_text(encoding="utf-8-sig")
        self._check(
            "registry/no-mutable-pr-state",
            re.search(r"(?i)pull/[0-9]+|PR\s*#[0-9]+|\b[a-f0-9]{40}\b", raw) is None,
            "durable registry must not embed PR numbers or commit SHAs",
        )
        self._check(
            "registry/no-machine-paths",
            re.search(r"(?i)[A-Z]:\\Users\\|/home/[^/]+/", raw) is None,
            "durable registry must not embed machine-local user paths",
        )

    def _check_artifact_registry(self, registry: dict[str, Any]) -> None:
        self._check("artifact-registry/schema-version", registry.get("schemaVersion") == 1, "expected schemaVersion 1")
        artifacts = registry.get("artifacts", [])
        self._check("artifact-registry/count", len(artifacts) == 4, "exactly four family artifact roles are required")
        for artifact in artifacts:
            artifact_id = artifact.get("artifactId", "unknown")
            self._check(
                f"artifact-registry/{artifact_id}/untracked",
                artifact.get("tracked") is False,
                "family run evidence must remain untracked",
            )
            self._check(
                f"artifact-registry/{artifact_id}/sensitivity",
                artifact.get("sensitivity") == "local-operational",
                "unexpected sensitivity class",
            )

    def _check_workflow(self, workflow: dict[str, Any]) -> None:
        self._check(
            "workflow/id",
            workflow.get("workflowId") == "repository-family-intake",
            "unexpected workflow id",
        )
        self._check(
            "workflow/entrypoint",
            workflow.get("entrypoint") == "scripts/Get-RepositoryFamilyHarnessStatus.ps1",
            "unexpected workflow entrypoint",
        )
        self._check(
            "workflow/proof-level",
            workflow.get("proofLevel") == "read-only-repository-intake",
            "unexpected workflow proof level",
        )
        forbidden = workflow.get("forbidden", [])
        for token in WORKFLOW_FORBIDDEN_TOKENS:
            self._check(
                f"workflow/forbidden/{token}",
                token in forbidden,
                "required forbidden action is missing",
            )

    def _check_schemas(self) -> None:
        schema_paths = [
            ".ai/harness/schemas/repository-family-registry.schema.json",
            ".ai/harness/schemas/run-context.schema.json",
            ".ai/harness/schemas/repository-family-status.schema.json",
            ".ai/harness/schemas/final-handoff.schema.json",
        ]
        for schema_path in schema_paths:
            ok, data, err = _load_json(schema_path)
            self._check(f"schema/{schema_path}/load", ok, err)
            if ok:
                self._check(
                    f"schema/{schema_path}/draft",
                    data.get("$schema") == "https://json-schema.org/draft/2020-12/schema",
                    "schema must use JSON Schema 2020-12",
                )
                self._check(
                    f"schema/{schema_path}/title",
                    bool(data.get("title")),
                    "schema title is missing",
                )

    def _check_powershell_parse(self) -> None:
        """Best-effort PowerShell parse check; skipped when pwsh is unavailable."""
        pwsh = shutil.which("pwsh")
        if not pwsh:
            self.passes.append("powershell/parse (skipped: pwsh not installed)")
            return

        for script_path in [
            "scripts/Test-RepositoryFamilyHarness.ps1",
            "scripts/Get-RepositoryFamilyHarnessStatus.ps1",
        ]:
            full = _path_inside_repo(script_path)
            try:
                cmd = (
                    f"$tokens=$null; $errors=$null; "
                    f"[void][System.Management.Automation.Language.Parser]::ParseFile('{full}', [ref]$tokens, [ref]$errors); "
                    f"if ($errors.Count -gt 0) {{ exit 1 }}"
                )
                result = subprocess.run(
                    [pwsh, "-NoLogo", "-NoProfile", "-Command", cmd],
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                self._check(
                    f"powershell/{script_path}/parse",
                    result.returncode == 0,
                    result.stderr.strip() or "parse errors",
                )
            except Exception as exc:
                self._check(f"powershell/{script_path}/parse", False, str(exc))

    def _print_report(self) -> None:
        print("REPOSITORY FAMILY HARNESS CONTRACT (Python validator)")
        for name in self.passes:
            print(f"[PASS] {name}")
        for name in self.failures:
            print(f"[FAIL] {name}")
        print(f"\nResult: {len(self.passes)} passed / {len(self.failures)} failed")


def main() -> int:
    validator = HarnessValidator()
    return validator.run()


if __name__ == "__main__":
    sys.exit(main())
