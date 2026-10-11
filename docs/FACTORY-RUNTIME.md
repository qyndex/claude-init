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

The supervisor heartbeats while its worker runs. SIGTERM/SIGINT, timeout or loss of ownership terminates the worker process group, including descendants. Success advances only to verifying. Failure blocks the task. A separate guardian owns the inherited task lock and worker cleanup. EOF on its liveness pipe detects supervisor death even when the actual worker closes its inherited descriptors. The guardian terminates the worker group before fencing/requeue; failed cleanup blocks the task. Guardian death itself still requires operator reconciliation and must not be treated as clean recovery. Outbox actions interrupted after dispatch require remote reconciliation before retry; they are never blindly replayed.

Fleet dispatch, reconciliation and respawn share a checkout-local `shared-writers.lock` across their complete operation. Nested wrappers validate and reuse an inherited lock descriptor. Task GC shares `memory-plane.oslock` with existing ledger/memory writers. The kernel releases locks when all owning descriptors close; lock files are persistent names, not stale PID markers, and must not be deleted to force entry. Locks coordinate local cooperating processes, not independent hosts or arbitrary editors. GC retains completed IDs referenced by unfinished tasks.

The overnight fallback now retains an OS lock while a foreground Claude process runs under an independent watchdog. `CLAUDE_OVERNIGHT_TIMEOUT_SECONDS` defaults to 19800 seconds and cannot exceed 21600. Exit 124 reports a timeout. Existing remote-branch and recent-report guards remain. This path does not yet import each agent task into the runtime database; it therefore does not complete unattended F-04 integration by itself.

Verification covers independent-process races, nested locks, mixed ledger writers, heartbeat renewal, cancelled claims, descendant termination, detached launcher lifetime and the actual overnight script using fake Git/Claude executables. Factory authority remains disabled. Approved-ledger import, archived ID reservation and basic TCP/directory resource contracts are implemented. Remaining F-04 work includes fencing every external mutating adapter and deployment-specific resource isolation; F-05–F-08 remain separate packages.

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

Without a command, the entry point only imports the task closure. It reads active and archived ledger files under the same OS lock used by task/memory writers and GC. Policy spec entries must contain the exact approved spec path/SHA-256, full AC set and allowed path scope. Imports are atomic and idempotent; existing unapproved/manual registrations cannot be silently upgraded. Local [x]/[s] markers do not complete dependencies. A trusted receipt adapter must call `confirm_merge` with the approved revision and actual repository/PR/merge SHA after authenticating delivery. This API does not authenticate a supplied receipt by itself and has no public CLI that accepts candidate-produced delivery JSON. The authenticated adapter below now provides the GitHub ingestion path; live proof remains a readiness dependency.

The runtime configuration can declare supported resources:

```json
{"runtime":{"services":[{"name":"http","kind":"tcp"},{"name":"sqlite","kind":"directory"}]}}
```

Each attempt exports `FACTORY_RESOURCE_NAMESPACE`, `FACTORY_RUN_DIR`, `TMPDIR` and JSON `FACTORY_SERVICES`. A TCP entry contains an inherited listening `fd` and its bound localhost `port`; the worker must serve using that descriptor rather than close it and rebind. A directory entry contains a private `directory` for a local database or files. Allocations last for the supervised attempt and sockets close during cleanup. Fixture workers prove distinct simultaneous listeners and storage directories. These adapters do not isolate an external database, Docker network, arbitrary process environment or service that ignores the contract; unsupported kinds are rejected until a tested adapter exists.

Task minting scans archived ledgers as well as the active ledger. Task helpers now share `memory-plane.oslock` with GC and preserve caller return variables. Same-lock nested calls are supported; nesting a different function-lock name fails with exit 75 rather than deadlocking. Descriptor 9 is reserved while a shell helper owns a lock. Fleet pivot uses the fleet lock and a same-directory temporary file. Quiescent upgrade remains necessary when old writer versions are still running.

## Authenticated delivery ingestion

Run `python3 .claude/scripts/factory-receipts.py --policy /absolute/path/to/trusted-policy.json --db /absolute/path/to/runtime.sqlite --run-id 12345` from trusted installed code with a read-capable GitHub CLI identity. No supplied local receipt file is accepted. Configure `receipts.workflow_id` and `receipts.trusted_revisions` in protected policy; each revision maps the coordinator workflow, coordinator, preflight and evidence validator paths to SHA-256 hashes. The checked-in configuration is empty and disabled.

