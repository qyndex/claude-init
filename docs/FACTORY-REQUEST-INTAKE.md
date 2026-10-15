# Factory request intake: coverage and boundaries

Spec [050](../specs/active/050-request-intake-router.md) is approved. This document records the implemented foundation and assembled worker fixture; it does not certify live native capability or activate intake. Installation remains neutral and disabled by default. Missing adopter identity, protected configuration or observed runtime prerequisites blocks governed work.

## Current coverage inventory

| Boundary | Implemented fixture coverage | Operational status |
| --- | --- | --- |
| Private controller | Distinct human submission identities, exact retry tokens, stateful continuation and proposal lineage; bounded Scout collection/assessment; approval and freshness checks | Direct protected APIs tested; no universal prompt interception |
| Proposal publication | Assigned private draft path, literal untrusted data, exclusive writes and exact recovery | Cannot approve or enter wider execution scope |
| Task enqueue and claim | Fixed account installation registry, protected pins, current approved task/request, unique start identity and owner/fence CAS | Installed console uses the pinned guarded claim/descriptor protocol; legacy direct supervisor and routing entry points remain blocked |
| Protected worker prompt | Supervisor-derived private descriptor; one-use exact prompt/session/cwd submit callback | Actual fake-native plus hook subprocess fixture; no human intake allocation from callbacks |
| Worker Read | Explicit selected context or exact completed own output | Broad source scope and inventory metadata do not grant disclosure authority |
| Worker Write/Edit | Exact approved path and bounded intended postimage; durable intent before native tool permission; independently observed post bytes and acknowledgment | Unknown effects fence subsequent actions; no blind retry |
| Worker completion | Successful bounded transport, confirmed group cleanup, exact session/model usage, current owned authority and resolved effects | Runtime completion only; engineering verification remains false |
| Guarded foreground console | Actual stdin/subprocess installation lookup, distinct submissions and retries, help/status, clarification, private draft publication and eligible approved continuation; urgent owned cancellation | Native conversation delivery unavailable; guarded task workers use separate fresh one-use sessions; live enablement requires protected observations |
| Explicit authenticated Slack feedback bridge | Authenticated receipt-bound capture, immutable edit lineage, bounded tool-free Scout subprocess, pending private drafts and encrypted restored retry/failure fixtures | Offline adapter coverage; inactive until per-adopter protected dataflow approval, pins and credentials; no generic Slack capture |
| Bare CLI, IDE/filesystem edits, other agents and tools | Outside this mandatory coverage | Advisory or unsupported; editable local hooks are not a privileged OS boundary |

The assembled acceptance command is:

```sh
bash .claude/scripts/test/factory-request-intake.sh hooks
```

It runs the protected wrapper, a pinned fake native executable and actual absolute hook subprocesses. The positive journey consumes the bound prompt, reads selected context, writes a new approved file, acknowledges it, reads that own output, edits it and acknowledges the exact observed bytes. Independent fixture assertions check actual files, two completed mutations/acknowledgments, the private semantic receipt and unchanged engineering task state. Negative journeys reject unselected disclosure, outside-scope mutation, a foreign native session and failed/missing post acknowledgments. Callback replay does not permit another write or native launch. A missing-post journey emits misleading native success, remains fenced, then reconciles the exact bound post callback through the actual hook subprocess; wrong callbacks reject, exact duplicate acknowledgment is harmless, and actual bytes and launch count remain unchanged. Other worker suites cover absent/crashed/invalid/timed-out hooks, malformed results and cleanup under wrapper loss/backpressure.

## Enablement prerequisites

Each adopting repository owns its private policy, profile, installation registry and state. Required helper/executable/interpreter/settings observations must match the protected source closure before execution. The worker uses only the protected primary implementation model and a dedicated implementation subscription credential; it has no reviewer/controller credential, fallback model or automatic retry.

