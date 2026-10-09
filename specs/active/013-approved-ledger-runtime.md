---
id: 013
slug: approved-ledger-runtime
status: approved
owner: "@codex"
human_owner: "@operator"
created: 2026-10-10
updated: 2026-10-10
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Approved ledger runtime integration

Authorized continuation of F-04. Read task authority from active and archived ledgers and approved spec pins. Local completed markers never prove delivery. Service adapters remain responsible for configuring actual port/database isolation.

## Acceptance criteria

1. **AC-1**: Import an approved task and its complete dependency closure atomically from active and archived ledgers. Duplicate IDs, missing or cyclic dependencies, changed spec bytes, unknown approval and changed immutable task scope fail without partial imports.
2. **AC-2**: Archived IDs remain reserved for task minting. Task, memory and GC writers share one lock; helper return values survive locking and nested same-lock helpers do not deadlock. Initialization and pivot fleet updates use their matching writer lock.
3. **AC-3**: Dependency delivery requires confirmed exact-task/revision merge receipts, never an [x] or [s] marker. Reimport is idempotent; changing a registered revision is rejected. Supervisor startup checks the imported approval before claiming and runs the caller's explicit foreground argv.
4. **AC-4**: Each claimed attempt receives a unique resource namespace and private temporary directory. Approved service adapters must consume that namespace; missing service isolation declarations block configured service runs. Fixtures prove disjoint attempt resources and fail-closed adapter declarations without claiming arbitrary application isolation.
