M-00 — CI test runner + dead-test detector
date: 2026-07-23

RED (main): validate.sh [dead-tests] flags 13 of 15 test/*.sh as unreferenced.
GREEN (with staged patch M-00-harness-test-runner.patch applied):
  validate.sh -> '✓ test/*.sh covered by a directory-glob CI runner'

Enforcement half (validate.sh [dead-tests] block): committed on branch.
Runner half (harness-validate.yml step): STAGED as operator-install patch
  (.github/workflows is constitution-guarded; O-2 stage-then-install honored).

Test triage (see triage.txt): 14/15 pass; security-invariants.sh has 2
pre-existing OUT-OF-SCOPE failures (INVARIANT-04 sandbox, INVARIANT-07).
