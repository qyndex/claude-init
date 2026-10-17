# Hosted integration boundary — T334 remains pending

The public `factory-git-state.run` regression uses actual local Git objects, protected origin, source partitions, checkpoint/stages, fixed fresh receipt-only SQLite reconstruction, typed report transfer, and a synthetic Slack transport. It is offline proof, not an actual hosted run or live activation.

Incremental actual failures are retained:

- `hosted-maintenance-red.log`: report initialization ran before durable maintenance, blocking at missing checkpoint.
- `hosted-maintenance-ready-red.log`: maintenance legitimately advanced the ref, making the original report bootstrap SHA stale.
- `hosted-maintenance-projection-red.log`: ready mode fell back to legacy successful-artifact discovery.
- `hosted-maintenance-scoped-forwarding-red.log`: the typed helper lacked the required scoped validator forwarding.
- `hosted-report-canonical-path-red.log`: macOS temporary directory alias spelling failed the canonical report path boundary.
- `hosted-pending-order-red.log`: an actual uncertain report attempted new source maintenance before receipt reconciliation.
- `hosted-alert-view-red.log`: alerts' second GitState omitted the protected archive view and rejected the approved writer policy through its legacy path.

The pending-future fixture error is retained separately; it was not a production defect. The final `hosted-integration-green.log` is terminal exit 0, owner session55065. It proves first report initialization only when the path was absent at reviewed bootstrap and throughout actual protected path history; maintenance publication precedes a fresh report snapshot; actual scoped reconstruction and coverage precede delivery; existing uncertain immutable batches reconcile without resend before maintenance; quiet alerts use the protected view; scope flags are strict booleans; deleted historical reports cannot reset. No caller SQLite, completion flag or cursor becomes proof.

The maintenance helper has its own earlier two-day, fresh-process, late/rerun/CAS proof. Its subsequent independent review fixes are being prepared separately. Large-history shared-budget composition and final consumer/config closure remain pending; this document does not extend the earlier 1001-record acceptance to an untested hosted composition.

Affected combined regressions also terminated successfully: reviewed typed transfer (11 behavioral groups, session37919), corrected legacy protected discovery (11 scenarios with 121 actual origin continuations, session15427), legacy hosted digest, and legacy alerts. Compile, shell syntax and warning-level ShellCheck passed on the changed source/test. These do not prove the unresolved large-history shared composition budget.