Supported mandatory native behavior requires an observed runtime version at least **2.1.295** with synchronous `UserPromptSubmit`, `PreToolUse`, `PostToolUse` and failure callbacks, including **`onFailure: block`**. Missing hooks, exceptions, invalid responses and timeouts must actually block in that runtime. Fake fixtures prove this adapter contract; they cannot certify a real native executable's ordering or failure semantics. Record those observations before enabling mandatory launch. See the official [hook contract](https://code.claude.com/docs/en/hooks), [CLI reference](https://code.claude.com/docs/en/cli-reference) and [memory controls](https://code.claude.com/docs/en/memory).

The wrapper's clean mode creates private cwd/HOME/config directories, pinned absolute settings and callbacks, empty MCP configuration, disabled auto memory and unmanaged instruction exclusions. It does not forward native `--safe-mode`, because native safe mode suppresses project hooks. Managed-policy compatibility and unmanaged instruction exclusion also require actual runtime observation.

Every claimed task receives a supervisor-issued fresh native session and immutable descriptor. A descriptor binds the actual task revision, request revision, owner/fence, model and prompt digest. It is consumed once and cannot be reused to allocate another human request. Human console sessions retain durable logical request identity. The installed console dispatches approved continuation through a separate guarded task worker subprocess, never by consuming a human prompt callback in-process or resuming an uncertain worker. General native conversation delivery remains unavailable. The legacy direct routing/supervisor launch path remains deliberately blocked; it does not assemble the protected console dispatch protocol.

Current finite bounds are at most 20,000 request characters, 500,000 collected context bytes, 64 KiB combined process output and 60 seconds per assessment or guarded worker turn. Adopters can choose stricter protected limits. Cleanup has a separate finite grace; limits never silently truncate or authorize another model attempt.

## Privacy, recovery and evidence

Raw requests, context, prompts, native stdout/stderr and semantic receipts stay in owner-only private storage outside candidate and authority repositories. Public projections must remain sanitized under the adopter's existing privacy contract. Explicit authenticated private Slack feedback approval does not authorize general channel ingestion.

A receipt binds private transport and effect hashes, exact native session/model usage and current approval/ref/lease/pause controls. Model narrative is untrusted data: it cannot approve scope, reconcile an uncertain write, prove tests/spec compliance, merge or deploy. Reported cost estimates are not actual subscription spend.

Successful transport is retained even when later semantic validation is paused. Unknown launch/effect outcomes fence replay. Recovery observes exact recorded effects under fresh authority; it never starts a second native process or blindly repeats a write. Current-authority checks remain necessary when validating an existing receipt.

T-243 is characterization of existing T-267–T-272 production behavior. Its assembled test is not a fabricated red/green implementation pair, full spec-050 completion, live activation, native capability certificate or engineering delivery proof.

## Installed console action acceptance (T-246)

```sh
bash .claude/scripts/test/factory-request-intake.sh phase1
```

This journey runs the actual installed console with real stdin and an isolated private fixture account. Help returns the guarded workflow explanation; status returns current private task states and eligible tasks; clarification asks for observable behavior, scope and acceptance criteria. New scope publishes the controller-assigned private draft with pending approval. Decisions retain their evidence in private storage and the console response. Draft creation grants no candidate mutation permission.

Eligible explicit continuation validates the pinned worker prerequisites and dedicated implementation credential before queue effects, then reserves one task start, claims its owner/fence, issues its descriptor and launches the pinned wrapper as a subprocess. The fake native executable invokes the actual generated absolute submit/read/write/post hooks. Independent assertions inspect the actual candidate file, acknowledgment, launch count and recorded receipt. The console independently validates that receipt and reports runtime completion with engineering verification false. A second request for the owned task cannot start another process. Missing capability evidence, changed approval and absent credentials fence task effects. A dispatch failure after valid ingress reports its bound receipt and a sanitized blocked action; the original decision remains intact and grants no fallback or automatic retry. Urgent stop cancels the owned wrapper, allows its guardian cleanup grace and checks the actual native group is gone.

