#!/usr/bin/env python3
import argparse, json, os, shutil, tempfile, uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
REG=ROOT/'tooling/code-search/harness/provider-registry.json'


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--no-write', action='store_true')
    p.add_argument('--json', action='store_true')
    p.add_argument('--output-root')
    a=p.parse_args()
    reg=json.loads(REG.read_text(encoding='utf-8'))
    payload={
      'schema':'agentswitchboard.code-search-readiness.v1',
      'runId':uuid.uuid4().hex,
      'ghAvailable':shutil.which('gh') is not None,
      'srcAvailable':shutil.which('src') is not None,
      'zoektAvailable':shutil.which('zoekt') is not None,
      'zoektGitIndexAvailable':shutil.which('zoekt-git-index') is not None,
      'sourcegraphEndpointConfigured':bool(os.environ.get('SRC_ENDPOINT')),
      'sourcegraphTokenObserved':bool(os.environ.get('SRC_ACCESS_TOKEN')),
      'providerCount':len(reg['providers']),
      'working':['tracked provider registry','deterministic selector','bounded query command builder','local untracked evidence policy'],
      'missing':['live provider authentication/readiness probe','observed query execution for this workstation'],
      'proofCeiling':'Executable presence and repository contract readiness only; authentication, index freshness, and query success remain unproved.'
    }
    report=("# Code Search Harness Status\n\n"
            f"- gh executable: {'present' if payload['ghAvailable'] else 'missing'}\n"
            f"- src executable: {'present' if payload['srcAvailable'] else 'missing'}\n"
            f"- zoekt executable: {'present' if payload['zoektAvailable'] else 'missing'}\n"
            f"- zoekt-git-index: {'present' if payload['zoektGitIndexAvailable'] else 'missing'}\n"
            f"- Sourcegraph endpoint configured: {payload['sourcegraphEndpointConfigured']}\n"
            "- Sourcegraph token value: never printed\n\n"
            "## Working\n" + ''.join(f"- {x}\n" for x in payload['working']) + "\n## Missing / unproved\n" + ''.join(f"- {x}\n" for x in payload['missing']) + f"\n## Proof ceiling\n{payload['proofCeiling']}\n")
    if not a.no_write:
        out=Path(a.output_root) if a.output_root else Path(tempfile.gettempdir())/'AgentSwitchboard'/'code-search'/payload['runId']
        out.mkdir(parents=True, exist_ok=True)
        (out/'code-search-readiness.json').write_text(json.dumps(payload,indent=2)+'\n',encoding='utf-8')
        (out/'code-search-operator-report.md').write_text(report,encoding='utf-8')
        payload['outputRoot']=str(out)
    print(json.dumps(payload,indent=2) if a.json else report)
    return 0

if __name__=='__main__': raise SystemExit(main())
