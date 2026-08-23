from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
H = ROOT / "tooling" / "harness" / "operational" / "opencode-lsp-setup"
ROUTER = H / "Recover-OpenCodeRuntime.ps1"
INSTALLER_COMMIT = "3a31c4ea801915c0b050df4b3842997ea62b6e93"


def read_router() -> str:
    return ROUTER.read_text(encoding="utf-8")


def literal_here_string(text: str, variable: str) -> str:
    marker = f"${variable} = @'\n"
    start = text.index(marker) + len(marker)
    end = text.index("\n'@", start)
    return text[start:end]


def install_payload(installer_path: str, timeout_seconds: str = "5") -> str:
    return (
        literal_here_string(read_router(), "installScript")
        .replace("__INSTALL_TIMEOUT__", timeout_seconds)
        .replace("__INSTALLER_COMMIT__", INSTALLER_COMMIT)
        .replace("__INSTALLER_PATH__", installer_path)
    )


def health_payload(probe_timeout: str = "2", kill_after: str = "1") -> str:
    return (
        literal_here_string(read_router(), "postInstallDiscoveryScript")
        .replace("__RUNTIME_PROBE_TIMEOUT__", probe_timeout)
        .replace("__RUNTIME_KILL_AFTER__", kill_after)
    )


def write_fake_curl(path: Path, installer_body: str) -> None:
    path.write_text(
        "#!/usr/bin/env bash\n"
        "set -u\n"
        "output=''\n"
        "while [ \"$#\" -gt 0 ]; do\n"
        "  if [ \"$1\" = '-o' ]; then\n"
        "    shift\n"
        "    output=\"${1:-}\"\n"
        "  fi\n"
        "  shift || true\n"
        "done\n"
        "[ -n \"$output\" ] || exit 91\n"
        "cat >\"$output\" <<'INSTALLER'\n"
        + installer_body
        + "\nINSTALLER\n"
        "chmod 755 \"$output\"\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


class TestOpenCodeInstallerExitGrounding(unittest.TestCase):
    def test_nonzero_installer_exit_is_not_terminal_before_health_probe(self) -> None:
        text = read_router()
        install_start = text.index("$installResult = Invoke-WslBash -Script $installScript")
        health_start = text.index("$script:stage = 'post-install-command-discovery'")
        post_probe = text.index("$postDiscovery = Invoke-WslBash -Script $postInstallDiscoveryScript")
        healthy_acceptance = text.index("$script:installerNonzeroRuntimeHealthy = $true")
        pre_health = text[install_start:health_start]

        self.assertIn(
            'SHELL=/bin/bash timeout --signal=TERM --kill-after=10s __INSTALL_TIMEOUT__s bash "__INSTALLER_PATH__" --no-modify-path',
            text,
        )
        self.assertNotIn("Stop-Recovery 'OPENCODE_INSTALL_FAILED'", pre_health)
        self.assertLess(post_probe, healthy_acceptance)
        for token in (
            "$script:installerExitCode = $installResult.ExitCode",
            "$script:installerStdoutPresent =",
            "$script:installerStderrPresent =",
            "$script:installerNonzeroRuntimeHealthy = $true",
            "OPENCODE_INSTALLER_NONZERO_RUNTIME_HEALTHY=",
            "installerExitCode = $script:installerExitCode",
            "installerNonzeroRuntimeHealthy = $script:installerNonzeroRuntimeHealthy",
        ):
            self.assertIn(token, text, token)

    @unittest.skipIf(os.name == "nt", "Bash payload semantics are exercised on Ubuntu CI")
    def test_nonzero_installer_with_healthy_exact_path_is_observably_healthy(self) -> None:
        installer_body = """#!/usr/bin/env bash
set -eu
[ "${SHELL:-}" = "/bin/bash" ] || exit 92
mkdir -p "$HOME/.opencode/bin"
cat >"$HOME/.opencode/bin/opencode" <<'BINARY'
#!/usr/bin/env bash
printf '1.2.3\\n'
BINARY
chmod 755 "$HOME/.opencode/bin/opencode"
exit 1"""

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            home = root / "home"
            home.mkdir()
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            fake_curl = fake_bin / "curl"
            write_fake_curl(fake_curl, installer_body)
            installer_path = root / "opencode.install.sh"

            env = os.environ.copy()
            env["HOME"] = str(home)
            env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
            env.pop("SHELL", None)

            installed = subprocess.run(
                ["bash", "-c", install_payload(str(installer_path))],
                env=env,
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )
            self.assertEqual(1, installed.returncode, installed.stderr)

            observed = subprocess.run(
                ["bash", "-c", health_payload()],
                env=env,
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )
            self.assertEqual(0, observed.returncode, observed.stderr)
            self.assertIn("STATE=healthy", observed.stdout)
            self.assertIn("EXIT=0", observed.stdout)
            self.assertIn("CLASS=none", observed.stdout)
            self.assertIn("VERSION=1.2.3", observed.stdout)

    @unittest.skipIf(os.name == "nt", "Bash payload semantics are exercised on Ubuntu CI")
    def test_nonzero_installer_without_binary_is_observably_missing(self) -> None:
        installer_body = """#!/usr/bin/env bash
set -eu
[ "${SHELL:-}" = "/bin/bash" ] || exit 92
exit 1"""

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            home = root / "home"
            home.mkdir()
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            fake_curl = fake_bin / "curl"
            write_fake_curl(fake_curl, installer_body)
            installer_path = root / "opencode.install.sh"

            env = os.environ.copy()
            env["HOME"] = str(home)
            env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
            env.pop("SHELL", None)

            installed = subprocess.run(
                ["bash", "-c", install_payload(str(installer_path))],
                env=env,
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )
            self.assertEqual(1, installed.returncode, installed.stderr)

            observed = subprocess.run(
                ["bash", "-c", health_payload()],
                env=env,
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )
            self.assertEqual(45, observed.returncode, observed.stderr)
            self.assertIn("STATE=missing", observed.stdout)
            self.assertIn("EXIT=45", observed.stdout)
            self.assertIn("CLASS=missing", observed.stdout)


if __name__ == "__main__":
    unittest.main()
