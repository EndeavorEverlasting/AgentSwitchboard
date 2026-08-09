---
id: wayfinder-runtime-binding
version: 1.0.0
status: canonical
---

# Wayfinder Runtime Binding

## Trigger

Use before any Wayfinder validation that crosses Python and PowerShell, uses an isolated virtual environment, or reports that a Python dependency exists in one command but is missing inside a nested validator.

## Inputs

- repository root;
- the exact Python interpreter that installed validation dependencies when known;
- Wayfinder requirements file;
- focused validator set;
- broader validation floor.

## Procedure

1. Prefer an explicit `-PythonPath` from the caller that created/installed the validation environment.
2. Otherwise use `ASB_WAYFINDER_PYTHON`, then active `VIRTUAL_ENV`, then repository `.venv`, then PATH.
3. Canonicalize through `sys.executable`; Windows short-path/junction/redirect string changes are informational if execution succeeds.
4. Print binding source, canonical interpreter path, and Python version before dependency validation.
5. Check/install dependencies with that same interpreter only.
6. Pass the same `-PythonPath` into nested Wayfinder PowerShell validators.
7. Run focused validators before public-plan/documentation/operational aggregate checks.
8. Record the exact head, interpreter binding, validator outcomes, proof ceiling, and unresolved live gate in the operator report/handoff.

## Outputs

- deterministic Python interpreter binding;
- runtime-binding validator evidence;
- focused and broader validator results;
- operator-readable report/handoff.

## Deterministic validation

Run:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-WayfinderPythonBinding.ps1 -PythonPath <bound-python>
<bound-python> tests/test_wayfinder_runtime_binding_contract.py
pwsh -NoLogo -NoProfile -File scripts/Test-WayfinderHarnessCompleteness.ps1 -PythonPath <bound-python>
```

## Forbidden scope

- installing dependencies into a different Python than nested validators execute;
- silently falling back when an explicit interpreter override is invalid;
- treating path spelling/case/short-name normalization alone as proof of interpreter mismatch;
- modifying product code, governance contracts, secrets, or live tracker state;
- promoting validator success to live tracker/HITL proof.

## Stop and escalate

Stop if the explicit interpreter cannot execute, its dependency floor cannot be satisfied, an owning validator fails, the repository head changes during exact-head proof, or the next gate requires credentials/live tracker/HITL authority outside harness scope.
