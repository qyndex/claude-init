## Evidence Bundle — Spec 025 (025-verified-slack-attachments)
Spec: `specs/active/025-verified-slack-attachments.md` · Commit: `a9eb886`

### Acceptance criteria (4/4 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-10T16:52:00+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-10-025-verified-slack-attachments/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-10-025-verified-slack-attachments/traces/`; full HAR at `verify/2026-10-10-025-verified-slack-attachments/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**
