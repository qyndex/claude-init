## Evidence Bundle — Spec 036 (036-worker-environment-boundary)
Spec: `specs/active/036-worker-environment-boundary.md` · Commit: `e1c468f`

### Acceptance criteria (4/4 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-11T12:18:06+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-11-036-worker-environment-boundary/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-11-036-worker-environment-boundary/traces/`; full HAR at `verify/2026-10-11-036-worker-environment-boundary/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**
