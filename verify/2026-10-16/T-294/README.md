# T-294 — bounded partitioned source backfill

Actual first RED demands the missing protected backfill operation. GREEN runs the
same command against the new implementation. Supplemental source-branch-red.txt
captures the actual unbound default-branch query failure before adding the branch
selector and immutable campaign source-branch binding. Final source/test digests
and base9f0ad1b are in inputs.json. No artificial production rollback forced RED.

The acceptance deliberately separates two kinds of proof. Its full1100-run time
partition algorithm uses an in-memory validated-state fixture; it reaches every
unique identity despite overlapping boundaries and the filtered1000cap. A later
epoch finds a late old-created ID and new attempt while the old attempt is retained.
This algorithm fixture is NOT protected origin or hosted capacity proof. Separate
real disposable Git tests exercise the actual atomic checkpoint writer, CAS race,
lost acknowledgement, fresh Python process restart, fixed campaign rejection,
boundary pending-index dedup and unchanged encrypted feedback bytes. They do not
claim all1100objects were persisted through the still-bounded full bootstrap gate.

Counts>=1000 split time ranges; even exactly1000 in a single-second bucket is a
persisted gap revisited next epoch. Page/count/unique identity and first-page
confirmation are required before calling a partition observed. Count drift,
short/repeated/duplicate pages, changed confirmation, network or denied reads are
gaps. Foreign/out-of-range/boolean metadata and observation-budget failures block
without advancing. Corrupt retained page digests/schema and copied pre-bootstrap
manifests reject. Raw transport error sentinels never enter persisted objects.
Known pending rows remain pending; no receipt/provenance object or runtime credit
is produced. All complete/coverage flags remain false.

A constant64-entry DFS frontier and strict sharded partition objects retain bounded
page facts. The existing journal keeps run/attempt watches in immutable segmented
paths; partition observations and watch/frontier progress publish together under
the existing protected bootstrap, base_tree and nonforceCAS (three observations).
No caller JSON/cursor is origin proof. The pure backfill_page helper returns data
only; its caller must authenticate protected blob origin before publishing.

Actual regressions: discovery11, reruns20, state-paths35, CAS11, bootstrap15,
retained-proof20 and coordinator63 passed. Two-module Python compile and structural
validation passed (four existing warnings). Whole TDD ledger:0failures/0warnings,
70pre-enforcementlegacyincomplete. The first algorithm-fixture draft accidentally
returned its in-memory manifest for the bootstrap tree; the fixture was corrected
to distinguish actual reviewed origin from mutable state before final GREEN.

T295 and parentT286 remain pending. Existing strict verify_bootstrap/T293 frozen
origin-suffix boundaries are unchanged until final integration; this is not an
unattended completeness claim. T288 must add protected end-extension campaigns
that retain original coverage_from and old partition/seen facts, not reset/delete
history or move a forward watermark. T288/T290 must preserve authenticated old
six-file retained facts across the seven-file reader upgrade while rejecting
current omissions and preserving revocation annotations. That compatibility work
and archive App-writer hidden-metadata/credential cutover remain pending. No PR110
candidate/main merge, live credential/settings/flags/protection, push or state
write occurred; all Git writes are disposable fixture operations.
