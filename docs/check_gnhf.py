import json
with open('reference.json') as f:
    ref = json.load(f)
for i, w in enumerate(ref.get('gnhfWorkflow', [])):
    pid = w.get('prompt', '')
    valid = pid.startswith('P') and len(pid) <= 4
    uc = w.get('useCase', '')[:60]
    print(f'{i}: prompt={pid!r:45s} valid={valid}  useCase={uc}')
