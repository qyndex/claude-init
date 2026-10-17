# T285 — cold-watch reruns and authenticated outcomes

Local approved Spec014 AC7/8 continuation on receipt source `9677d8ee24352b12c187e4e996b00ad45b58d2c3`, with protected main6606 already merged. No live state, flags, credentials, App permissions or protection model changed. Analyze014 remains PASS.

The strict original RED records missing reconciliation; final GREEN runs 20 scenarios with actual disposable Git objects/atomic commits and fixture Actions metadata. The same old failed run ID is revisited, its new attempt is retained and an actual authenticated fixture delivery is appended. Once retained, expired/unavailable source artifacts are not fetched again. Round-robin segment/row cursors retain old failed/skipped/running runs without a creation-time watermark; finite frozen-prefix overlap catches a newly visible older ID. Source metadata/attempt/source SHA remains immutable per watched identity. Coverage is always explicitly false.

`authenticate_source` checks actual emitter event/path/workflow/default branch/source HEAD and complete approved source policy/runtime, with explicit profile or reviewed legacy mode. Non-delivery requires either that exact source policy disables merging or a successful exact-source, origin/digest-verified `merged:false` receipt. Cache entries retain bounded original policy/runtime bytes and, for shadow receipts, the original ZIP/artifact metadata; every cache read revalidates them under the current canonical trust/mode epoch. Failed merge-capable attempts remain watchable. Revoked/removed profiles never fall back, while later explicit reapproval changes epoch and revisits prior unapproved observations. Cached terminal non-delivery still checks latest attempt metadata.

Retained identity/discovery/segment/record/material lookup occurs before source artifacts. Already authenticated delivery facts survive revocation with withdrawn annotation, not runtime completion. Unavailable source observations never create proof. Transport parity has its own actual RED (`metadata-unavailable-red.txt`): the real CLI adapter raises `ValueError('GitHub API request failed: ...')`, rather than the fixture's generic RuntimeError. Only that exact transport failure preserves known retained/cached facts; malformed identity/schema/budget failures still reject. No task/SQLite lifecycle API is used.

The copied-bootstrap negative (`copied-bootstrap-red.txt`) exposed a real origin gap. Pre-bootstrap discovery/index/segment/record/material and cached outcome capsules now reject absent an explicit reviewed import protocol. Actual fixture cases exercise whole copied archive, original record-only/material-only aliases, report-only reconstruction and copied source/receipt capsules. Hashes/JSON alone are not origin. Existing report and encrypted-feedback bytes stay intact through actual archive/progress/outcome commits.

Actual checks:

- `bash .claude/scripts/test/factory-receipt-reruns.sh`: 20 scenarios PASS (`green.log`).
- Profiles33, immutable source24, equivalence9, revocation18, reporting projection4 AC groups, archive31, retained proof20, segmented discovery11, state paths35, coordinator63: all PASS (`regressions.txt`).
- Python compile PASS for all four source modules, with a temporary cache.
- Structural validation PASS with four existing warnings (`structural-results.txt`).
- Whole-repository ledger PASS: zero failures, zero enforced warnings; 70 pre-T111 legacy-incomplete entries not enforced (`whole-ledger-results.txt`).

Limits: reconciliation visits at most 16 rows in one segment, and discovery observes at most two bounded source pages per CAS observation; new rows split into 128-row segments. Max-three observations share 4,096 checked API calls/32MiB. Positive archive appends may survive an invocation work limit; the next invocation resumes index-first. No compact record is pruned. Known schema1/2 checkpoints migrate to schema3 only after protected origin, without discarding watch identities.

T286 still must prove capped-query partition completeness and integrate resumable verified ancestry/projection windows, including fresh-hosted SQLite continuation; the current256-commit/128-projection invocation limits are not unattended capacity. GitHub App read-only omission of protection bypass metadata remains a live activation blocker; this task keeps the old full-metadata fail-closed contract and does not implement the separately proposed approval model. No independent/live factory receipt is claimed by fixture proof.
