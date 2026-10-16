---
name: 0009-isolated-reporting-queue-probe
description: "ADR-0009: Isolated GitHub reporting queue probe"
status: accepted
created: 2026-10-16
metadata:
  type: decision
  status: accepted
---

# ADR-0009: Isolated GitHub reporting queue probe

- **Date**: 2026-10-16
- **Deciders**: @operator (explicit Option A approval)
- **Owners**: @operator
- **written_by**: architect
- **source_session**: Codex factory reporting queue-health continuation
- **last_verified**: 2026-10-16
- **Context**: specs/active/029-github-reporting-alerts.md; T-312
- **Tags**: reporting, reliability
- **subsystem**: factory

## Context

An unstarted old digest and its monitoring alert shared the reporting concurrency
group. Cancelling the stale run unblocked the alert. These administrative facts
do not establish the original waiting cause or prove older digest delivery.
Same-group serialization protects state but can delay the alert for a stall.

## Decision

The operator approved GitHub-only Option A: a separate default-off queue probe
with distinct concurrency, same protected factory-reporting environment and
existing state/Slack credentials. It observes bounded exact repository/workflow/
run/job health and labels a stalled eligible worker without claiming group owner
or deployment-wait cause. Optional unavailable metadata stays unknown.

Use the existing inert reports/<64hex>.json namespace with an exact queue-role
hash, distinct from worker streams. Authenticate branch protection and explicit
reviewed initialization. Persist immutable intent before Slack send, reconcile
uncertain acknowledgement and use bounded nonforce CAS/reload preserving every
opaque report/encrypted-feedback blob via base_tree. Never reset a missing role
journal or resend unknown effects. No private feedback decryption is needed.

## Consequences and limits

No new provider, VM, credentials, App permissions, automatic cancellation,
deployment approval, policy weakening or factory authority. Same environment
blockage can still block the probe; Actions-wide and Slack-wide outages remain
limitations. Healthchecks is disabled; external monitoring stays optional.
Real Git CAS/restart/preservation and exact Slack receipt regressions precede
reviewed rollout and a labelled live queue/recovery/repeat drill. Source tasks
and live activation are pending; this accepted architecture is not runtime proof.
