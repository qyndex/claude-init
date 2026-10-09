---
id: 011
slug: durable-runtime-state
spec: specs/active/011-durable-runtime-state.md
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
---

# Durable runtime state implementation

Spec: specs/active/011-durable-runtime-state.md

Use Python's standard SQLite library, immediate transactions and a busy timeout. Store only runtime projections of ledger task IDs and approved revisions. Persist fencing tokens across reclaim; guard all worker mutations with owner/token/expiry. Keep an explicit state transition graph. A durable outbox distinguishes pending, dispatching, uncertain and confirmed; uncertain effects require remote reconciliation before retry. Test races in independent processes and reopen the database after every recovery boundary.

This package does not migrate swarm writers or install a supervisor. Those follow only after this state contract is verified. No GitHub credential or model invocation is required by these tests.