These tests declare capabilities for the private fake executable only. They neither invent observations for an installed live runtime nor issue a native capability certificate. Actual pinned native hook ordering, failure blocking, clean instruction exclusion and managed policy compatibility must be observed before live enablement. An unsupported live installation remains blocked or advisory. The guarded adapter still limits each worker to at most 60 seconds plus bounded hook/cleanup overhead; runtime completion does not certify tests, spec compliance, merge or deployment.


## Explicit Slack bridge acceptance (T-252)

```sh
bash .claude/scripts/test/factory-intake-slack.sh phase2
```

The command prints and runs six intake selectors (`hosted-journey`, `authenticated`, `edits-replay`, `publication`, `checkpoint`, `checkpoint-failure`) and four existing regressions (legacy feedback, Slack feedback, encrypted feedback and hosted feedback). Any child failure stops acceptance. With no argument, the existing `authenticated` selector remains the default. Crypto checks require a Python interpreter with `cryptography` available; fixture credentials and executable observations apply only to the temporary fake executable.

The assembled hosted journey invokes the actual `factory-hosted-feedback.py` run path with fake Git/Slack clients and a real pinned fake Scout subprocess. It checks the authenticated explicit command, encrypted durable reservation before Scout, one assessment and pending private draft, a fresh decrypted holder on exact retry with no additional assessment/write, and an authenticated edit linked to the immutable prior revision. The edit supersedes the old request and creates its own assessed pending draft. The actual publication entry rejects the old request. Assertions inspect restored SQLite, unchanged reporting state, assessment counts, zero task rows, open feedback and unchanged Slack posts. Git blobs, captured API write payloads and captured public stdout/stderr exclude raw command and assessment text. No local worker or approved scope is created.

### Protected configuration and inactive rollout

This coverage remains offline and default-off. The existing reporting/feedback configuration must explicitly enable its repository, workspace/team, destination, branch, operator allowlist, receipt-bound digest and private feedback state. Generic channel conversation is unsupported. The reporting store must already contain a confirmed digest. Encrypted state uses `feedback_key_id`, the separately confirmed `feedback_bootstrap_sha`, and `FACTORY_FEEDBACK_STATE_KEY` (base64 32-byte key); existing reporting-state and Slack authentication remain required. Do not place those credentials or private files in candidate or authority repositories. Installation neither supplies pilot identity nor calls a provider.

An explicit canonical owner-only `intake_config` file in a private 0700 directory enables `hosted-slack-capture-v1`. Its version-1 fields are `schema_version`, `enabled`, `mode`, `repository`, `team_id`, `destination`, `stream`, `feedback_config_sha256` and `controller_sha256`. The stream binds repository/destination/branch; the stable feedback digest binds configuration including operators and state policy while excluding relocatable private paths. Protected source bytes are captured before a fresh encrypted holder is created. Candidate roots remain excluded after relocation.

Capture-only policy does not authorize Scout. Assessment additionally requires explicit per-adopter approval of the `private-scout-v1` dataflow and the `assessment` object: `enabled`, `dataflow`, `profile_sha256`, `trusted_files` and `limits`. The protected `assessment_profile` binds the planning primary runtime, model, tool-free/config-isolated arguments, executable/settings/MCP/observation pins and no fallback. The trusted closure contains `factory-intake.py`, `factory-intake-scout.py`, `factory-routing.py`, `factory-bounded-process.py` and `factory-feedback.py`. A planning subscription credential (`FACTORY_PLANNING_CLAUDE_OAUTH_TOKEN`) is distinct from implementation credentials. Fake observations are not a certificate for a live native runtime; actual protected observations and adopter approval are prerequisites to enablement.

Limits permit at most 20,000 request characters, 500,000 context bytes, 65,536 output bytes and 60 assessment seconds, with stricter finite values allowed and zero automatic model retries. The assembled fixture uses three assessment seconds. The existing codec caps plaintext SQLite at 4,000,000 bytes and encrypted envelopes at 6,000,000 bytes, validates supported hosted version-1 schema/provenance and preserves unrelated opaque compatible extension tables. Unknown intake protocol/schema or provenance blocks restore/writeback before provider work. Private files must be canonical, owned, 0600, single-link, finite and stable, without detached journals.

