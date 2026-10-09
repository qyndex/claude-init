---
id: 012
slug: supervised-local-workers
spec: specs/active/012-supervised-local-workers.md
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
---

# Supervised local workers

Serialize maintained shared writers through a portable Python fcntl wrapper. Keep an inherited descriptor across nested calls, validate it against the lock inode and re-lock it before reuse. Use process groups and bounded termination for the foreground worker supervisor. The supervisor keeps its own claim alive, writes attempt-scoped outcomes and never interprets worker exit zero as verification or delivery. Provide a detached launch command with persistent logs; do not depend on a shell launcher PID for ownership. The overnight fallback becomes a foreground process with a bounded watchdog and OS lock; runtime-ledger integration is a subsequent adoption step, not inferred from its agent prompt.
