---
id: 014
slug: authenticated-receipt-recovery
spec: specs/active/014-authenticated-receipt-recovery.md
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
---

# Authenticated receipt and worker recovery

Authenticate coordinator artifacts through GitHub API run/workflow metadata, historical source pins, archive digest and actual merged PR identity. Read the policy at the pinned run revision and bind the task mapping/spec hash. Write delivery and provenance in one local transaction; never accept a candidate-provided file as receipt input. Pin the coordinator checkout to the Actions source SHA.

Wrap the actual worker in a separate guardian owning the worker process group and inherited resource descriptors. The supervisor alone owns the liveness pipe writer. EOF after supervisor death triggers bounded worker cleanup before fencing/requeue; cleanup failure blocks recovery. Preserve an attempt outcome and uncertain outbox actions. Test live disposable process trees and fake authenticated GitHub responses with real ZIP digests.

The initial receipt contract accepts one explicitly approved task per delivery. Automated fixtures cover artifact/source/PR negatives, immutable replay, a real SIGKILL process tree, duplicate exclusion and fenced retry. Live receipt ingestion and simultaneous guardian death remain separate readiness work.
