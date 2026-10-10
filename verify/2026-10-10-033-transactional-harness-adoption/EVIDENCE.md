## Evidence Bundle — Spec 033 (033-transactional-harness-adoption)
Spec: `specs/active/033-transactional-harness-adoption.md` · Commit: `11757e0`

### Acceptance criteria (4/4 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-10T18:41:34+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-10-033-transactional-harness-adoption/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-10-033-transactional-harness-adoption/traces/`; full HAR at `verify/2026-10-10-033-transactional-harness-adoption/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**

## Artifact index
- verify/2026-10-10-033-transactional-harness-adoption/evidence.json
- verify/2026-10-10-033-transactional-harness-adoption/pr-body.md
- verify/2026-10-10-033-transactional-harness-adoption/acceptance.log
- verify/2026-10-10-033-transactional-harness-adoption/EVIDENCE.md
- verify/2026-10-10-033-transactional-harness-adoption/results.json
- verify/2026-10-10-033-transactional-harness-adoption/smoke.log
