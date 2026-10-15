---
id: 014
slug: authenticated-receipt-recovery
status: approved
owner: "@codex"
human_owner: "@operator"
created: 2026-10-10
updated: 2026-10-16
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Authenticated delivery receipts and abrupt-death recovery

Authorized continuation of F-04. Protected receipt ingestion is read-only against GitHub and updates local runtime projections. Live activation and real independently reviewed delivery remain separate readiness gates.

## Acceptance criteria

1. **AC-1**: Authenticate digest-verified receipts only from successful approved default-branch coordinator runs, using an explicit reviewed exact-revision mode or a separately protected content profile. Bind immutable repository/workflow/event/branch/run/attempt/source, complete transitive runtime bytes, canonical source policy, artifact and approved spec. Reject foreign, missing, partial, revoked, expired, ambiguous, tampered or malformed proof. Never trust a self-asserted authentication flag or fall back after mismatch.
2. **AC-2**: Preserve actual merged PR repository, approved spec/task mapping, exact head, target and merge SHA. Runtime completion requires the current approved task/spec revision; historical reporting retains authenticated merge-time facts without completing revised tasks. Revocation blocks new authentication and completion in every mode, including historical and legacy; previously reported facts remain immutable with an explicit withdrawn-trust annotation. Conflicts/replays cannot alter a delivery or partially complete tasks.
3. **AC-3**: A separate guardian detects supervisor death through an inherited liveness pipe, terminates the actual worker group including descendants, then fences and requeues that attempt with bounded retries. Interrupted external actions become uncertain. A stale guardian cannot alter a newer or cancelled claim.
4. **AC-4**: SIGKILL drills prove guardian cleanup, no duplicate live worker, retained interruption outcomes and successful fenced retry. Existing cancellation, timeout, detached startup and live resource fixtures continue passing. No local outcome can claim engineering verification or merge authority.
5. **AC-5**: A protected profile outside the canonical policy authorizes exact policy digest and complete emitter closure without pinning itself or its enclosing commit. Two ordinary source commits with identical approved authority bytes authenticate without per-SHA registration. Changed policy/workflow/runtime fails until a new reviewed profile is approved; legacy imports remain explicit and constrained.
6. **AC-6**: Append compact authenticated receipt/provenance and deduplicated source-policy/spec/runtime proof indefinitely on the existing approved per-repository data branch. Retain sufficient original receipt/artifact bytes and immutable origin/digest facts to reconstruct proof after 90-day detailed Actions artifacts expire. Reject tampered, foreign, conflicting or untrusted-bootstrap archives; links alone are insufficient.
7. **AC-7**: Bounded resumable discovery covers reruns, late visibility, pagination completeness and restartable backfill without a lifetime-run cliff or silent omission. Establish explicit audited coverage origin before the first unattended merge. Missing required history, exhausted budgets, pending attempts or incomplete pagination produce a visible coverage gap and block complete-coverage claims; no cursor advances past unresolved work.
8. **AC-8**: Atomic non-forced CAS append/restart drills preserve reporting and encrypted feedback bytes. Public archives contain only approved public delivery facts; private repository/source/spec/message data never enters public state. Projection cannot create/complete tasks or grant merge authority. No new vendor, credentials or signing permissions; no automatic proof pruning.

## Approved continuation — 2026-10-16

The operator approved option A from the reviewed durable receipt trust proposal and retention A: compact authenticated receipt/provenance indefinitely; detailed producer Actions artifacts 90 days. This records actual approval, not implementation or live verification. AC-3 and AC-4 are unchanged. Existing exact-revision imports remain supported explicitly. Previously reported revoked facts remain auditable with withdrawn-trust annotations; newly revoked proof cannot complete tasks. GitHub API provenance plus the reviewed protected archive writer remains the trust boundary; retained JSON is not independently signed proof. A private adopter requires an approved private state store. Coverage origin must be explicitly initialized and audited per adopter before unattended merging; unavailable earlier history stays labelled, never fabricated or silently reset.
