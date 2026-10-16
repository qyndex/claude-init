---
id: 029
slug: github-reporting-alerts
status: approved
owner: "@codex"
created: 2029-10-10
updated: 2026-10-16
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

## Approved queue continuation — 2026-10-16

The operator explicitly approved Option A of the blocked-reporting-queue proposal.
An unstarted Oct12 digest run38288117986 and pending alert38831997734 shared the
reporting concurrency group; administrative recovery observations did not prove
all earlier digests delivered or establish the original waiting cause. This
amendment adds independent queue scheduling, not new credentials or permissions.
Spec029 remains approved; implementation and live verification are pending.
