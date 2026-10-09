## Evidence Bundle — Spec 006 (006-trustworthy-candidate-verification)
Spec: `specs/active/006-trustworthy-candidate-verification.md` · Commit: `633faee`

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
# Smoke test — 2026-10-09T18:29:29+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-09-006-trustworthy-candidate-verification/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-09-006-trustworthy-candidate-verification/traces/`; full HAR at `verify/2026-10-09-006-trustworthy-candidate-verification/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**
