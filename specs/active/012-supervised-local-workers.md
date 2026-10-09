---
id: 012
slug: supervised-local-workers
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

# Supervised local workers and shared writers

Authorized continuation of F-04. Runtime claims remain projections of approved task authority. This package provides supervised foreground workers and serializes the maintained fleet dispatch/reconcile/respawn and task GC scripts. It does not enable autonomous merges or certify arbitrary external writers.

## Acceptance criteria

1. **AC-1**: Competing fleet and ledger mutations acquire one repository-scoped OS lock across their entire read/modify/write operation; nested reconciliation/respawn calls reuse a verified inherited lock without deadlock. Task GC shares the ledger/memory lock and retains completed dependencies of unfinished tasks. Lock ownership survives a waiting launcher and is released after process termination.
2. **AC-2**: A supervisor claims an approved registered runtime task, runs a foreground argv in a new process group, heartbeats the lease and retains ownership until the worker ends. Success advances only to verifying; failed workers become blocked.
3. **AC-3**: Timeout, cancellation and lease loss terminate the worker process group before reporting failure. Unique attempt directories retain command outcome and logs; startup rejects background Claude argv. Restart cannot duplicate an active claim.
4. **AC-4**: The local overnight launcher runs a supervised foreground Claude process under its retained lock instead of launching a detached session and deleting its guard immediately. A detached supervisor entry point survives launcher exit; shutdown and timeout drills use fixture workers without invoking a paid model.
