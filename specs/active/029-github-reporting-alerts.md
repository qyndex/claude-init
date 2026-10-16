---
id: 029
slug: github-reporting-alerts
status: approved
owner: "@codex"
created: 2029-10-10
updated: 2026-10-17
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# GitHub-only reporting alerts

Approved operator decision: use GitHub-only failure and overdue-digest alerts to the configured reporting Slack destination. Independent outage coverage is optional; Healthchecks stays disabled. No per-adopter identity is hardcoded.

## Acceptance criteria

1. **AC-1**: Detect missed 08:00 Sydney digest after configurable grace using protected checkpoint and exact remote delivery health. Persist alert journal before send, suppress a prolonged incident across repeats, preserve journal across actual hosted digest updates and send one recovery after current verified delivery.
2. **AC-2**: Preserve immutable alert intent and exact bot/metadata/text/receipt binding. Lost acknowledgement or checkpoint response is reconciled on fresh invocation; absent or altered history never triggers blind resend. A labelled manual verification drill is idempotent per GitHub run and never asserts a real outage.
3. **AC-3**: Validate actual failed run against configured repository, protected default branch and hosted reporting workflow; require completed failure/timed-out schedule/manual run. Disabled, foreign and invalid-clock inputs block. Repeated failure events do not duplicate incident notices.
4. **AC-4**: Versioned bounded data-only optional alert journal rejects unknown fields, invalid receipts, duplicate identities and unjustified recovery. The existing default-off main-only failure/overdue workflow serializes with reporting; the separately approved queue probe uses its own concurrency group. The existing workflow responds to completed reporting runs and polls overdue health without any monitoring provider. Local hosted/watchdog/reporting/policy and workflow regressions pass; live labelled drill, recovery and unchanged repeat are required before claiming notification activation.

5. **AC-5**: A separately default-off protected default-branch queue probe has a concurrency group distinct from digest, feedback and ordinary alerts, while retaining the same factory-reporting environment and existing writer/Slack credentials. Read bounded exact same-repository workflow/run/job metadata and protected health. Identify an eligible reporting worker stalled beyond configured grace, including an unstarted waiting run; do not infer the actual concurrency-group owner or deployment-wait cause. Foreign identity, unknown schema, invalid/future clocks, pagination/budget exhaustion or unavailable required metadata remains explicit unknown, never healthy proof. Optional inaccessible deployment metadata cannot justify a cause or new permission.
6. **AC-6**: Isolate queue journal under reports/<role-sha256>.json, where role SHA256 binds canonical [factory-reporting-queue-v1, repository, destination, default branch]. Strict bounded versioned data rejects unknown fields, duplicate incidents, unjustified recovery and caller cursor/SQL authority. Authenticate existing protected state branch and exact reviewed initialization revision for first creation; missing journal later never silently resets. Journal changes use base_tree plus nonforce CAS, at most three fresh re-read/reconcile attempts and explicit uncertain-ack handling. Real Git restart/conflict/lost-ack tests preserve every opaque worker report/encrypted-feedback blob byte-for-byte; do not deserialize private feedback or replace worker state.
7. **AC-7**: Persist immutable queue-alert intent before Slack send, bind exact bot/destination/metadata/text and opaque receipt, reconcile uncertain effects on fresh invocation before any resend/reconstruction. Repeat observations suppress one prolonged incident and one verified recovery closes it. Missing/altered/ambiguous Slack history stays blocked; no blind retry, cancellation, deployment approval, protection change or factory authority is granted. Schema capacity failure remains explicit; no pruning retained intent.
8. **AC-8**: Actual local aggregate/workflow/reporting regressions and source-bound evidence precede reviewed rollout. An explicitly labelled queue/recovery drill then proves real Slack receipt, fresh-invocation duplicate suppression and unchanged ordinary digest/feedback state; no production worker is stalled or cancelled to create the drill. This labelled synthetic drill proves separate workflow execution and actual Slack reconciliation only; real old-waiting-worker detection is exercised by metadata/configuration fixtures, not claimed from injected drill data. Activation remains blocked until reviewed source and exact initialization/configuration are verified. Same-environment blockage and Actions-wide/Slack-wide outages remain limitations; Healthchecks and external monitoring remain optional and disabled.

9. **AC-9**: Authenticated historical queue-completion replay follows the approved2026-10-17 amendment below. A separately reviewed protected-main producer re-verifies and signs exact original native/source/log/state evidence; a bounded read-only PR consumer authenticates the distinct durable operational record. Missing, forged, revoked or incomplete proof fails closed. Historical proof grants no delivery, current-task, merge, production or current-readiness authority; the current-source live checker stays unchanged.

