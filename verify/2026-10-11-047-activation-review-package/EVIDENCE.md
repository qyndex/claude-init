## Evidence Bundle — Spec 047 (047-activation-review-package)
Spec: `specs/active/047-activation-review-package.md` · Commit: `4cbb033`

### Acceptance criteria (4/4 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-11T20:13:46+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-11-047-activation-review-package/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-11-047-activation-review-package/traces/`; full HAR at `verify/2026-10-11-047-activation-review-package/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**

## Artifact index
- verify/2026-10-11-047-activation-review-package/evidence.json
- verify/2026-10-11-047-activation-review-package/pr-body.md
- verify/2026-10-11-047-activation-review-package/acceptance.log
- verify/2026-10-11-047-activation-review-package/EVIDENCE.md
- verify/2026-10-11-047-activation-review-package/future-state.log
- verify/2026-10-11-047-activation-review-package/results.json
- verify/2026-10-11-047-activation-review-package/smoke.log
