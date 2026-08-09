#!/usr/bin/env python3
"""Bounded foreground Herdr server start/status/stop probe for real Termux.

This is not an installer and does not use Herdr's auto-detect daemon launch.
The exact pinned binary is re-downloaded into a private temporary sandbox,
verified by size/SHA-256, started only as `herdr server`, observed only through
`herdr status server --json`, stopped only with `herdr server stop`, and removed.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re, signal, stat, subprocess, tempfile, time, urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE=Path(__file__).resolve().parent
SOURCE=BASE/"upstream-server-start-source.json"

def state_root() -> Path:
    xdg=os.environ.get("XDG_STATE_HOME")
    base=Path(xdg).expanduser() if xdg else Path.home()/".local/state"
    return base/"agentswitchboard/android-herdr-migration"

def clean(value: object, limit: int=700) -> str:
    text=str(value).replace("\x00","?").replace("\r"," ").replace("\n"," ")
    return re.sub(r"\s+"," ",text).strip()[:limit]

def load_source() -> dict:
    data=json.loads(SOURCE.read_text(encoding="utf-8"))
    assert data["schema"]=="agentswitchboard.android-herdr-server-start-source.v1"
    assert data["reviewDecision"]=="BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL"
    assert data["migrationDecision"]=="KEEP_TMUX"
    p=data["probe"]
    assert p["launchCommand"]==["herdr","server"]
    assert p["statusCommand"]==["herdr","status","server","--json"]
    assert p["stopCommand"]==["herdr","server","stop"]
    assert "run bare `herdr` auto-detect launch" in p["forbiddenActions"]
    return data

def parse_env(path: Path) -> dict[str,str]:
    out={}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if raw and not raw.startswith("#") and "=" in raw:
            k,v=raw.split("=",1); out[k]=v
    return out

def newest_prebuilt(root: Path) -> Path|None:
    if not root.is_dir(): return None
    found=sorted(root.glob("herdr-prebuilt-exec-*.env"))
    return found[-1] if found else None

def valid_prebuilt(path: Path|None, data: dict) -> bool:
    if not path or not path.is_file(): return False
    ev=parse_env(path); pre=data["precondition"]
    return (ev.get("schema")==pre["requiredEvidenceSchema"] and ev.get("release_commit")==pre["requiredReleaseCommit"] and ev.get("artifact")==pre["requiredArtifact"] and ev.get("expected_sha256")==pre["requiredSha256"] and ev.get("expected_size_bytes")=="19960864" and ev.get("size_verified")=="yes" and ev.get("digest_verified")=="yes" and ev.get("version_exit_code")=="0" and pre["requiredVersionOutputContains"].lower() in ev.get("version_output","").lower() and ev.get("exec_compatibility")==pre["requiredExecCompatibility"])

def write_evidence(fields: dict[str,object]) -> Path:
    root=state_root(); root.mkdir(parents=True,exist_ok=True)
    path=root/f"herdr-server-start-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.env"
    path.write_text("\n".join(f"{k}={clean(v)}" for k,v in fields.items())+"\n",encoding="utf-8")
    return path

def proc_children(pid: int) -> list[int]:
    p=Path(f"/proc/{pid}/task/{pid}/children")
    try: raw=p.read_text(encoding="utf-8").strip()
    except OSError: return []
    return [int(x) for x in raw.split() if x.isdigit()]

def descendants(pid: int) -> list[int]:
    seen=set(); stack=[pid]; result=[]
    while stack:
        current=stack.pop()
        for child in proc_children(current):
            if child not in seen: seen.add(child); result.append(child); stack.append(child)
    return result

def alive(pid: int) -> bool:
    try: os.kill(pid,0); return True
    except OSError: return False

def force_cleanup(pid: int) -> bool:
    targets=list(reversed(descendants(pid)))+[pid]; used=False
    for sig in (signal.SIGTERM, signal.SIGKILL):
        current=[p for p in targets if alive(p)]
        if not current: return used
        used=True
        for p in current:
            try: os.kill(p,sig)
            except OSError: pass
        deadline=time.monotonic()+2.0
        while time.monotonic()<deadline and any(alive(p) for p in current): time.sleep(0.05)
    return used

def run_json(cmd: list[str], *, env: dict[str,str], cwd: Path, timeout: int) -> tuple[int,dict|None,str]:
    try: r=subprocess.run(cmd,cwd=cwd,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout,check=False)
    except subprocess.TimeoutExpired: return 124,None,"timeout"
    text=clean(r.stdout)
    try: payload=json.loads(r.stdout)
    except Exception: payload=None
    return r.returncode,payload,text

def contract(data: dict) -> int:
    src=data["source"]; p=data["probe"]
    assert src["artifactSizeBytes"]==19960864
    assert src["artifactSha256"]=="f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87"
    assert p["launchMode"]=="foreground-headless-direct" and p["startTimeoutSeconds"]<=10 and p["commandTimeoutSeconds"]<=20
    print("HERDR_SERVER_START_CONTRACT=PASS\nDECISION=BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL\nMIGRATION_DECISION=KEEP_TMUX\nNEXT_GATE=exact-device-foreground-server-start-stop")
    return 0

def evidence(data: dict, explicit_prebuilt: Path|None) -> int:
    prefix=os.environ.get("PREFIX","")
    if "com.termux" not in prefix or not Path(prefix).is_dir(): raise SystemExit("[FAIL] evidence mode requires a real Termux environment; no download or server start was attempted")
    root=state_root(); prebuilt=explicit_prebuilt.expanduser() if explicit_prebuilt else newest_prebuilt(root)
    if not valid_prebuilt(prebuilt,data): raise SystemExit("[FAIL] exact-device PASS prebuilt execution evidence is required; no download or server start was attempted")
    src=data["source"]; cfg=data["probe"]
    fields:dict[str,object]={"schema":"agentswitchboard.android-herdr-server-start.v1","release_tag":src["releaseTag"],"release_commit":src["releaseCommit"],"artifact":src["artifact"],"expected_size_bytes":src["artifactSizeBytes"],"expected_sha256":src["artifactSha256"],"prebuilt_evidence":str(prebuilt),"prebuilt_identity_verified":"yes","download_status":"unproved","size_verified":"no","digest_verified":"no","launch_command":"herdr server","launch_mode":"foreground-headless-direct","status_exit_code":"not-run","status_running":"unproved","status_version":"unproved","status_protocol":"unproved","status_compatible":"unproved","status_socket":"unproved","detached_server_daemon_capability":"unproved","stop_exit_code":"not-run","post_stop_running":"unproved","server_exit_code":"not-run","forced_cleanup":"no","server_lifecycle":"UNPROVED","migration_decision":"KEEP_TMUX","next_gate":"exact-device-foreground-server-start-stop","proof_level":"foreground-server-start-status-stop-only"}
    outcome=40; error=""; server=None
    try:
        with tempfile.TemporaryDirectory(prefix="agentswitchboard-herdr-server-probe-") as td:
            sandbox=Path(td); candidate=sandbox/src["artifact"]; digest=hashlib.sha256(); size=0
            req=urllib.request.Request(src["artifactUrl"],headers={"User-Agent":"AgentSwitchboard-Herdr-Server-Probe/1"})
            with urllib.request.urlopen(req,timeout=45) as response, candidate.open("wb") as handle:
                while True:
                    chunk=response.read(1024*1024)
                    if not chunk: break
                    size+=len(chunk)
                    if size>int(src["artifactSizeBytes"]): raise RuntimeError("download exceeded pinned artifact size")
                    digest.update(chunk); handle.write(chunk)
            fields["download_status"]="pass"
            if size!=int(src["artifactSizeBytes"]): raise RuntimeError(f"size mismatch: expected {src['artifactSizeBytes']}, received {size}")
            fields["size_verified"]="yes"; actual=digest.hexdigest()
            if actual!=src["artifactSha256"]: raise RuntimeError(f"sha256 mismatch: expected {src['artifactSha256']}, received {actual}")
            fields["digest_verified"]="yes"; candidate.chmod(stat.S_IRUSR|stat.S_IWUSR|stat.S_IXUSR)
            home=sandbox/"home"; config_home=sandbox/"config"; run_state=sandbox/"state"; data_home=sandbox/"data"; cache_home=sandbox/"cache"; temp_home=sandbox/"tmp"
            for p in (home,config_home,run_state,data_home,cache_home,temp_home): p.mkdir()
            config_path=config_home/"herdr"/"config.toml"; config_path.parent.mkdir()
            config_path.write_text('onboarding = false\n\n[update]\nversion_check = false\nmanifest_check = false\n\n[ui.toast]\ndelivery = "off"\n\n[ui.sound]\nenabled = false\n\n[session]\nresume_agents_on_restore = false\n',encoding="utf-8")
            api_socket=sandbox/"probe.sock"; env=os.environ.copy()
            env.update({"HOME":str(home),"XDG_CONFIG_HOME":str(config_home),"XDG_STATE_HOME":str(run_state),"XDG_DATA_HOME":str(data_home),"XDG_CACHE_HOME":str(cache_home),"TMPDIR":str(temp_home),"HERDR_CONFIG_PATH":str(config_path),"HERDR_SOCKET_PATH":str(api_socket),"NO_COLOR":"1"})
            env.pop("HERDR_SESSION",None); env.pop("HERDR_CLIENT_SOCKET_PATH",None)
            console=sandbox/"server-console.log"
            with console.open("w",encoding="utf-8") as log: server=subprocess.Popen([str(candidate),"server"],cwd=sandbox,env=env,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,text=True,start_new_session=True)
            deadline=time.monotonic()+int(cfg["startTimeoutSeconds"]); status_payload=None; status_text=""; status_rc=1
            while time.monotonic()<deadline:
                if server.poll() is not None: break
                status_rc,status_payload,status_text=run_json([str(candidate),"status","server","--json"],env=env,cwd=sandbox,timeout=2)
                if status_rc==0 and status_payload and status_payload.get("running") is True: break
                time.sleep(0.1)
            fields["status_exit_code"]=status_rc
            if status_payload:
                fields["status_running"]="yes" if status_payload.get("running") is True else "no"; fields["status_version"]=status_payload.get("version","unknown"); fields["status_protocol"]=status_payload.get("protocol","unknown"); comp=status_payload.get("compatible"); fields["status_compatible"]="yes" if comp is True else ("no" if comp is False else "unknown"); fields["status_socket"]=status_payload.get("socket","unknown"); fields["detached_server_daemon_capability"]=(status_payload.get("capabilities") or {}).get("detached_server_daemon","unknown")
            else: fields["status_running"]="no"; fields["status_version"]="unknown"
            ready=(status_rc==0 and status_payload is not None and status_payload.get("running") is True and status_payload.get("version")=="0.8.0" and status_payload.get("compatible") is True and status_payload.get("socket")==str(api_socket))
            if not ready: raise RuntimeError(f"server readiness gate failed: {status_text or 'no running status'}")
            stop=subprocess.run([str(candidate),"server","stop"],cwd=sandbox,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=int(cfg["commandTimeoutSeconds"]),check=False); fields["stop_exit_code"]=stop.returncode
            if stop.returncode!=0: raise RuntimeError(f"server stop failed: {clean(stop.stdout)}")
            try: exit_code=server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                fields["forced_cleanup"]="yes"; force_cleanup(server.pid)
                try: server.wait(timeout=3)
                except subprocess.TimeoutExpired: pass
                raise RuntimeError("foreground server did not exit within 5 seconds after server stop")
            fields["server_exit_code"]=exit_code
            post_rc,post_payload,post_text=run_json([str(candidate),"status","server","--json"],env=env,cwd=sandbox,timeout=2); post_running=bool(post_payload and post_payload.get("running") is True); fields["post_stop_running"]="yes" if post_running else "no"
            if post_rc!=0 or post_payload is None or post_running: raise RuntimeError(f"post-stop status gate failed: {post_text}")
            if exit_code!=0: raise RuntimeError(f"foreground server exited with code {exit_code}")
            fields["server_console"]=clean(console.read_text(encoding="utf-8",errors="replace")); fields["server_lifecycle"]="PASS"; fields["next_gate"]="bounded-client-attach-review"; outcome=0
    except subprocess.TimeoutExpired as exc: error=f"command timeout: {clean(exc)}"; outcome=41
    except Exception as exc: error=clean(exc); outcome=42
    finally:
        if server is not None and server.poll() is None:
            fields["forced_cleanup"]="yes"; force_cleanup(server.pid)
            try: fields["server_exit_code"]=server.wait(timeout=2)
            except Exception: fields["server_exit_code"]="cleanup-timeout"
        if error: fields["error"]=error; fields["server_lifecycle"]="FAIL"; fields["next_gate"]="server-start-compatibility-repair"
    artifact=write_evidence(fields); print(f"EVIDENCE={artifact}")
    for key in ("prebuilt_identity_verified","download_status","size_verified","digest_verified","status_exit_code","status_running","status_version","status_protocol","status_compatible","status_socket","detached_server_daemon_capability","stop_exit_code","post_stop_running","server_exit_code","forced_cleanup","server_lifecycle","migration_decision","next_gate","proof_level"): print(f"{key.upper()}={fields[key]}")
    return outcome

def main() -> int:
    p=argparse.ArgumentParser(); p.add_argument("mode",choices=("contract","evidence"),nargs="?",default="contract"); p.add_argument("--prebuilt-evidence",type=Path); a=p.parse_args(); data=load_source(); return contract(data) if a.mode=="contract" else evidence(data,a.prebuilt_evidence)

if __name__=="__main__": raise SystemExit(main())