### Recovery and privacy

Assessment and proposal action intent must cross the encrypted checkpoint barrier before dependent effects. Provider/schema/quota/timeout failures block; envelope/plaintext overflow and Git CAS failure cannot silently publish or fall back. A lost PATCH acknowledgment or runner death may leave committed intent unresolved: restore the authoritative encrypted state and reconcile the exact existing identity before continuing. Do not delete reservation rows, replay Scout or rotate to another provider to bypass the fence. A pre-intent CAS loser has no committed assessment intent; a later fresh authoritative run can start only after ordinary validation. Exact retries never erase current edit lineage or revive an older decision.

Retention stays under the existing private feedback contract. This acceptance adds no deletion, history compaction, plaintext export or public telemetry policy. Operators must retain unresolved intent and its source/action provenance until reconciliation; exceeding bounds blocks instead of truncating or silently pruning. Disablement blocks dependent intake rather than granting ungated execution. Per-adopter retention, key custody/recovery and protected dataflow approval remain operator responsibilities.

T-252 characterizes and assembles existing phase-two behavior; it has no fabricated RED phase or production change. Adoption, rollback and the final acceptance matrix remain in T-253 and later tasks. These offline fixtures do not complete spec050, activate live intake, certify an adopter or authorize planning/execution of new scope.

## Neutral adoption package (T-253)

The immutable adoption package now includes `factory/request-intake.example.json` and this guide. Existing directory ownership already distributes intake controller/Scout/console scripts, generated-callback helpers and the three intake hook scripts. The example validates as disabled: repository, candidate/authority roots, database, profile and policy are null; trusted pins are empty; finite limits remain explicit. It is a template, not protected runtime configuration. The existing feedback example remains disabled and has no `intake_config` locator, so adoption does not enable hosted intake or select an assessment model/dataflow.

Use a reviewed, clean, immutable factory Git source and the existing transactional adopter CLI. For example, with your own absolute paths:

```sh
python3 /trusted/claude-init/.claude/scripts/factory-adopt.py \
  --from /trusted/claude-init --into /work/product \
  --state-root /private/adopter/adoption-journal
```

Requirements are POSIX filesystem/process semantics, Git, Bash and a suitable Python 3 interpreter. The packaging fixture is tested with Homebrew Python 3.14; the system Apple Python may be too old for runtime filesystem APIs such as `Path.stat(follow_symlinks=False)`. The CLI's optional `--check-tools` also checks `jq`. `cryptography` is required only when exercising the hosted encrypted feedback path; adopting the package itself does not require it or install dependencies.

The source and target must be canonical distinct Git roots, and the source must be clean. The CLI preflights ownership hashes/modes and foreign collisions, then writes its private external journal and `.claude/install-manifest.json` transactionally. Existing target task authority, private settings, state and memory remain adopter-owned. Active source backlog, memory, runtime state, pilot policy, private databases and credentials are excluded. Review the resulting manifest and diff before committing the target installation. No model/provider calls, network activation, cloud resources, account registry bootstrap, private intake policy/key/database creation or execution of copied scripts occurs during adoption. The adoption journal is the only private operational state this packaging step creates.

Copying scripts into a developer-editable candidate repository does not make those copies a protected enforcement boundary. Mandatory guarded console/worker support requires separately reviewed and pinned source/executable/interpreter/settings copies outside both candidate and authority roots, a private adopter policy and profile, explicit repository identity, current authoritative eligibility, dedicated credentials and independently observed capabilities. Only an explicit per-adopter bootstrap after those prerequisites may bind the protected installation into the OS-account registry. Installing these package files does not perform that bootstrap. Bare native/IDE paths remain advisory or unsupported.

