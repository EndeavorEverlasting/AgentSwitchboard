#!/usr/bin/env python3
import argparse, json, subprocess, sys, time
from pathlib import Path


def command(provider, query, repo, limit, index_dir):
    if provider == "github-api-code-search":
        if not repo: raise ValueError("--repo is required for GitHub search")
        return ["gh","search","code",query,"--repo",repo,"--limit",str(limit),"--json","path,repository,sha,textMatches,url"]
    if provider == "sourcegraph":
        return ["src","search","-json","--stream","--",query]
    if provider == "zoekt-local":
        if not index_dir: raise ValueError("--index-dir is required for Zoekt")
        return ["zoekt","-index_dir",index_dir,query]
    raise ValueError(f"unsupported provider: {provider}")


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--provider", required=True, choices=["github-api-code-search","zoekt-local","sourcegraph"])
    p.add_argument("--query", required=True)
    p.add_argument("--repo")
    p.add_argument("--limit", type=int, default=30)
    p.add_argument("--index-dir")
    p.add_argument("--timeout", type=int, default=30)
    p.add_argument("--output")
    p.add_argument("--dry-run", action="store_true")
    a=p.parse_args()
    if a.limit < 1 or a.limit > 200: p.error("--limit must be 1..200")
    cmd=command(a.provider,a.query,a.repo,a.limit,a.index_dir)
    if a.dry_run:
        print(json.dumps({"provider":a.provider,"argv":cmd},indent=2)); return 0
    started=time.monotonic()
    try:
        cp=subprocess.run(cmd,capture_output=True,text=True,timeout=a.timeout,check=False)
        timed_out=False
    except FileNotFoundError as e:
        payload={"provider":a.provider,"status":"query-failed","exitCode":127,"durationMs":round((time.monotonic()-started)*1000),"stderr":str(e),"stdout":"","proofCeiling":"provider executable launch failed"}
        cp=None; timed_out=False
    except subprocess.TimeoutExpired as e:
        payload={"provider":a.provider,"status":"query-failed","exitCode":124,"durationMs":round((time.monotonic()-started)*1000),"stderr":str(e),"stdout":"","proofCeiling":"bounded query timed out"}
        cp=None; timed_out=True
    if cp is not None:
        payload={"provider":a.provider,"status":"query-succeeded" if cp.returncode==0 else "query-failed","exitCode":cp.returncode,"durationMs":round((time.monotonic()-started)*1000),"stdout":cp.stdout,"stderr":cp.stderr,"proofCeiling":"one bounded query execution only; not index completeness or freshness proof"}
    if a.output:
        Path(a.output).write_text(json.dumps(payload,indent=2)+"\n",encoding="utf-8")
    sys.stdout.write(payload["stdout"])
    if payload["stderr"]: sys.stderr.write(payload["stderr"])
    return 0 if payload["status"]=="query-succeeded" else payload["exitCode"] or 1

if __name__=="__main__": raise SystemExit(main())
