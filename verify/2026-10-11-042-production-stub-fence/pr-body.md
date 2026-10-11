## Evidence Bundle — Spec 042 (042-production-stub-fence)
Spec: `specs/active/042-production-stub-fence.md` · Commit: `e612a8f`

### Acceptance criteria (3/3 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-11T14:50:30+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-11-042-production-stub-fence/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-11-042-production-stub-fence/traces/`; full HAR at `verify/2026-10-11-042-production-stub-fence/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**
