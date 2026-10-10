## Evidence Bundle — Spec 022 (022-reporting-policy-approval)
Spec: `specs/active/022-reporting-policy-approval.md` · Commit: `f457c53`

### Acceptance criteria (4/4 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-10T13:40:31+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-10-022-reporting-policy-approval/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-10-022-reporting-policy-approval/traces/`; full HAR at `verify/2026-10-10-022-reporting-policy-approval/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**