The installed settings do not register the intake hooks or enable local/global intake settings; protected generated settings supply absolute callbacks only after trusted configuration is established. Do not enable an example by replacing `false` alone or reuse source pilot identity, pins or credentials. For hosted Slack, keep the existing feedback template disabled until the per-adopter prerequisites above are satisfied; the optional assessment object must stay neutral (`enabled: false`, null `dataflow`/`profile_sha256`, empty `trusted_files`, finite limits) until the private Scout dataflow is separately approved.

Packaging acceptance is `bash .claude/scripts/test/factory-intake-adoption.sh package`. It creates a clean isolated source image from current tracked package bytes plus this task's explicit new files and runs the actual adopter CLI into a fresh local product Git repository. It verifies exact ownership bytes/hashes/modes, target state preservation, disabled schemas and an audited local-Git-only installation. This proves packaging and default-off behavior. Upgrade/collision and later adoption/rollback acceptance remain separate tasks; it does not enable live intake or complete spec050.

## Protected pause, rollback and diagnostics (T-256)

Use the adopter's existing authorized control path to pause the protected runtime before rolling back an enabled entry. For hosted feedback, the authoritative encrypted runtime's `control.paused` fences Scout and private proposal effects. A fresh holder may retain authenticated feedback capture, but a new unassessed request observed during pause records `blocked` / `none` with reason `hosted-paused` and assessment count zero. Retrying that same bound revision does not silently restart it after unpause: an operator must reconcile its outcome or submit a new authenticated revision. Existing completed decisions, proposals and source lineage are retained.

Hosted guards recheck pause in the transactions that validate current requests and actual proposal effects, after the durable pre-model checkpoint and before accepting an assessment result. A pause racing an already reserved or running assessment leaves a bound unknown attempt, without a published decision/proposal; restored retries cannot reassess it. Pause is not proof that an already running native process was cancelled. Its bounded completion and unresolved intent still require reconciliation. If pause arrives after durable proposal reservation, the exact action identity remains unknown and cannot publish while paused. After explicit authoritative unpause, existing exact SQLite proposal reconciliation remains available under its original guards; this is not permission to repeat Scout or another uncertain external effect.

Do not remove intake markers/tables, clear unknown rows, delete pending history, or remove the configured bridge to force legacy behavior. An already bound encrypted store rejects absent/disabled incompatible policy. Revert code only after owned operations and unknown outcomes have been reconciled under current authority; retain additive state and the existing encrypted retention/key contract. Disabling intake cannot relax implementation gates or activate review, release, cloud resources or another provider. A pre-intent CAS conflict and a committed unresolved intent have different recovery semantics: always restore the current authoritative encrypted head before deciding whether any action is eligible.

Precise request/source/actor/revision, policy/profile hashes, assessment/action identity and reason remain in private state; raw request text and assessment material never become public diagnostics. Sanitized reporting is limited to disposition, next action, fixed reason enums, source kind and counts already supported by that boundary. Hosted CLI configuration/storage failures return a generic blocked message and withhold raw exceptions, actors, tokens, excerpts and provider stderr. Ciphertext-only Git state is not public plaintext telemetry. The rollback fixture checks the actual CLI error path and public API/blob/stdout surfaces against private markers while independently inspecting retained private provenance.

```sh
bash .claude/scripts/test/factory-intake-adoption.sh rollback-observability
```

Run this hosted crypto fixture with an appropriate Python plus `cryptography`. It exercises fresh encrypted restores, pause before and during the real fake Scout subprocess, pause inside the durable proposal boundary, exact retry, unresolved-intent retention, no downgrade, and sanitized diagnostics. Existing local console urgent-control and approval/pause fixtures cover local fencing separately. These are offline observations of the adapters, not live cancellation, capability certification, blanket interception, new retention policy or full spec050 completion.

## Final offline acceptance and evidence (T-257)