## Approved queue continuation — 2026-10-16

The operator explicitly approved Option A of the blocked-reporting-queue proposal.
An unstarted Oct12 digest run38288117986 and pending alert38831997734 shared the
reporting concurrency group; administrative recovery observations did not prove
all earlier digests delivered or establish the original waiting cause. This
amendment adds independent queue scheduling, not new credentials or permissions.
Spec029 remains approved; implementation and live verification are pending.

# Approved historical operational-proof amendment — 2026-10-17

Status: APPROVED. The operator selected “A Approve authenticated historical replay amendment” on2026-10-17. This approves the acceptance amendment; implementation, public upload, exact-head merges and live activation remain separate.

## Concrete defect

T318's actual native verification succeeded at protected source91839087a769bd45670df5b84cb96993bcb97d42. Its three actual run/attempt selectors are38850566089/1,38850688638/1 and38850871872/1. The publication task ledger newly marks T318 complete, so the required PR verifier re-executes its acceptance. That declaration omits required selectors; adding them is insufficient: the live checker requires checkout HEAD=current main=all three run heads, and protected reporting configuration unavailable to the PR runner. An unmerged source candidate cannot satisfy that conjunction. Copying its old live-proof.json is not authenticated replay. Full diagnosis: /private/tmp/factory-publication-acceptance-diagnosis-20261017.md.

## Recommended decision A

Authorize a narrowly typed authenticated historical operational-proof receipt for T318, reusing the already-approved main-only producer/native-attestation and per-repository durable-state architecture. Do not change the existing current-source live checker or grant historical evidence current readiness credit.

1. A separately reviewed protected-main producer independently re-reads the original GitHub repository/workflow/run/attempt/job/log facts and exact immutable state/journal lineage. It validates the original approved source and the protected execution/configuration boundary. Original observed timestamps remain original; the new verification/signing timestamp is current. Missing or expired required facts fail closed; there is no summary-only or fabricated success fallback.
2. Sign an exact purpose-bound `historical-queue-completion` record using the approved GitHub-native attestation backend. Bind repository identity, source/workflow/runtime identity, original selectors and job/log hashes, immutable journal/state evidence, verification source, producer run and record digest. Store compact authenticated proof indefinitely on that repository's existing protected state branch; detailed artifacts retain the approved90-day baseline. No private message text or secrets enter the public record.
3. The PR verifier uses bounded read-only authentication of this retained record, its trusted producer execution, source/profile authorization and applicable revocation state. Any additional PR permissions must be read-only and limited to the required Actions/attestation reads. Signing/write authority stays in the protected-main producer; no reporting environment or credentials enter a PR runner.
4. Keep this record type distinct from delivery receipts. It cannot satisfy factory current-task evidence, merge eligibility, delivery coverage, production authorization or current live readiness. TASKS remains the task authority; receipt ingestion cannot mark tasks complete. T318's historical acceptance may validate the authenticated operational record; current source behavior still runs its own tests, and T180 still requires fresh current-main capability/shadow/cutover proof.
5. Bootstrap the producer through reviewed source first; do not claim T318 publication replay passes before the authenticated record exists. If necessary, defer T318's ledger closure in the source candidate rather than weakening the required verifier. Restore the closure only after genuine proof and full applicable gates pass. This sequencing does not erase the genuine historical observation or count it as current activation.
6. No new provider, host, private key export, merge-key reuse, automatic merge activation or production activation. New trusted producer/profile registration and any exact-head source maintenance merge still require their existing concrete review/approval.

## Required verification before completion

- Genuine original-source positive record, independently authenticated against native producer and immutable journal evidence.
- Reject forged summary, wrong repository/source/workflow/run/attempt, changed log/state digest, untrusted/revoked producer/profile, missing artifact/history, malformed/truncated proof and failed signing.
- Reject using the operational record as delivery/current-task/merge/readiness evidence.
- Ordinary PR replay succeeds using only its approved read permissions; no protected reporting variables, secrets or candidate-provided trust assertion.
- Existing live checker retains all current-main, source, configuration, state and fail-closed checks unchanged.
- Durable reconstruction and restart preserve original evidence and unrelated encrypted feedback bytes; no fresh1001-history production needed for this repair.
- Full applicable publication gates run with no skip flag or substituted base. Keep a draft on failure.
