# T330 — reporting-only administrative policy observations

The first feature RED followed a passing existing real-Git full-metadata bootstrap,
then rejected the explicit schema-2 bootstrap (`archive bootstrap schema differs`).
`fixture-import-error.log` preserves an earlier incorrect fixture import; it is
not feature RED. `implementation-check.log` preserves the first implementation's
clock-call error. Subsequent checks and the canonical GREEN pass 86 focused cases.

Schema 1 retains its exact raw-policy hash contract. Schema 2 explicitly selects
stable semantic hashes and the separately protected fixed sibling
`receipt-policy-observations.json`. The reporting-only capture requires actual
visible exact App update actors and empty deletion/rewrite actors. Missing actors
require complete settled, repository/branch/writer/ruleset-bound observations;
visible bad actors always reject. The neutral empty-actor merge helper is unchanged.
The actual disposable Git test verifies protected bootstrap/current rereads and
preserves encrypted worker bytes without state writes. Capture tests use only
fixed GET endpoints, with bounded JSON/frontier/cycle/document negatives.

Legacy regressions: 60 neutral observation cases and 15 real-Git bootstrap cases
pass. Compile and ShellCheck pass. The early parent review is static only and its
helper hash predates the clock-call correction; it is not independent native proof.

This is local source preparation. No live operator observation, App installation
or private API capability, ruleset cutover, credential changes, or archive activation
is claimed. Protected workflow ingress/routing and complete runtime closures remain
later T331–T335 integration work. T333's new helper path was unioned under the task
lock for separately assigned source preparation; T333 remains pending.
