# Local worker ownership and recovery

The runtime store is a transactional projection of task IDs, approved revision hashes and dependencies; tasks/TASKS.md remains task authority. Register a task through `Store.enqueue` from a trusted ledger adapter before launching it. Claims allow one owner and carry monotonic fencing tokens. Task states never equate worker exit zero with verified or merged delivery.

Launch a foreground command with an explicit working directory and central runtime database:

```bash
python3 .claude/scripts/factory-supervisor.py \
  --db /absolute/path/to/runtime.sqlite --task T-185 \
  --cwd /absolute/path/to/isolated/worktree \
  --attempts /absolute/path/to/attempts --timeout 1800 --lease 30 \
  -- command arg1 arg2
```

Add `--detach` before `--` when the shell launcher should return. The response is a supervisor PID, not proof of a successful claim. Inspect the durable task state and launcher/attempt logs. Commands must remain in the foreground; background Claude flags are rejected. Each attempt gets a private log/outcome directory and TMPDIR. Repository-specific ports, databases and service isolation still require an adoption adapter; the directory alone does not isolate those resources.

The supervisor heartbeats while its worker runs. SIGTERM/SIGINT, timeout or loss of ownership terminates the worker process group, including descendants. Success advances only to verifying. Failure blocks the task. A separate inherited task lock prevents a new supervisor while a surviving worker retains that descriptor; abrupt supervisor death can leave a worker requiring operator reconciliation. Do not assume a SIGKILL produced a clean shutdown. Outbox actions interrupted after dispatch require remote reconciliation before retry; they are never blindly replayed.

Fleet dispatch, reconciliation and respawn share a checkout-local `shared-writers.lock` across their complete operation. Nested wrappers validate and reuse an inherited lock descriptor. Task GC shares `memory-plane.oslock` with existing ledger/memory writers. The kernel releases locks when all owning descriptors close; lock files are persistent names, not stale PID markers, and must not be deleted to force entry. Locks coordinate local cooperating processes, not independent hosts or arbitrary editors. GC retains completed IDs referenced by unfinished tasks.

The overnight fallback now retains an OS lock while a foreground Claude process runs under an independent watchdog. `CLAUDE_OVERNIGHT_TIMEOUT_SECONDS` defaults to 19800 seconds and cannot exceed 21600. Exit 124 reports a timeout. Existing remote-branch and recent-report guards remain. This path does not yet import each agent task into the runtime database; it therefore does not complete unattended F-04 integration by itself.

Verification covers independent-process races, nested locks, mixed ledger writers, heartbeat renewal, cancelled claims, descendant termination, detached launcher lifetime and the actual overnight script using fake Git/Claude executables. Factory authority remains disabled. Remaining F-04 work includes approved-ledger import, archive reconciliation, per-service isolation and fencing every mutating runtime adapter; F-05–F-08 remain separate packages.

Upgrade the lock library only after stopping and draining existing writers. Already-running processes with the older directory-lock implementation do not coordinate with the new OS-lock protocol. Repository adoption must perform that quiescent migration before allowing concurrent work.

## Approved-ledger entry point

Factory workers should enter through `factory-ledger.py`, using a trusted authority checkout and protected policy separate from the implementation worktree:

```bash
python3 .claude/scripts/factory-ledger.py \
  --authority-root /absolute/path/to/authority-checkout \
  --policy /absolute/path/to/protected-policy.json \
  --db /absolute/path/to/runtime.sqlite --task T-42 \
  --cwd /absolute/path/to/implementation-worktree \
  --attempts /absolute/path/to/attempts --timeout 1800 \
  -- command arg1 arg2
```

Without a command, the entry point only imports the task closure. It reads active and archived ledger files under the same OS lock used by task/memory writers and GC. Policy spec entries must contain the exact approved spec path/SHA-256, full AC set and allowed path scope. Imports are atomic and idempotent; existing unapproved/manual registrations cannot be silently upgraded. Local [x]/[s] markers do not complete dependencies. A trusted receipt adapter must call `confirm_merge` with the approved revision and actual repository/PR/merge SHA after authenticating delivery. This API does not authenticate a supplied receipt by itself and has no public CLI that accepts candidate-produced delivery JSON. Connecting protected GitHub receipts is still a readiness dependency.

The runtime configuration can declare supported resources:

```json
{"runtime":{"services":[{"name":"http","kind":"tcp"},{"name":"sqlite","kind":"directory"}]}}
```

Each attempt exports `FACTORY_RESOURCE_NAMESPACE`, `FACTORY_RUN_DIR`, `TMPDIR` and JSON `FACTORY_SERVICES`. A TCP entry contains an inherited listening `fd` and its bound localhost `port`; the worker must serve using that descriptor rather than close it and rebind. A directory entry contains a private `directory` for a local database or files. Allocations last for the supervised attempt and sockets close during cleanup. Fixture workers prove distinct simultaneous listeners and storage directories. These adapters do not isolate an external database, Docker network, arbitrary process environment or service that ignores the contract; unsupported kinds are rejected until a tested adapter exists.

Task minting scans archived ledgers as well as the active ledger. Task helpers now share `memory-plane.oslock` with GC and preserve caller return variables. Same-lock nested calls are supported; nesting a different function-lock name fails with exit 75 rather than deadlocking. Descriptor 9 is reserved while a shell helper owns a lock. Fleet pivot uses the fleet lock and a same-directory temporary file. Quiescent upgrade remains necessary when old writer versions are still running.
