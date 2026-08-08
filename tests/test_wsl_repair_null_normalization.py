# tests/test_wsl_repair_null_normalization.py
# Regression coverage for PowerShell 7 NUL removal in WSL distro enumeration.

import os
import shutil
import subprocess
import unittest


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WSL_REPAIR_PATH = os.path.join(
    REPO_ROOT,
    "tooling",
    "profiles",
    "windows",
    "technician-live-cert",
    "stages",
    "Repair-Technician-WSL-Ubuntu.ps1",
)
SAFE_EXPRESSION = ".Replace(([char]0).ToString(), [string]::Empty)"
AMBIGUOUS_EXPRESSION = ".Replace([char]0, '')"


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


class TestWslRepairNullNormalization(unittest.TestCase):
    def test_repair_uses_explicit_string_replace_overload(self):
        repair = read_text(WSL_REPAIR_PATH)
        self.assertIn(SAFE_EXPRESSION, repair)
        self.assertNotIn(AMBIGUOUS_EXPRESSION, repair)

    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell 7 is not available")
    def test_corrected_expression_removes_embedded_nuls_in_pwsh(self):
        command = (
            "$value = 'U' + [char]0 + 'b' + [char]0 + 'u' + [char]0 + "
            "'n' + [char]0 + 't' + [char]0 + 'u'; "
            "$actual = ([string]$value).Replace(([char]0).ToString(), [string]::Empty).Trim(); "
            "if ($actual -ne 'Ubuntu') { throw \"Unexpected normalized value: $actual\" }; "
            "Write-Output $actual"
        )
        completed = subprocess.run(
            [
                shutil.which("pwsh"),
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                command,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        self.assertEqual("Ubuntu", completed.stdout.strip())


if __name__ == "__main__":
    unittest.main()
