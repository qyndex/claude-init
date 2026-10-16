## Evidence Bundle — Spec 014 (014-authenticated-receipt-recovery)
Spec: `specs/active/014-authenticated-receipt-recovery.md` · Commit: `b2fe148`

### Acceptance criteria (8/8 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |
| AC-5 | tagged test | ✓ PASS |
| AC-6 | tagged test | ✓ PASS |
| AC-7 | tagged test | ✓ PASS |
| AC-8 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-17T05:00:46+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: FAIL (1 check(s) failed)
exit: 1
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-17-014-authenticated-receipt-recovery/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-17-014-authenticated-receipt-recovery/traces/`; full HAR at `verify/2026-10-17-014-authenticated-receipt-recovery/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **FAIL**

## Artifact index
- verify/2026-10-17-014-authenticated-receipt-recovery/evidence.json
- verify/2026-10-17-014-authenticated-receipt-recovery/binding.json
- verify/2026-10-17-014-authenticated-receipt-recovery/pr-body.md
- verify/2026-10-17-014-authenticated-receipt-recovery/EVIDENCE.md
- verify/2026-10-17-014-authenticated-receipt-recovery/results.json
- verify/2026-10-17-014-authenticated-receipt-recovery/smoke.log
