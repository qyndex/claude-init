## Evidence Bundle — Spec 014 (014-authenticated-receipt-recovery)
Spec: `specs/active/014-authenticated-receipt-recovery.md` · Commit: `3d06a87`

### Acceptance criteria (4/4 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-10T03:11:41+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-10-014-authenticated-receipt-recovery/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-10-014-authenticated-receipt-recovery/traces/`; full HAR at `verify/2026-10-10-014-authenticated-receipt-recovery/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**
