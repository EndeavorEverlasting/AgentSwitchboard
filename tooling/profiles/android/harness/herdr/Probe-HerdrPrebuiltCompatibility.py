#!/usr/bin/env python3
"""Ephemerally execute the exact pinned Herdr Linux-musl ARM64 asset on Termux.

This is a compatibility probe, not an installer. The binary is downloaded into a
private temporary directory, verified by exact size and SHA-256, run only with
--version under an isolated HOME/XDG sandbox, and deleted with the sandbox.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re, stat, subprocess, tempfile, urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE = Path(__file__).resolve().parent
SOURCE = BASE / "upstream-runtime-compatibility.json"


def state_root() -> Path:
    xdg = os.environ.get("XDG_STATE_HOME")
    base = Path(xdg).expanduser() if xdg else Path.home() / ".local/state"
    return base / "agentswitchboard/android-herdr-migration"


def source() -> dict:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    prebuilt = data["compatibility"]["linuxMuslPrebuiltOnTermux"]
    assert data["reviewDecision"] == "EXECUTION_PROBE_APPROVED_NO_INSTALL"
    assert prebuilt["decision"] == "EXECUTION_PROBE_APPROVED_NO_INSTALL"
    assert prebuilt["buildTarget"] == "aarch64-unknown-linux-musl"
    return data


def clean(value: object) -> str:
    text = str(value).replace("\x00", "?").replace("\r", " ").replace("\n", " ")
    text = re.sub(r"\s+", " ", text).strip()
    return text[:500]


def write_evidence(fields: dict[str, object]) -> Path:
    root = state_root()
    root.mkdir(parents=True, exist_ok=True)
    path = root / f"herdr-prebuilt-exec-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.env"
    path.write_text("\n".join(f"{key}={clean(value)}" for key, value in fields.items()) + "\n", encoding="utf-8")
    return path


def contract(data: dict) -> int:
    src = data["source"]
    assert src["artifact"] == "herdr-linux-aarch64"
    assert src["artifactSizeBytes"] == 19960864
    assert src["artifactSha256"] == "f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87"
    assert data["compatibility"]["nativeAndroidSourceBuild"]["decision"] == "BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK"
    print("HERDR_PREBUILT_COMPATIBILITY_CONTRACT=PASS")
    print("DECISION=EXECUTION_PROBE_APPROVED_NO_INSTALL")
    print("MIGRATION_DECISION=KEEP_TMUX")
    print("NEXT_GATE=exact-device-prebuilt-execution-identity")
    return 0


def evidence(data: dict) -> int:
    prefix = os.environ.get("PREFIX", "")
    if "com.termux" not in prefix or not Path(prefix).is_dir():
        raise SystemExit("[FAIL] evidence mode requires a real Termux environment; no download was attempted")

    src = data["source"]
    fields: dict[str, object] = {
        "schema": "agentswitchboard.android-herdr-prebuilt-exec.v1",
        "release_tag": src["releaseTag"],
        "release_commit": src["releaseCommit"],
        "artifact": src["artifact"],
        "build_target": data["compatibility"]["linuxMuslPrebuiltOnTermux"]["buildTarget"],
        "expected_size_bytes": src["artifactSizeBytes"],
        "expected_sha256": src["artifactSha256"],
        "download_status": "unproved",
        "size_verified": "no",
        "digest_verified": "no",
        "version_exit_code": "not-run",
        "version_output": "not-run",
        "exec_compatibility": "UNPROVED",
        "migration_decision": "KEEP_TMUX",
        "next_gate": "exact-device-prebuilt-execution-identity",
        "proof_level": "prebuilt-exec-identity-only",
    }
    outcome = 20
    error = ""
    try:
        with tempfile.TemporaryDirectory(prefix="agentswitchboard-herdr-probe-") as td:
            sandbox = Path(td)
            candidate = sandbox / "herdr-linux-aarch64"
            digest = hashlib.sha256()
            size = 0
            request = urllib.request.Request(src["artifactUrl"], headers={"User-Agent": "AgentSwitchboard-Herdr-Compatibility-Probe/1"})
            with urllib.request.urlopen(request, timeout=45) as response, candidate.open("wb") as handle:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    size += len(chunk)
                    if size > int(src["artifactSizeBytes"]):
                        raise RuntimeError("download exceeded pinned artifact size")
                    digest.update(chunk)
                    handle.write(chunk)
            fields["download_status"] = "pass"
            if size != int(src["artifactSizeBytes"]):
                raise RuntimeError(f"size mismatch: expected {src['artifactSizeBytes']}, received {size}")
            fields["size_verified"] = "yes"
            actual = digest.hexdigest()
            if actual != src["artifactSha256"]:
                raise RuntimeError(f"sha256 mismatch: expected {src['artifactSha256']}, received {actual}")
            fields["digest_verified"] = "yes"
            candidate.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)

            run_home = sandbox / "home"
            run_home.mkdir()
            env = os.environ.copy()
            env.update({
                "HOME": str(run_home),
                "XDG_CONFIG_HOME": str(run_home / "config"),
                "XDG_DATA_HOME": str(run_home / "data"),
                "XDG_STATE_HOME": str(run_home / "state"),
                "XDG_CACHE_HOME": str(run_home / "cache"),
                "TMPDIR": str(sandbox),
                "NO_COLOR": "1",
            })
            try:
                result = subprocess.run(
                    [str(candidate), "--version"],
                    cwd=sandbox,
                    env=env,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    timeout=10,
                    check=False,
                )
                output = clean(result.stdout)
                fields["version_exit_code"] = result.returncode
                fields["version_output"] = output
                if result.returncode == 0 and "herdr" in output.lower() and "0.8.0" in output:
                    fields["exec_compatibility"] = "PASS"
                    fields["next_gate"] = "bounded-server-start-review"
                    outcome = 0
                else:
                    fields["exec_compatibility"] = "FAIL"
                    fields["next_gate"] = "prebuilt-execution-compatibility-repair"
                    outcome = 21
            except subprocess.TimeoutExpired:
                fields["version_exit_code"] = "timeout"
                fields["version_output"] = "--version exceeded 10 second compatibility timeout"
                fields["exec_compatibility"] = "FAIL"
                fields["next_gate"] = "prebuilt-execution-compatibility-repair"
                outcome = 22
            except OSError as exc:
                fields["version_exit_code"] = f"oserror-{exc.errno}"
                fields["version_output"] = clean(str(exc).replace(str(sandbox), "<sandbox>"))
                fields["exec_compatibility"] = "FAIL"
                fields["next_gate"] = "prebuilt-execution-compatibility-repair"
                outcome = 23
    except Exception as exc:
        error = clean(str(exc))
        fields["download_status"] = "fail" if fields["download_status"] == "unproved" else fields["download_status"]
        fields["exec_compatibility"] = "UNPROVED"
        fields["next_gate"] = "repair-prebuilt-probe-input-or-network"
        outcome = 24

    if error:
        fields["error"] = error
    artifact = write_evidence(fields)
    print(f"EVIDENCE={artifact}")
    for key in ("download_status", "size_verified", "digest_verified", "version_exit_code", "version_output", "exec_compatibility", "migration_decision", "next_gate", "proof_level"):
        print(f"{key.upper()}={fields[key]}")
    return outcome


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=("contract", "evidence"), nargs="?", default="contract")
    a = p.parse_args()
    data = source()
    return contract(data) if a.mode == "contract" else evidence(data)


if __name__ == "__main__":
    raise SystemExit(main())
