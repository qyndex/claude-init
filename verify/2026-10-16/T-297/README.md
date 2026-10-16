# T-297 — protected observation ingress and separate audit

Initial RED/GREEN (preserved as initial-red.log/initial-green.log) ran the unchanged task acceptance command: coordinator plus
workflow-baseline suites. RED rejects the unsupported observations keyword before
integration; initial GREEN exercises hidden exact administrative approval and all
existing63 coordinator cases. Additional cases reject missing/foreign/id/hash/
future observations, malformed/nonempty visible actors, changed live metadata on
final recheck, duplicate/unknown/foreign/oversize protected-file envelopes.
The actual CLI path produces separate bounded administrative audit and receipt
files, without adding observations to the existing receipt schema.

The workflow-baseline suite executes the shipped protected ingress shell with
real temporary files and asserts no raw sentinel echo. Its original strict
preparation rejection was superseded by the failure-invalidation review below.
The coordinator file-loader and T296 decoder exercise the262144byte application
bound. The suite checks default-branch/main-only environment routing, unchanged
Administration read and a separate audit artifact path. Existing four workflow
baseline acceptance cases and full actionlint/ShellCheck pass.

Additional actual regressions: observation60, workflows8, producers36 passed.
Python coordinator compile passed. Structural check passed with4 existing warnings;
TDD ledger passed with0failures/0warnings and70 pre-enforcement legacy incomplete.
No hosted proof, live observation/configuration, permission, flags or rules changed.
The helper-dependent producer pins remain intentionally incomplete until T298;
this local intermediate commit is not publishable activation readiness.

## Review follow-up — failure invalidation

The review found malformed input loaded outside the eligibility failure handler.
Canonical red.log now captures the actual regression: a preexisting same-head
success was not replaced on invalid input. Canonical green.log follows the fix
using the same task command. Duplicate JSON, an oversized file and unknown JSON
with a sentinel now enter the existing merge-mode failure handler, which posts
failed factory-eligibility for the exact head and leaves no successful receipt.
Shadow retains its established GET-only semantics; conditional merge revalidates
input and cannot authorize effects from a stale successful check.

Workflow preparation only writes a capped raw file; semantic validation is
intentionally deferred to the coordinator so it cannot bypass invalidation.
The updated actual ingress fixture confirms malformed/foreign/duplicate/unknown
inputs reach that path without raw echo. The previous environment-size scenario
was superseded: the actual oversized file regression proves application-bound
failure invalidation without relying on operating-system environment limits.
T297 remains complete locally; T298 and aggregate T292 remain pending.
