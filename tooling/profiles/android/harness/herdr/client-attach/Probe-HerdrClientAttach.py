#!/usr/bin/env python3
"""Bounded, no-install Herdr client-protocol observer probe for Android/Termux."""
from __future__ import annotations
import argparse, base64, datetime as dt, hashlib, json, os, selectors, signal, subprocess, tempfile, time, urllib.request
from pathlib import Path

BASE=Path(__file__).resolve().parent
SOURCE=BASE/"upstream-client-attach-source.json"
STATE_SUB=Path("agentswitchboard/android-herdr-migration")

def state_root()->Path:
    return Path(os.environ.get("XDG_STATE_HOME", str(Path.home()/".local/state")))/STATE_SUB

def parse_env(path:Path)->dict[str,str]:
    out={}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if "=" in raw:
            k,v=raw.split("=",1); out[k.strip()]=v.strip()
    return out

def latest_server_evidence()->Path:
    found=sorted(state_root().glob("herdr-server-start-*.env"), key=lambda p:p.stat().st_mtime, reverse=True)
    if not found: raise RuntimeError("no herdr-server-start-*.env evidence found")
    return found[0]

def source()->dict:
    d=json.loads(SOURCE.read_text(encoding="utf-8"))
    if d["reviewDecision"]!="BOUNDED_CLIENT_PROTOCOL_OBSERVER_PROBE_APPROVED_NO_INSTALL": raise RuntimeError("source decision is not approved")
    if d["fullAppTuiDecision"]!="BLOCKED_AUTODETECT_DAEMON_RACE": raise RuntimeError("full-app TUI decision invariant changed")
    return d

def validate_server_evidence(path:Path,d:dict)->dict[str,str]:
    e=parse_env(path); p=d["precondition"]
    checks={"schema":p["requiredEvidenceSchema"],"release_commit":p["requiredReleaseCommit"],"expected_sha256":p["requiredSha256"],"server_lifecycle":p["requiredLifecycle"],"status_running":p["requiredStatusRunning"],"status_version":p["requiredStatusVersion"],"status_compatible":p["requiredStatusCompatible"],"stop_exit_code":p["requiredStopExitCode"],"post_stop_running":p["requiredPostStopRunning"],"server_exit_code":p["requiredServerExitCode"],"forced_cleanup":p["requiredForcedCleanup"]}
    bad=[f"{k}={e.get(k)!r} expected {v!r}" for k,v in checks.items() if e.get(k)!=v]
    if bad: raise RuntimeError("server evidence prerequisite failed: "+"; ".join(bad))
    return e

def run(cmd,env,timeout=20,check=False):
    r=subprocess.run(cmd,env=env,text=True,capture_output=True,timeout=timeout)
    if check and r.returncode!=0: raise RuntimeError(f"command failed rc={r.returncode}: {cmd!r}: {r.stderr[-1000:]}")
    return r

def read_line(proc:subprocess.Popen,timeout:float)->str:
    sel=selectors.DefaultSelector(); sel.register(proc.stdout,selectors.EVENT_READ)
    events=sel.select(timeout)
    if not events: return ""
    return proc.stdout.readline()

def terminate(proc:subprocess.Popen|None, wait=3):
    if not proc or proc.poll() is not None: return False
    try: proc.terminate(); proc.wait(timeout=wait)
    except Exception:
        try: proc.kill(); proc.wait(timeout=wait)
        except Exception: pass
    return True

def contract():
    d=source()
    assert d["probe"]["observerCommand"][:4]==["herdr","terminal","session","observe"]
    assert d["probe"]["readOnlyDiscoveryCommand"]==["herdr","pane","list"]
    assert "bare `herdr`" in " ".join(d["probe"]["forbiddenActions"])
    src=Path(__file__).read_text(encoding="utf-8")
    for required in ('["server"]','["pane","list"]','["terminal","session","observe"','["server","stop"]'):
        assert required in src, required
    print("HERDR_CLIENT_ATTACH_CONTRACT=PASS")
    print("DECISION=BOUNDED_CLIENT_PROTOCOL_OBSERVER_PROBE_APPROVED_NO_INSTALL")
    print("FULL_APP_TUI_DECISION=BLOCKED_AUTODETECT_DAEMON_RACE")
    print("MIGRATION_DECISION=KEEP_TMUX")
    print("NEXT_GATE=exact-device-client-protocol-observer-frame")