The adapter authenticates run identity/event/default branch, successful conclusion, pinned source closure, artifact digest and actual merged PR. It reads policy/spec at the run source revision and requires current spec/task mapping to match. Delivery and immutable source/run/artifact provenance commit in one SQLite transaction; conflicting replay fails. The initial contract supports exactly one explicitly approved `task_ids` entry per spec delivery. Multiple tasks require a future per-task acceptance mapping and cannot be inferred from spec-wide proof.

Coordinator checkout uses the Actions source SHA. A guardian retains `guardian.json` after abrupt supervisor death, confirms process-group cleanup, fences the old claim and requeues within the existing attempt limit. Interrupted dispatches become uncertain and require remote reconciliation. Workers that escape their process group and simultaneous guardian/supervisor death remain outside this cleanup guarantee. Local outcomes never certify engineering verification. No live authenticated receipt or independently reviewed delivery has been demonstrated while review capacity is paused.

## Worker credential inheritance

Supervised workers and their guardians receive a deny-by-default environment containing ordinary runtime keys and assigned per-attempt resources. GitHub tokens, App keys, Slack tokens, encryption keys, cloud credentials, provider API keys, proxies and interpreter/loader injection variables are dropped. A separately supplied `FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN` maps only to the worker’s `CLAUDE_CODE_OAUTH_TOKEN`; an inherited reviewer/coordinator OAuth token is never borrowed. This is a subscription credential, not permission to fall back to metered APIs.

Environment filtering alone cannot isolate native workers running under the coordinator’s OS account. HOME/keychain, same-user files and process visibility remain accessible. Do not enable autonomous factory workers or merge authority until an isolated container/principal adapter and its external-process cleanup have passed real drills. Current native supervision is useful for authorized manual execution and fixtures; success still means verifying, never independently verified. Local live CLI authentication and the isolated runtime are separate rollout prerequisites.

## Protected role and model routing

`factory-routing.py` validates an operator-owned profile stored outside authority and candidate checkouts: parent 0700, JSON 0600, exact repository and SHA-256 pins for trusted probe/runtime files. Required roles are planning and implementation locally, and independent review, verification and security in Actions. Each primary and explicit fallback must retain the role's capability floor and authority location. Optional browser/reporting roles have their own floors. Unsupported source extensions or detected stacks without configured tools/acceptance adapters block startup. Stack inspection disables Git fsmonitor and hooks and does not execute project setup.

An enabled profile contains schema_version=1, enabled=true, repository, source_roots, stacks, roles and runtimes. Each stack declares absolute executable tools and an acceptance argv; each role declares primary, fallbacks and capabilities. Each runtime declares kind, model, billing, location, allowed_model_usage, command and probe. Probe declares argv, trusted_files (absolute path to SHA-256), and timeout (1–30 seconds). Claude uses explicit full model IDs, billing=subscription and safe-mode structured foreground output. Review must use a fresh nonpersistent run. The acceptance fixture demonstrates the complete schema with synthetic model IDs; adopters must obtain their actual supported model and auth metadata rather than copy those IDs.

`factory-claude-probe.py --binary ABSOLUTE_CLAUDE --model FULL_MODEL_ID --auth-method EXPECTED_AUTH_METHOD --subscription-type EXPECTED_SUBSCRIPTION_TYPE` checks native CLI flags/auth in a neutral temporary directory. Without `--live` it deliberately reports unavailable. An explicitly configured `--live` performs a bounded, tool-free fixed prompt and requires structured native model usage for the exact configured model. Dedicated FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN and FACTORY_REVIEW_CLAUDE_OAUTH_TOKEN are routed separately; use `--credential-kind review` for the review probe. Shared coordinator OAuth and metered provider keys are never fallback credentials. Keep trusted controller code/configuration outside candidate write access; file modes alone cannot isolate processes running under the same OS user.

