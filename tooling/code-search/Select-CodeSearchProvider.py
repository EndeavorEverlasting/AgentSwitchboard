#!/usr/bin/env python3
import argparse, json
from pathlib import Path


def select(c):
    if c.get("repositoryHostedOnGitHub") and c.get("ghAvailable") and c.get("ghAuthenticated") and c.get("githubProbeSucceeded"):
        return {"status":"ready","provider":"github-api-code-search","reason":"GitHub-hosted repository and bounded gh search probe succeeded"}
    if c.get("localIndexingAllowed") and c.get("zoektAvailable") and c.get("zoektIndexPresent"):
        return {"status":"ready","provider":"zoekt-local","reason":"GitHub path unavailable; existing local Zoekt index is explicitly allowed and present"}
    if c.get("sourcegraphExplicitOptIn") and c.get("srcAvailable") and c.get("srcAuthenticated") and c.get("sourcegraphPlanVerified"):
        return {"status":"ready","provider":"sourcegraph","reason":"Sourcegraph use is explicit and endpoint/auth/plan gates are proven"}
    missing=[]
    if c.get("repositoryHostedOnGitHub") and not c.get("githubProbeSucceeded"):
        missing.append("successful bounded GitHub code-search probe")
    if c.get("localIndexingAllowed") and not (c.get("zoektAvailable") and c.get("zoektIndexPresent")):
        missing.append("installed Zoekt plus existing local index")
    if c.get("sourcegraphExplicitOptIn") and not (c.get("srcAvailable") and c.get("srcAuthenticated") and c.get("sourcegraphPlanVerified")):
        missing.append("Sourcegraph executable/auth/current-plan proof")
    if not missing:
        missing.append("an explicitly allowed provider whose readiness gate passes")
    return {"status":"blocked","provider":None,"reason":"; ".join(missing)}


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--capabilities", required=True)
    p.add_argument("--output")
    a=p.parse_args()
    payload=select(json.loads(Path(a.capabilities).read_text(encoding="utf-8")))
    text=json.dumps(payload, indent=2)
    if a.output:
        Path(a.output).write_text(text+"\n", encoding="utf-8")
    print(text)
    return 0 if payload["status"]=="ready" else 2

if __name__=="__main__": raise SystemExit(main())
