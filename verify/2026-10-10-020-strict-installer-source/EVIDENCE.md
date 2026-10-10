## Evidence Bundle — Spec 020 (020-strict-installer-source)
Spec: `specs/active/020-strict-installer-source.md` · Commit: `ad4446a`

### Acceptance criteria (4/4 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-10T12:17:17+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-10-020-strict-installer-source/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-10-020-strict-installer-source/traces/`; full HAR at `verify/2026-10-10-020-strict-installer-source/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**

## Artifact index
- verify/2026-10-10-020-strict-installer-source/evidence.json
- verify/2026-10-10-020-strict-installer-source/pr-body.md
- verify/2026-10-10-020-strict-installer-source/EVIDENCE.md
- verify/2026-10-10-020-strict-installer-source/results.json
- verify/2026-10-10-020-strict-installer-source/smoke.log
- verify/2026-10-10-020-strict-installer-source/AC-4.txt
- verify/2026-10-10-020-strict-installer-source/command-observations.json
- verify/2026-10-10-020-strict-installer-source/AC-1.txt
- verify/2026-10-10-020-strict-installer-source/AC-3.txt
- verify/2026-10-10-020-strict-installer-source/AC-2.txt
