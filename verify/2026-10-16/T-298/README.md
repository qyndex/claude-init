# T-298 — complete helper-dependent runtime closure

Actual first RED: producer candidate incorrectly accepted omission of the new
observation-helper pin. GREEN: the same acceptance command passes38 producer
cases,42 provenance assertions and actual metadata-preflight assertions. Omitted
helper in either role, altered candidate helper, altered protected-checkout helper
and incomplete emitter source revisions reject. Provenance uses committed local
Git fixture material; injected verified-certificate positives are not native live
signature proof. Both producer roles have8 current-byte pins, emitter closure7.

The preflight test verifies all16 pinned runtime hashes against actual files and
compares the complete remaining policy object to protected main6606: unchanged,
merge_enabled:false and receipts.trusted_revisions empty. Metadata presence is not
credential authentication. There is no new fixed material-count allowance in the
current producer/provenance protocol; existing ZIP/signature/observation byte caps
stay unchanged. The paused Spec014 branch has separate retained-material9→10 and
profile/runtime6→7 integration pending; no active profile/history migration occurs.

Actual scoped regressions: coordinator63 plus AC5 integration, observation60,
review-runtime (including full actionlint/workflow baseline), receipt-projection
four AC groups and receipts-recovery three AC groups passed. Recovery initially
failed in the sandbox, then the unchanged real crash/restart fixture passed with
process inspection; both facts are retained in recovery-sandbox-observation.txt
and receipts-recovery-escalated.txt. Do not infer production GREEN from that retry.
Four-module Python compile passed. Structural check passed with4existingwarnings;
ledger0failures/0warnings,70pre-enforcementlegacyincomplete. Helper/closure omission
checks run actual acceptance functions, not only implementation-shape assertions.

No push, live observation, App permission, authority/merge flag, protection change,
private capability or hosted shadow proof is included. T292 aggregate verification
remains pending after this local task; landing needs normalCI and separate reviewed
maintenance. Archive hidden-metadata adaptation is expressly outside this source
repair: its expected App-only writer actors and caller-field-independent protected
bootstrap need separately reviewed integration. Never inject actors into a live
API response or interpret v1 explicit-empty observations as archive-writer proof.
