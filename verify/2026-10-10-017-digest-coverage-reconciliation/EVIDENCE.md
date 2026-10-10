## Evidence Bundle — Spec 017 (017-digest-coverage-reconciliation)
Spec: `specs/active/017-digest-coverage-reconciliation.md` · Commit: `df60781`

### Acceptance criteria (4/4 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-10T11:50:55+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-10-017-digest-coverage-reconciliation/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-10-017-digest-coverage-reconciliation/traces/`; full HAR at `verify/2026-10-10-017-digest-coverage-reconciliation/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**

## Artifact index
- verify/2026-10-10-017-digest-coverage-reconciliation/evidence.json
- verify/2026-10-10-017-digest-coverage-reconciliation/pr-body.md
- verify/2026-10-10-017-digest-coverage-reconciliation/EVIDENCE.md
- verify/2026-10-10-017-digest-coverage-reconciliation/results.json
- verify/2026-10-10-017-digest-coverage-reconciliation/smoke.log
- verify/2026-10-10-017-digest-coverage-reconciliation/AC-4.txt
- verify/2026-10-10-017-digest-coverage-reconciliation/command-observations.json
- verify/2026-10-10-017-digest-coverage-reconciliation/AC-1.txt
- verify/2026-10-10-017-digest-coverage-reconciliation/AC-3.txt
- verify/2026-10-10-017-digest-coverage-reconciliation/AC-2.txt