[Claude headless documentation](https://code.claude.com/docs/en/headless) describes native structured output. Native client cost fields are conversation-scoped API-equivalent estimates; they are not actual subscription charges and should not be summed as billed spend. Authentication alone does not prove available capacity. Quota/reset remain unknown unless a trusted typed probe supplies them. Capacity blockers checkpoint privately without claiming work or spending a task attempt.

The approved policy runtime.routing_profile_sha256 binds canonical profile JSON; runtime.roles_by_task binds each task to planning or implementation. Launch through `factory-ledger.py` with existing authority-root/policy/db/task/cwd/attempts arguments plus `--routing-config ABSOLUTE_PRIVATE_PROFILE`. Caller command overrides are forbidden. Private databases need a matching repository namespace; existing nonempty legacy stores require an explicit migration, never silent rebinding. Runtime route events persist decisions and outcomes, with success only reaching verifying. OS isolation, real reviewer capacity, independent receipts and deterministic eligibility remain required before unattended rollout.

## External worker effects and cleanup fences

The private runtime `worker_effects` table records immutable repository, namespace, container name and pinned image identity before a trusted guardian dispatches an external effect. `register_worker_effect` requires current task ownership and fence. Pending intent is conservatively uncertain: a lost create acknowledgement does not establish remote absence. The store blocks claims after lease expiry, transition to verification/delivery and guardian requeue while any effect remains unresolved.

`confirm_worker_effect_cleanup` accepts only the exact typed docker-offline identity/absence observation from the trusted adapter; it is a local adapter contract and does not authenticate independent review. Candidate containers must have no access to this database or controller process. Cleanup is idempotent and can reconcile a prior effect after cancellation or blocked recovery without restoring task authority. Unknown cleanup remains visible and cannot be silently dropped to permit retry. The next container adapter must inspect actual daemon ownership and absence before calling this method; synthetic store tests do not prove live isolation or cleanup.

## Offline container execution

An approved resource contract may include `execution` with kind `docker-offline`, canonical Docker executable and SHA-256, locally present immutable image ID, repository, memory_mb, cpus and pids_limit. Run only on nonroot Linux. Workers receive one candidate bind mount and no host provider/coordinator credentials, networking or private runtime state. Use a clean approved image. Containers share the host kernel; production workers require suitable dedicated infrastructure. See [Docker security](https://docs.docker.com/engine/security/).

Intent and observed container ID survive coordinator failure. Unknown daemon cleanup fences retry and verification. Reconcile stale effects using `factory-container.py --config /private/config.json --db /private/runtime.db --task T-ID`; private canonical owned files must have mode 600 and parents 700. This command never dispatches or revives a task. Failed creation without durable acknowledgement/presence remains uncertain even when a subsequent list is empty.

The enabled required Linux CI drill must pass before claiming isolation. Local fake-daemon fixtures exercise contracts only. This adapter deliberately does not supply Claude provider egress or establish subscription capacity.

## Private output and retention

Approved runtime resources may set `output_limit_bytes` from 1024 through 8000000 (default 1000000). The guardian streams combined worker output into mode-600 `worker.log`, monitors parent liveness and waits for complete EOF. Overflow blocks verification and cleans the worker; partial output never counts as a native model result. Git inventory, native/routing probes and Docker acknowledgements are bounded while read, including timeout and owned process-group cleanup. Docker uncertainty retains its durable fence.

Raw logs, argv and feedback stay private. `factory-private-artifacts.py` accepts a canonical owned mode-600 policy outside the candidate checkout with exactly `repository` and `retention_days` (1–365). Database/policy parents and attempt root require mode 700. Repository binding must already exist in the runtime store. Example protected policy: `{ "repository": "owner/project", "retention_days": 30 }`.

```sh
python3 .claude/scripts/factory-private-artifacts.py --config /private/artifacts.json --db /private/runtime.sqlite --attempts /private/attempts metrics
python3 .claude/scripts/factory-private-artifacts.py --config /private/artifacts.json --db /private/runtime.sqlite --attempts /private/attempts retain
```

Retention defaults to dry-run. Add `--apply` only in a trusted maintenance job after reviewing eligible counts. It requires old terminal namespaces, exact task/fence metadata, confirmed cleanup, released task locks and no unconfirmed external effects/actions. Active, uncertain, unknown, symlinked or hardlinked state stays protected. SQLite receipts are never removed. Metrics expose only aggregate runtime states and unresolved worker-effect counts; they do not certify verified delivery or satisfy rollout gates. No pilot retention job is enabled by this package.
