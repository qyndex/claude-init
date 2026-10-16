# T317 — committed-source local readiness

The current bundle is verify/2026-10-16-029-github-reporting-alerts, bound to
committed repaired source d95c4339226e8789adf9ccf913160a305f20d86f. Its actual
aggregate ran once at that SHA, exit0,36.045 seconds; acceptance-run.json retains
source, command, timestamps and aggregate SHA256. Queue contracts include
60 journal,20 real Git CAS,33 observer,39 delivery,64 Actions/config,11 CLI,
41 source/log and12 real Git journal cases, plus the reporting/workflow
regressions. Smoke exit0 and actual AC-tagged local contributions were collected
at the same source. A second independent claude-sonnet-5-5 review passed with
zero findings; safe review inputs, execution and verdict are retained.

The collector's eight AC tags measure local contract contributions only. They do
not establish full Spec029 acceptance: READINESS.json explicitly records
full_spec_acceptance_complete:false, live_activation_verified:false and
full_AC8_pending:true. Local source readiness is verified; merge readiness is
false pending exact-head hosted checks and reviewed operator cutover. T318
remains pending. No live queue execution or settings changes occur in this task.
The official checkout-pin observation is administrative, not native attestation.

The first ceae9f5 aggregate/collector attempt is preserved under
attempt-1-ceae9f5. Its subsequent independent review requested changes after the
actual Actions [command] log-format defect was reproduced. T325 contains the
actual RED, minimal repair and GREEN. Historical collector files are named
historical-evidence.json/HISTORICAL-EVIDENCE.md/historical-pr-body.md to prevent
selection as a second current candidate; their contents remain preserved. No
first-attempt local PASS is represented as source ready for merge.

This parent task characterizes existing implementation; no runtime/test behavior
was introduced and no manufactured RED is claimed. The supported characterization
marker permits truthful green-only verification. T312–T325 retain original child
fail-first evidence. The generic tdd-ledger writer warning about absent parent
RED is superseded by the actual characterization-aware ledger validator.

Task317 completion means local readiness and rollout-evidence preparation only.
The final metadata commit does not modify the reviewed runtime source. No push,
credential, environment, authority flag, branch policy or Slack operation occurs.