```sh
FACTORY_INTAKE_LOCAL_PYTHON=/absolute/path/to/local/python3 \
FACTORY_INTAKE_CRYPTO_PYTHON=/absolute/path/to/crypto/python3 \
  bash .claude/scripts/test/factory-intake-adoption.sh phase3
```

Choose the appropriate local Python for the console/worker/filesystem fixtures and a Python with `cryptography` for hosted state. The maintained run uses Homebrew Python 3.14 and bundled crypto Python 3.12; paths are adopter-specific. `phase3` runs the complete local request-intake suite, the additional actual console route matrix, Slack phase2, hosted rollback/observability, adoption upgrades, and runtime/supervisor/routing/ledger/bounded-process/environment compatibility checks. It forwards only ordinary environment settings, creates isolated fixture credentials/processes and does not call live providers, Slack, cloud control planes or account-registry bootstrap.

Every invocation creates a separate `verify/<date>-050-request-intake-router/phase3-attempt-*` directory with complete suite logs, command/interpreter versions, exits, durations, source/log hashes, source-default-off checks, `manifest.tsv`, `AC-EVIDENCE.md` and machine-readable `results.json`. The bundle's current `results.json` is initially marked running/unproven, then atomically replaced by that completed attempt, including failures. The acceptance process returns the runner's exact status. A failed compatibility suite or changed source/control state prevents overall success even when some AC cases pass. No stale passing result is silently reused.

The following map names the actual cases whose completed exits and observed assertion markers drive each tagged result. It is an inventory, not evidence inferred from guide text:

| Criterion | Executed proof cases |
| --- | --- |
| AC-1 | Installed console stdin and explicit authenticated Slack source, plus unsupported boundaries |
| AC-2 | Distinct submissions, issued-token retries, immutable Slack edits and actor-conflict rollback |
| AC-3 | Exact decision/action schema and actual mixed-intent draft route |
| AC-4 | Bound continuation, immutable clarification revisions and linked actual console reply |
| AC-5 | Pinned tool-free Scout, private clean subprocess context and isolated credentials |
| AC-6 | Actual enqueue/start guards, generated native mutation hooks and current-source private publication |
| AC-7 | Strict approval/OQ/spec bindings and drafts that remain pending, including unmatched maintenance |
| AC-8 | Unmatched defect proposal, read-only Scout and existing private legacy feedback fences |
| AC-9 | Encrypted intent/replay/CAS/lost acknowledgment, durable outbox and retained unknown outcomes |
| AC-10 | Quota/schema/model/context/storage/output failures, no fallback and sanitized CLI errors |
| AC-11 | Changed context/approval/pins, hostile imported approval, urgent control and hosted pause races |
| AC-12 | Zero-call answer/status and exact context/request/output/deadline/descendant bounds |
| AC-13 | Actual console routes and guarded worker, authenticated Slack, retry/edit/failure matrix |
| AC-14 | Neutral templates, immutable adoption/upgrade, foreign/custom ownership and unchanged disabled controls |

The results use AC-tagged assertion records compatible with the existing CLI evidence reader. A criterion is recorded passing only when its required suites exit zero and its specific behavioral case markers occur in those logs. This proves those maintained offline cases; it does not establish general model classification quality, every possible runtime, live native hook capability, adopter approval, engineering delivery, merge or deployment. Bare native/IDE edits remain advisory/unsupported. Source templates, source authority/merge/producers and unregistered global intake hooks are checked before and after; source bytes must remain unchanged during acceptance.

`phase3` deliberately never invokes `verify.sh` or `collect-evidence.sh`. After source/evidence review and sanctioned task completion, the owner runs repository verification/evidence collection separately with the intended `VERIFY_BASE`; its newly completed acceptance rerun can then call `phase3` safely without recursion. `collect-evidence.sh 050 --check-only` must consume the actual current tagged results and still run its required smoke gate. Failed repository gates remain failures and must be reported with their logs; the offline AC results do not waive them. No browser rig is required for these CLI entrypoints, and these tests do not activate a live adopter.
