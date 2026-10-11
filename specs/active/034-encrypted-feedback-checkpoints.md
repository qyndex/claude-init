---
id: 034
slug: encrypted-feedback-checkpoints
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Private encrypted feedback checkpoints

Authorized F-06/F-07 privacy work implements the operator-selected encrypted-state architecture before hosted activation.

## Acceptance criteria

1. **AC-1**: Real AES-256-GCM preserves exact SQLite feedback in an authenticated, padded ciphertext envelope. Temporary plaintext is owned 0600 inside an owned 0700 temporary root; public envelopes contain no plaintext feedback or plaintext digest.
2. **AC-2**: Reject wrong keys, tampered ciphertext, duplicate/truncated envelopes and foreign repository/channel/branch/key context before opening plaintext SQLite.
3. **AC-3**: Preserve unchanged ciphertext without checkpoint churn; after an uncertain commit, authoritative-holder replay keeps idempotent records without duplicate writes. Each changed encryption uses a fresh random nonce.
4. **AC-4**: Failed intake and invalid keys/databases or foreign SQLite identity cannot publish partial state. Remove temporary plaintext on success/failure and reject detached journals or executable SQLite schema.
