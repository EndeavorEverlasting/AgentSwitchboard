import json
import os
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_text(path):
    with open(os.path.join(REPO_ROOT, path), "r", encoding="utf-8") as handle:
        return handle.read()


def load_json(path):
    return json.loads(read_text(path))


class TestMachineProfileHarnessCompleteness(unittest.TestCase):
    def setUp(self):
        self.manifest = load_json("tooling/profiles/windows/harness/machine-profile/manifest.json")

    def test_registered_files_exist(self):
        keys = ["codebaseMap", "machineProfileRegistry", "environmentRoleRegistry", "knownTrapsRegistry", "artifactRegistry", "workflowSpecs", "schemaPath", "skill", "operatorDocumentation", "operatorReportTemplate", "statusReporter", "statusCommand", "validator", "validatorCommand", "pythonValidator", "preCommitHook", "ciWorkflow"]
        missing = [self.manifest[key] for key in keys if not os.path.isfile(os.path.join(REPO_ROOT, self.manifest[key]))]
        self.assertEqual([], missing)

    def test_roles_are_exact_and_paths_local_only(self):
        registry = load_json(self.manifest["environmentRoleRegistry"])
        roles = {role["roleId"]: role for role in registry["roles"]}
        self.assertEqual({"personal-windows-laptop", "desktop-workstation", "admin-box-1", "admin-box-2"}, set(roles))
        self.assertEqual(r"%USERPROFILE%\Desktop\Dev", roles["personal-windows-laptop"]["pathResolution"]["workspacePattern"])
        for role in roles.values():
            self.assertFalse(role["pathResolution"]["committedResolvedPathAllowed"])

    def test_workflows_and_traps_are_complete(self):
        workflows = load_json(self.manifest["workflowSpecs"])
        self.assertEqual({"machine-profile-task-intake", "machine-profile-validation", "machine-profile-failure-recovery", "machine-profile-handoff"}, {item["workflowId"] for item in workflows["workflows"]})
        traps = load_json(self.manifest["knownTrapsRegistry"])
        ids = {item["id"] for item in traps["traps"]}
        self.assertTrue({"shell-mismatch", "errorlevel-clobber", "downstream-after-failure", "unsafe-powershell-null-replace", "remembered-path", "pull-over-local-patch", "path-role-collapse"}.issubset(ids))
        null_trap = next(item for item in traps["traps"] if item["id"] == "unsafe-powershell-null-replace")
        self.assertEqual(".Replace(([char]0).ToString(), [string]::Empty)", null_trap["safeExpression"])

    def test_generated_artifacts_are_untracked(self):
        registry = load_json(self.manifest["artifactRegistry"])
        self.assertTrue(registry["generatedArtifacts"])
        for artifact in registry["generatedArtifacts"]:
            self.assertFalse(artifact["tracked"])

    def test_no_real_machine_literals(self):
        paths = [self.manifest[key] for key in ("codebaseMap", "environmentRoleRegistry", "knownTrapsRegistry", "skill", "operatorDocumentation")]
        text = "\n".join(read_text(path) for path in paths)
        for forbidden in ("CheeksMcClappeth", "pa_rperez26", "OneDrive - Northwell Health"):
            self.assertNotIn(forbidden, text)


if __name__ == "__main__":
    unittest.main()
