## Evidence Bundle — Spec 010 (010-protected-proof-producers)
Spec: `specs/active/010-protected-proof-producers.md` · Commit: `10f8049`

### Acceptance criteria (4/4 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-16T09:18:45+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-16-010-protected-proof-producers/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-16-010-protected-proof-producers/traces/`; full HAR at `verify/2026-10-16-010-protected-proof-producers/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**

## Artifact index
- verify/2026-10-16-010-protected-proof-producers/evidence.json
- verify/2026-10-16-010-protected-proof-producers/workflow-boundary.log
- verify/2026-10-16-010-protected-proof-producers/pr-body.md
- verify/2026-10-16-010-protected-proof-producers/EVIDENCE.md
- verify/2026-10-16-010-protected-proof-producers/results.json
- verify/2026-10-16-010-protected-proof-producers/smoke.log
- verify/2026-10-16-010-protected-proof-producers/bounded-review-runtime.log
- verify/2026-10-16-010-protected-proof-producers/signed-provenance.log
- verify/2026-10-16-010-protected-proof-producers/producer-contracts.log
- verify/2026-10-16-010-protected-proof-producers/coordinator-contracts.log

## Proof boundary

Five shell suites ran freshly before collector --check-only consumed their new AC-tagged results and reran actual verify.sh smoke. Results bind source10f8049 after commit-message formatting and ADR YAML corrections; later commits only refresh the decision index and package evidence. No historical PASS was reused. AC-2 locally proves sandbox argv/output contracts through injected runners; native Docker remains CI. Certificate-positive policy fixtures inject verified results; the unrelated official signed fixture/tampered-subject pair proves actual CLI compatibility only. No live factory signing, hosted verdict or shadow eligibility is claimed. Protected runtime policy pins remain unchanged until the reviewed merged source is recorded.
