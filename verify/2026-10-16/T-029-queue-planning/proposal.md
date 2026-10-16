# Proposed Spec029 amendment: detect a blocked reporting queue

Status: proposed for operator review. No implementation or live configuration change.

## Observed problem

On 2026-10-16, the pilot reporting group was held by the unstarted scheduled digest
[38288117986](https://github.com/qyndex/claude-init/actions/runs/38288117986),
created 2026-10-12T18:01:23Z. Before cancellation, the API showed a waiting report
job, no executed steps and a pending factory-reporting deployment. Its pending
reviewer list was empty; the underlying waiting condition was not established.
Recent digest/feedback runs had been cancelled without jobs, while alert run
[38831997734](https://github.com/qyndex/claude-init/actions/runs/38831997734)
was pending. These workflows all share factory-reporting-${github.repository}.

Cancelling that stale, unstarted run allowed the alert job to complete successfully.
A current-main reconciliation digest
[38833392995](https://github.com/qyndex/claude-init/actions/runs/38833392995)
then passed Slack preflight and the authoritative state/delivery step. These are
administrative observations, not signed proof that every earlier digest delivered.

GitHub documents that a concurrency group permits one running workflow and, by
default, one pending workflow; a new pending run replaces an older pending run.
[GitHub concurrency documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).
The existing shared group protects state serialization, but can also queue the
alert that should report a stuck worker. Increasing queue capacity does not make
an alert execute while a worker holds the group.

## Recommended amendment

Keep GitHub-hosted Actions, the existing approved Slack destination and disabled
Healthchecks integration. Add a protected main-only queue-health probe with its
own concurrency group. It must execute independently of the reporting worker's
concurrency reservation while retaining environment protection.

The probe reads bounded same-repository run/job/deployment metadata and protected
reporting health. Detect a reporting run holding the group past an explicitly
configured grace, including an unstarted environment-waiting run. Report only
safe workflow/run IDs, status and timing; never message or credential plaintext.
It alerts and offers an operator link; it does not approve deployments, cancel
jobs, relax protection, retry unknown deliveries, or turn on factory authority.

Persist a bounded deduplication/outbox journal before Slack sends. Its writes must
be isolated from worker data and use actual nonforce CAS with conflict/lost-ack
reconciliation. Reuse the existing protected writer/environment; copying secrets
to another environment or changing writer authority is not approved by this
proposal. Preserve report state and encrypted feedback byte-for-byte. If safe
concurrent journal isolation cannot be demonstrated, fail closed and present that
implementation choice for review before activation.

## Required acceptance

1. Real workflow/configuration fixtures prove the probe's concurrency group differs
   from digest/feedback, while its default-branch and environment guards remain.
2. A bounded GitHub fixture with an old environment-waiting digest and pending
   worker alerts still permits the probe to detect the queue incident; short grace,
   future timestamps, unrelated repository, unknown schema and API failure reject
   or remain explicit unknown states rather than healthy proof.
3. Duplicate observations send one incident alert, retries reconcile uncertain
   Slack acknowledgement, and one verified recovery closes the incident.
4. Real Git CAS/restart/lost-ack tests preserve concurrent report and encrypted
   feedback bytes. No raw serialized SQL, arbitrary caller cursor or hash grants
   authority; source state and journal origin remain protected.
5. An explicitly labelled live queue/recovery drill occurs only after reviewed
   source rollout; ordinary scheduled delivery and existing alert regressions pass.

This improves the approved GitHub-only baseline for a worker/queue stall. It does
not provide independent coverage when GitHub Actions itself cannot start either
workflow. Independent external monitoring remains optional and disabled.

## Decision options

A — Approve this amendment (recommended). It addresses the observed blind spot
without a new provider or reporting VM; implementation and activation remain
subject to the acceptance above.

B — Keep the existing serialized alert design. Retain manual recovery for a stuck
reporting group and document that the same-group alerts may also wait.
