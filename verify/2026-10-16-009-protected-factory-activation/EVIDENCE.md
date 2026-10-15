## Evidence Bundle — Spec 009 (009-protected-factory-activation)
Spec: `specs/active/009-protected-factory-activation.md` · Commit: `61964c1`

### Acceptance criteria (5/5 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |
| AC-4 | tagged test | ✓ PASS |
| AC-5 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-16T09:37:49+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-16-009-protected-factory-activation/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-16-009-protected-factory-activation/traces/`; full HAR at `verify/2026-10-16-009-protected-factory-activation/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**

## Artifact index
- verify/2026-10-16-009-protected-factory-activation/evidence.json
- verify/2026-10-16-009-protected-factory-activation/workflow-boundary.log
- verify/2026-10-16-009-protected-factory-activation/activation-package.log
- verify/2026-10-16-009-protected-factory-activation/pr-body.md
- verify/2026-10-16-009-protected-factory-activation/EVIDENCE.md
- verify/2026-10-16-009-protected-factory-activation/results.json
- verify/2026-10-16-009-protected-factory-activation/smoke.log
- verify/2026-10-16-009-protected-factory-activation/producers.log
- verify/2026-10-16-009-protected-factory-activation/activation-planning.log
- verify/2026-10-16-009-protected-factory-activation/signed-provenance.log
- verify/2026-10-16-009-protected-factory-activation/coordinator.log
- verify/2026-10-16-009-protected-factory-activation/request-only-shipping.log

## Proof boundary

Seven shell suites ran freshly before the collector consumed their new AC-tagged results in `--check-only` mode and reran actual `verify.sh` smoke against base bc678f611e7c2e05b1eb427e805654644c84dd67. This shell-only collector has no configured native shell journey runner; no historical result was reused. Source61964c1 contains the reviewed pin-only preparation; subsequent commits package evidence.

These are local implementation/metadata contracts, including injected coordinator merge fixtures. They are not genuine signed factory producer artifacts, App authentication, active twelve-check protection, shadow eligibility or delivery. Key-presence metadata declarations are not key validation. T-180 remains blocked and T-222 pending. Producer switches, authority switch, live rules, pilot branch, receipt trusted revisions and merge mode are unchanged.