def evidence(server_evidence:Path|None)->int:
    d=source(); server_evidence=server_evidence or latest_server_evidence()
    result={"schema":"agentswitchboard.android-herdr-client-attach.v1","release_tag":d["source"]["releaseTag"],"release_commit":d["source"]["releaseCommit"],"artifact":d["source"]["artifact"],"expected_size_bytes":str(d["source"]["artifactSizeBytes"]),"expected_sha256":d["source"]["artifactSha256"],"server_evidence":str(server_evidence),"server_evidence_verified":"no","download_status":"not-run","size_verified":"no","digest_verified":"no","server_status_running":"no","server_status_version":"","discovery_exit_code":"","pane_count":"0","observer_target_terminal_id":"","observer_frame_received":"no","observer_frame_seq":"","observer_frame_encoding":"","observer_exit_code":"","stop_exit_code":"","post_stop_running":"","server_exit_code":"","forced_cleanup":"no","client_protocol_observer":"FAIL","full_app_tui_attached":"no","migration_decision":"KEEP_TMUX","next_gate":"bounded-client-attach-review","proof_level":"client-protocol-observer-frame-unproved"}
    server=None; observer=None; sandbox=None; candidate=None
    try:
        validate_server_evidence(server_evidence,d); result["server_evidence_verified"]="yes"
        with tempfile.TemporaryDirectory(prefix="agentswitchboard-herdr-client-probe-") as td:
            sandbox=Path(td); candidate=sandbox/"herdr"
            try:
                with urllib.request.urlopen(d["source"]["artifactUrl"],timeout=30) as response: data=response.read()
                result["download_status"]="pass"
            except Exception as exc:
                result["download_status"]="fail"; raise RuntimeError(f"download failed: {exc}")
            if len(data)!=d["source"]["artifactSizeBytes"]: raise RuntimeError("artifact size mismatch")
            result["size_verified"]="yes"
            if hashlib.sha256(data).hexdigest()!=d["source"]["artifactSha256"]: raise RuntimeError("artifact digest mismatch")
            result["digest_verified"]="yes"; candidate.write_bytes(data); candidate.chmod(0o700)
            home=sandbox/"home"; config=sandbox/"config"; state=sandbox/"state"; cache=sandbox/"cache"; tmp=sandbox/"tmp"
            for p in (home,config,state,cache,tmp): p.mkdir()
            (config/"herdr").mkdir(); (config/"herdr"/"config.toml").write_text("onboarding = false\n\n[update]\nversion_check = false\nmanifest_check = false\n\n[ui]\nmouse_capture = false\n",encoding="utf-8")
            env=os.environ.copy(); env.update({"HOME":str(home),"XDG_CONFIG_HOME":str(config),"XDG_STATE_HOME":str(state),"XDG_CACHE_HOME":str(cache),"TMPDIR":str(tmp),"HERDR_SOCKET_PATH":str(sandbox/"probe.sock"),"HERDR_LOG":"herdr=info"})
            server=subprocess.Popen([str(candidate),"server"],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True)
            deadline=time.time()+d["probe"]["serverReadyTimeoutSeconds"]; status=None
            while time.time()<deadline:
                if server.poll() is not None: raise RuntimeError(f"server exited early rc={server.returncode}")
                r=run([str(candidate),"status","server","--json"],env,timeout=3)
                if r.returncode==0:
                    try:
                        s=json.loads(r.stdout)
                        if s.get("running") is True: status=s; break
                    except Exception: pass
                time.sleep(.1)
            if not status: raise RuntimeError("foreground server readiness timeout")
            result["server_status_running"]="yes"; result["server_status_version"]=str(status.get("version") or "")
            if result["server_status_version"]!="0.8.0" or status.get("compatible") is not True: raise RuntimeError("server identity/protocol mismatch")
            listing=run([str(candidate),"pane","list"],env,check=True); result["discovery_exit_code"]=str(listing.returncode)
            payload=json.loads(listing.stdout); panes=payload.get("result",{}).get("panes",[]); result["pane_count"]=str(len(panes))
            if not panes: raise RuntimeError("pane list returned no existing panes; workspace mutation is forbidden")
            target=panes[0].get("terminal_id")
            if not target: raise RuntimeError("pane list lacks terminal_id")
            result["observer_target_terminal_id"]=str(target)
            observer=subprocess.Popen([str(candidate),"terminal","session","observe",str(target),"--cols","80","--rows","24"],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
            line=read_line(observer,d["probe"]["observerFrameTimeoutSeconds"])
            if not line:
                if observer.poll() is not None: raise RuntimeError(f"observer exited before frame rc={observer.returncode}: {observer.stderr.read()[-1000:]}")
                raise RuntimeError("observer frame timeout")
            frame=json.loads(line)
            if frame.get("type")!="terminal.frame" or frame.get("encoding")!="ansi": raise RuntimeError(f"unexpected observer envelope: {frame.get('type')!r}/{frame.get('encoding')!r}")
            base64.b64decode(frame.get("bytes",""),validate=True)
            result["observer_frame_received"]="yes"; result["observer_frame_seq"]=str(frame.get("seq","")); result["observer_frame_encoding"]="ansi"
            stop=run([str(candidate),"server","stop"],env,timeout=d["probe"]["commandTimeoutSeconds"]); result["stop_exit_code"]=str(stop.returncode)
            if stop.returncode!=0: raise RuntimeError(f"server stop failed: {stop.stderr[-1000:]}")
            observer.wait(timeout=d["probe"]["commandTimeoutSeconds"]); result["observer_exit_code"]=str(observer.returncode)
            if observer.returncode!=0: raise RuntimeError(f"observer exit rc={observer.returncode}: {observer.stderr.read()[-1000:]}")
            server.wait(timeout=d["probe"]["commandTimeoutSeconds"]); result["server_exit_code"]=str(server.returncode)
            if server.returncode!=0: raise RuntimeError(f"server exit rc={server.returncode}")
            post=run([str(candidate),"status","server","--json"],env,timeout=5,check=True); ps=json.loads(post.stdout); result["post_stop_running"]="yes" if ps.get("running") else "no"
            if ps.get("running") is not False: raise RuntimeError("post-stop status still running")
            result["client_protocol_observer"]="PASS"; result["next_gate"]="bounded-full-tui-attach-review"; result["proof_level"]="client-protocol-observer-frame-only"
    except Exception as exc:
        result["error"]=str(exc).replace("\n"," ")[:1200]
    finally:
        if observer and observer.poll() is None: result["forced_cleanup"]="yes" if terminate(observer) else result["forced_cleanup"]
        if server and server.poll() is None:
            try: os.killpg(server.pid,signal.SIGTERM); server.wait(timeout=3); result["forced_cleanup"]="yes"
            except Exception:
                try: os.killpg(server.pid,signal.SIGKILL); server.wait(timeout=3); result["forced_cleanup"]="yes"
                except Exception: pass
        out=state_root()/f"herdr-client-attach-{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.env"; out.parent.mkdir(parents=True,exist_ok=True)
        keys=list(result); out.write_text("\n".join(f"{k}={str(result[k]).replace(chr(10),' ')}" for k in keys)+"\n",encoding="utf-8")
        print(f"EVIDENCE={out}")
        for k in keys: print(f"{k.upper()}={result[k]}")
    return 0 if result["client_protocol_observer"]=="PASS" else 1

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("mode",choices=["contract","evidence"]); ap.add_argument("--server-evidence",type=Path); a=ap.parse_args()
    if a.mode=="contract": contract(); return
    raise SystemExit(evidence(a.server_evidence))
if __name__=="__main__": main()
