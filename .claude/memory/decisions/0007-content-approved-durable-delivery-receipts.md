---
name: 0007-content-approved-durable-delivery-receipts
description: "ADR-0007: Content-approved durable delivery receipts"
status: accepted
created: 2026-10-16
---

# ADR-0007: Content-approved durable delivery receipts

- **Date**: 2026-10-16
- **written_by**: architect
- **source_session**: delegated receipt planning continuation
- **last_verified**: 2026-10-16
- **subsystem**: factory

## Context

Per-source-SHA registration in the policy cannot authenticate its own new enclosing commit; full rescans also fail after artifact expiry or 1,000 runs. The operator approved option A and indefinite compact proof/90-day detailed Actions retention on 2026-10-16. This is an approved design, not implementation proof.

## Decision

Use a separately protected exact content profile outside canonical policy, explicit revocation, bounded authenticated append-only proof on the existing per-repository state branch, and resumable discovery with explicit coverage gaps. Current task authority and guardian contracts remain intact. Preserve GitHub API/protected-writer trust; no new signer/vendor/credentials and no automatic pruning. Public stores cannot hold private source/spec/message data.

## Alternatives

Exact revision imports remain an explicit legacy mode but require manual updates. Trusting all branch history weakens authority and is rejected. A third attestation signer is stronger portable proof but requires separate permissions/approval and is outside this scope. Links or self-asserted JSON are insufficient retained proof.

## Consequences

Compact storage grows indefinitely in bounded segments. Archive writer compromise remains a documented trust boundary. Budget exhaustion and absent history block coverage rather than erase it. Private adopters need private approved state. Live activation requires actual independent evidence after implementation.

## References

- specs/active/014-authenticated-receipt-recovery.md
- plans/active/014-authenticated-receipt-recovery.md
- docs/FACTORY-DIGEST.md
