## Evidence Bundle — Spec 009 (009-protected-factory-activation)
Spec: `specs/active/009-protected-factory-activation.md` · Commit: `b2fe148`

### Acceptance criteria (5/5 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |
| AC-5 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-17T04:59:39+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: FAIL (1 check(s) failed)
exit: 1
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-17-009-protected-factory-activation/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-17-009-protected-factory-activation/traces/`; full HAR at `verify/2026-10-17-009-protected-factory-activation/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **FAIL**

## Artifact index
- verify/2026-10-17-009-protected-factory-activation/evidence.json
- verify/2026-10-17-009-protected-factory-activation/authority-flag.json
- verify/2026-10-17-009-protected-factory-activation/stderr.log
- verify/2026-10-17-009-protected-factory-activation/result.json
- verify/2026-10-17-009-protected-factory-activation/pr-body.md
- verify/2026-10-17-009-protected-factory-activation/input.json
- verify/2026-10-17-009-protected-factory-activation/EVIDENCE.md
- verify/2026-10-17-009-protected-factory-activation/results.json
- verify/2026-10-17-009-protected-factory-activation/smoke.log
- verify/2026-10-17-009-protected-factory-activation/stdout.log
- verify/2026-10-17-009-protected-factory-activation/bootstrap-pr50.json
- verify/2026-10-17-009-protected-factory-activation/AC-4.json
