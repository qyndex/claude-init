# T-320 — verification-only parent characterization

This parent task verifies existing committed behavior. It introduces no runtime,
workflow or test behavior and does not manufacture a RED. The repository's
check-tdd-ledger.sh explicitly supports green-only characterization via a marker
file; `characterization` records why it applies here. The actual parent acceptance
command is run once into green.log. The generic tdd-ledger writer warns about
the deliberately absent RED; the dedicated check-tdd-ledger checker recognizes
this supported marker, and its actual result is retained separately. Its source anchor is c1720b983c4daae8b858137f4d2203cfac30a5b1.

Implementation and genuine fail-first evidence already reside in:

- T322, d876583a0086b4c446fac01fb5519d6fa4e2c4ab: bounded protected source/run/job/log observer.
- T323, 1b0b13044a4e0671dccce39f0e53a8fc52ca5872: protected isolated journal and real Git publication proof.
- T324, c1720b983c4daae8b858137f4d2203cfac30a5b1: explicit live CLI composition and offline/live separation.

Acceptance is `bash .claude/scripts/test/factory-reporting-queue-live-evidence.sh`
without --live. It exercises eleven actual CLI cases using a local fake-gh
transport, 35 source-observer and twelve real Git journal contracts. Permission
for process inspection enables the existing bounded child-cleanup guard; these
fixtures make no network calls. There is no new failing test to report because
this task characterizes those already implemented contracts.

Success establishes local checker readiness only. Explicit --live with complete
actual selectors remains mandatory for T318. No live evidence is obtained or
stored by this parent run, and no rollout, source push, token, protection or
workflow setting is changed. Administrative correlation is not native attestation
or independent local Slack verification. T321/T317 aggregate documentation and
T318 actual reviewed rollout remain pending. The parent's uncommitted plan
clarification remains untouched and excluded from this commit.
