---
id: 050
slug: request-intake-router
status: approved
spec: specs/active/050-request-intake-router.md
owner: "@codex"
created: 2026-10-12
updated: 2026-10-12
phases: 3
---

# Plan 050: Automatic request intake and Scout routing

## TL;DR

Add a private durable intake controller, a tool-free bounded Scout using the existing protected planning profile, and actual guards at enumerated factory action boundaries. Deliver Claude Code integration first, bridge only already authenticated Slack feedback second, and finish neutral adoption and coverage proof third; all deployment enablement remains explicit and separate from implementation.

## Confirmed entry decision

The human approved spec050 and selected the guarded factory console on 2026-10-12. Launch the console once per session; it allocates every human submission before native delivery. Bare native sessions remain advisory. Live enablement requires observed native ordering, fail-closed hooks and protected runtime pins; fixtures do not certify production readiness.

## Architecture

### Components

- `.claude/scripts/factory-intake.py`: strict schemas, private store migration, bindings, cheap classification, Scout result validation, continuation resolution, guarded proposal/task/action dispatch and reconciliation. Imports existing runtime, ledger and bounded-process modules by the repository's established importlib pattern.
- `.claude/scripts/factory-intake-scout.py`: selects exactly the primary protected planning runtime, verifies executable/script pins and observed model usage, builds bounded sanitized context, and invokes its dedicated tool-free assessment command. Do not call `factory-routing.run` for assessment: that function starts an approved task worker and owns task leases. Reuse its profile validation, protected path/pin checks and JSON/usage validation instead, with a distinct read-only assessment adapter.
- `.claude/scripts/factory-intake-console.py`: trusted foreground console launcher, outside candidate ownership, captures explicit human input and allocates submission identity before native launch. `.claude/hooks/request-intake.sh`: correlates native `UserPromptSubmit` with that already allocated pending ingress; it does not infer human origin or allocate a new request from hook text. `.claude/hooks/pre-intake-action.sh`: gates enumerated Write/Edit/NotebookEdit and factory Bash/dispatch operations before effects. Keep keyword skill hints for discovery but they cannot satisfy enforcement.
- Existing `factory-ledger.import_task`, `factory-routing.run`, supervisor claims and feedback draft publication receive a shared controller prerequisite check when their protected intake contract is enabled. They retain independent approval, scope, lease and receipt checks.
- Existing `factory-slack-feedback.py`: invoke intake after receipt validation and `Feedback.intake_batch`, bound to the returned feedback identity. Existing `factory-hosted-feedback.py` encrypted private DB lifecycle checkpoints additive intake tables without projecting raw material. No generic Slack capture or new Slack sending.
- `docs/FACTORY-REQUEST-INTAKE.md`: coverage inventory, installation/runtime prerequisites, runbook, private configuration, identity/retry contract and advisory limits. Neutral disabled example packaged through existing immutable adoption manifest.

### Trust and controlled paths

The protected owner-only intake configuration lives outside candidate checkouts beside the private runtime database. Its repository binding, enabled state, profile hash, approved policy hash, controller/executable hashes, action inventory and data-flow approval are authoritative. Candidate settings/env can locate a protected contract but cannot override it. Protected factory launchers bind and pass its verified digest; direct CLI callers must resolve the same canonical owner-only configuration. A candidate missing its locator cannot make an enabled protected launcher revert to ungated legacy behavior.

The controller-owned runtime DB is the protected registry: enabled installations persist the intake binding in the same private database consumed by ledger/routing. At the start of `import_task` and `routing.run`, before queue/start effects, inspect that registry regardless of whether the caller supplies intake arguments. If enabled/paused, omission of a request/action identity is an error; a supplied alternate empty DB cannot qualify because existing repository/runtime authority binding and protected launcher database selection must match. A direct programmatic fixture may use a fresh explicitly disabled registry, but that is not an enabled-cohort bypass. Authoritative profile/launcher also pins the required-intake bit and store identity, so removed/corrupt registry tables reject for enabled profiles rather than imply disabled.

Default-disabled legacy installations preserve existing behavior and are labelled unsupported for mandatory intake. After enabling, disabling or losing intake pauses governed mutation until an explicit operator transition; it never falls through to legacy execution. This requires a persisted enabled/paused binding in protected storage, independent of an editable environment variable. A malicious local same-user developer can alter ordinary files and hooks; this plan makes no sandbox or universal filesystem interception claim.

Inventory mandatory boundaries: proposed-spec publication through controller, feedback proposed-draft publication, task ledger import/enqueue, local routing start, supervised implementation worker mutation within approved allowed_paths, and installed Claude Write/Edit/NotebookEdit/Bash hooks. Native worker isolation/approved scope remains the enforcement boundary for its effects. Opaque Bash commands are not parsed to certify read-only safety: controlled sessions permit only enumerated read commands or an eligible bound task principal through existing scope/isolation controls. Unknown Bash is blocked. Answer/status routes grant no executable-tool permit beyond explicitly enumerated trusted read commands; implementation routes receive a task-stage permit that remains subject to actual existing isolation. No arbitrary shell path confinement is claimed without a tested isolation boundary. Any uncovered MCP/editor/raw-shell path is advisory/unsupported and is not advertised as mandatory. Hooks return nonzero blocking status on failure and never print raw request text.

Stop/pause/revocation gets precedence: identify exact cheap control forms, request existing owned supervisor/guardian cancellation before model invocation, then record outcome. If storage fails, cancellation still happens and dependent work stays blocked; no successful durable outcome is invented.

### Data flow

Human entry -> trusted ingress identity allocation -> private request commit -> cheap disposition or reserved single Scout assessment -> strict decision commit -> independently validated permitted action -> durable action intent -> existing dispatcher/claim -> reconciliation/outcome. No SQLite transaction is held during a model subprocess. Only controller-captured console input and authenticated Slack adapter input can assert human ingress. Native callbacks without a matching pending console submission cannot mint a human request; neither a hook field nor caller-supplied origin string establishes provenance. Unsupported origins receive a sanitized unsupported outcome without capturing their text.

## Data model

Use additive `intake_` tables in the existing bound SQLite database; no views/triggers and no modification of existing feedback/runtime rows. Schema_version=1 lives in `intake_identity`; migrations use an explicit version allowlist, `BEGIN IMMEDIATE`, rollback on incompatible versions, `trusted_schema=OFF`, DELETE journal mode for hosted checkpoint databases, and existing owner-only canonical path checks (root700, DB600, outside all candidate roots, no symlink/hardlink).

| Entity | Columns and constraints |
|---|---|
| intake_identity | singleton id=1, schema_version, repository, policy_sha256, contract_sha256, enabled_latch, mode=enabled/paused; foreign bindings reject |
| intake_sessions | session primary key, repository, actor, next_sequence integer, current_request nullable; allocation is atomic |
| intake_requests | request_id primary key, source_kind, submission_key, source_revision, parent_request, session, sequence, actor, repository, ref, content_sha256, policy_sha256, scope_sha256, payload_sha256, private_payload JSON, state, created_at; UNIQUE(source_kind,submission_key,source_revision), UNIQUE(session,sequence) |
| intake_assessments | request_id/revision primary key, assessment_id unique, state=reserved/running/completed/blocked/unknown, count=0/1, protected profile/runtime hashes, started/deadline, result_json, reason; unknown cannot silently retry |
| intake_decisions | request_id/revision primary key, decision_sha256, exact decision_json, state=current/invalidated, created_at |
| intake_actions | action_id primary key, request_id/revision, kind, target, target_revision, stage, decision_sha256, state=intent/started/completed/blocked/unknown, existing_claim_owner/fence nullable, reconciliation_json; UNIQUE(request_id,revision,kind,target,target_revision,stage) |
| intake_events | monotonic sequence primary key, request_id, event_kind, private_details JSON, time; sanitized projection has an explicit allowlist |

A distinct request must not start duplicate approved task execution: existing supervisor claims serialize task/stage/revision; guard persists the action identity with expected task authority and fence, then dispatcher uses existing claim logic. The intake table is not a replacement lease. If effect starts but outcome commit is lost, reconcile exact existing task/attempt/action identity; never blindly retry. Proposal publication uses a controller-assigned canonical target and content digest, exclusive creation or compare-existing replay; conflicting existing bytes block. No intake record becomes merge evidence.

### Native human provenance and pending delivery

The initial mandatory Claude entry is the installed factory console launcher, launched once per operator session; users type normal prompts without per-message workflow commands. Bare native interactive/IDE/Desktop sessions remain advisory until a stronger independently observed source contract exists. This is a runtime prerequisite within explicitly scoped support, but it changes the terminal experience and should be disclosed before adoption.

The console captures each human submission itself, authenticating only the configured local operator, and commits a new UUID request plus monotonic sequence, exact UTF-8 payload digest and expected native session UUID before invoking native foreground print mode. First turn uses configured native `-p --session-id UUID`; subsequent turns use `-p --resume UUID`. Supply user prompt via stdin rather than exposing raw text in argv. The launcher retains a private session mapping and serializes turns; a new prompt is not queued until prior native launch has exited/reconciled. Native session identity is checked against the hook's actual session_id and final observed session, not guessed from cwd or a recent conversation.

Add `intake_pending_native(request_id PRIMARY KEY, native_session, payload_sha256, launch_nonce, state=pending|consumed|expired|unknown, expires_at)` and an exclusive pending-session constraint. Only protected launcher code can create pending rows. The first exact session/digest match atomically consumes the row and references the existing intake record; additional callbacks cannot consume it again. Unmatched callbacks are handled without private text capture as generated/unverified, with no human reintake or new action grant. Match is a correlation to already authorized input, never a text-based request identity. Distinct identical console submissions obtain distinct UUIDs/sequences. Explicit delivery retries use controller-issued tokens; lost launch/consume acknowledgements become unknown and reconcile, not guessed duplicates.

A same-text generated callback before the intended submit could consume a digest match: therefore the supported launcher allows only one owned foreground child per session, no background agents, scheduled loops, inbound channels or cross-session producers during the pending window. The adapter startup fixture must demonstrate the initial foreground callback occurs before generated work; if native ordering/feature restriction cannot be observed, this entry stays blocked. Even a mistaken consumption cannot mint broader authority or a second request; existing task/decision guards independently limit actions. Console control input interrupts/cancels owned running work immediately, independently of the native input loop. No claimed prompt origin field is added to the native schema.

Slack submission key remains authenticated workspace/channel/message timestamp; edit timestamp is linked new revision. Repeated same-key conflicting bytes reject.


## API contracts

CLI JSON on stdin, private stdout result and sanitized hook rendering; no network endpoint. Commands: `submit`, `decision`, `dispatch`, `guard`, `reconcile`, `pause`, `coverage`. All load the protected contract before effects; no caller-supplied policy/schema/controller overrides. Request-source diagnostics are controller-derived; a caller string cannot create authenticated actor provenance. Exit0=validated result, exit2=blocked/unsupported/clarify where no dependent effect is allowed, exit3=durable reconciliation required. Hook adapter maps controlled denials to exit2/runtime block JSON. Install synchronous command hooks with `onFailure:"block"` for UserPromptSubmit and enumerated PreToolUse guards; require observed native version>=2.1.295. Missing script, exception, invalid JSON, nonzero1 and timeout must block in real/fake runtime fixtures. Older versions are unsupported for mandatory paths; they cannot inherit a silent fail-open contract. Intake hook timeout must exceed the assessment60s plus bounded collection/cleanup overhead (initial90s), while the private controller deadline still bounds the assessment. The console does not dispatch a turn until its protected ingress commit succeeds.

Strict decode rejects duplicate keys, extra properties, nonfinite values, wrong booleans/types and oversized data. Shared request fields, all required:

`{schema_version:1, source_kind:claude|slack, origin:human, session:string, submission_key:string|null, delivery_token:string|null, source_revision:string, parent_request:string|null, actor:string, repository:string, ref:string, text:string}`.

Actor/repository/ref/source values are controller or authenticated adapter bindings, not accepted claims from model text. Claude actor means configured local operator identity, not a claim of remote authentication. Adapter populates fields from observed runtime context; unsupported input fails before private capture.

Exact decision fields, all required:

`{schema_version:1, request_id:string, revision:string, disposition:answer|status|existing_approved|new_feature|changed_requirement|defect|clarify|risk_control|unsupported|blocked, intents:[{kind:enum, summary:string, scope: [relative-path]}], rationale:string, evidence:[{kind:request|spec|plan|task|repository, ref:string, sha256:string}], uncertainty:none|missing_context|ambiguous|conflict, spec:string|null, plan:string|null, task:string|null, next_action:answer|inspect|question|draft|resume|stop|none, blocked_reason:string|null}`.

Model output is an untrusted assessment with the same content fields minus request/binding identifiers. Controller adds observed bindings and rechecks references; it rejects invented evidence, paths outside collected context, self-approval and contradictory disposition/action pairs. Mixed change/continuation requires proposed scope, never resume. Deterministic help/status fixtures bypass the model; fuzzy natural-language answers and ambiguous/change input use Scout. Continue checks durable context and authoritative eligible candidates, asking if zero/multiple qualify.

Exact action fields, all required:

`{schema_version:1, request_id:string, revision:string, decision_sha256:string, kind:proposal_publish|task_enqueue|task_start|implementation_mutation|answer|inspect|question|stop, target:string, target_revision:string, stage:string, paths:[relative-path], principal:string|null, fence:integer|null}`.

Proposal publication requires current draft disposition and writes status draft only in assigned proposal slot; spec approval/configuration paths reject. Task enqueue/start calls existing approved ledger import and routing_contract validators; verify approved spec hash/status/AC IDs, plan/task bindings, unresolved OQs, dependencies, allowed_paths, legacy-characterization and existing pause/claim state before action intent. Use canonical `**AC-N**` identifiers in spec050, preserving all acceptance text, so existing ledger, coordinator and producer readers extract the exact approved AC set without parser changes.

Mutation guard requires bound active task principal/fence and allowed scope, not a mere existing_approved model answer. Draft slots require no implementation approval but have a separate permitted write contract. Missing/stale/foreign decision, revoked policy, changed tracked/untracked relevant content, ref change and edited source produce blocking codes (`binding_invalid`, `stale_decision`, `scope_unapproved`, `claim_invalid`, `intake_unavailable`). Comparison uses bounded exact bytes/file inventories from permitted sources; no candidate script execution to obtain evidence.

### Scout execution and bounds

Configured primary planning CLI executable/model must already be allowed by protected `factory-routing` profile and pins. Existing planning worker command may wrap native invocation with `--safe-mode`; it is not reused as an assessor argv. Add an optional exact `assessment` object to that runtime profile: pinned native executable/script paths and hashes, argv template accepting only model and private input path, observed version/capabilities, clean environment allowlist. Validate strict optional schema and enforce same primary runtime/model; no role/model fallback is introduced. Incomplete assessment object blocks Scout-required requests. Add a dedicated assessment argv contract with tool disablement and a minimal clean environment; no fallback selection and zero automatic retries. Dedicated planning credential is present only in the owned subprocess environment, never candidate cwd/material or reviewer/controller credentials. Run from a private empty assessment directory with no candidate/home config auto-discovery and permitted sanitized content supplied as data. Use the documented native tool/config controls as a candidate assessed argv: `-p --tools "" --disallowedTools "mcp__*" --strict-mcp-config` with a pinned empty MCP file and protected `--settings`; private empty cwd/HOME and restricted settings sources. `--safe-mode` alone leaves built-in tools enabled and cannot establish tool-free execution; it also suppresses project hooks, so do not use it for the console entry. Managed settings still require inspection/proof because command flags do not establish a universal bypass of managed policy. If configured CLI cannot demonstrably disable tools/config discovery or maintain credential separation, entry blocks. No SDK dependency, API billing fallback or new provider is introduced.

Context consists only of request, approved bounded spec/plan/task excerpts and allowlisted relevant tracked repository bytes with paths/digests. Exclude credentials, private feedback neighbors, executable content evaluation and instruction authority from imported text. Tool-free model cannot fetch more context itself. Use `factory-bounded-process.run` and extend it compatibly with an aggregate stdout+stderr cap: existing limit is per stream, insufficient for this contract. Request max20,000 Unicode characters; collected context max500,000 UTF-8 bytes counting serialized envelope and request; assessment stdout+stderr combined max65,536 bytes counting runtime wrapper; timeout60s monotonic from spawn until complete EOF and process exit; zero automatic retry. No silent truncation. Existing cleanup terminates owned groups; cleanup uncertainty yields blocked/unknown, not completed. Stricter protected limits allowed. Reserve assessment before spawn; restart with reserved/running unknown cannot duplicate spawn without explicit reconciliation. Provider quota/error/schema/usage failures produce explicit blocked outcome. No provider tests contact live models.

## Dependencies (new)

No new package, service or MCP dependency. Python stdlib SQLite/json/subprocess plus existing pinned cryptography for hosted encrypted feedback. Existing native CLI is an explicit optional enablement prerequisite; fake pinned native CLI fixtures prove the adapter without model calls. No mandatory VM: reuse existing isolation boundaries for task execution; Scout remains tool-free private context assessment.

## Phasing

### Phase 1 — Complete Claude Code entry and guarded action path

Reserved tasks T-224 and T-226–T-246: core schema/state/identity and pending native provenance, actual console launcher/lightweight/Scout CLI, hooks and action guards, approved ledger/routing integration, bounded process aggregate limit, private neutral example and coverage/runbook. Ship real answer/status/question/draft and eligible resume behavior, tested through installed hooks and actual fake CLI subprocess. Exit: `bash .claude/scripts/test/factory-request-intake.sh` and existing ledger/routing/bounded-process tests pass; missing/stale intake blocks every claimed path. Slack remains explicitly unsupported until phase2, no full-spec completion claim.

### Phase 2 — Existing authenticated Slack bridge and encrypted replay

Reserved T-247–T-252 dependent T-246: hook after current feedback receipt/intake validation; same-store source identity/edit revisions and draft guard; hosted encryption checkpoint roundtrip retaining intake tables. Inspect existing codec validators/projections and modify only explicit additive table validation if necessary. An older supported decoder must retain new tables byte-for-byte across unchanged operations or block incompatible writeback; test preservation, never silently drop state. Hosted feedback uses already approved private flow and no local-only runtime dispatch. Exit: `bash .claude/scripts/test/factory-intake-slack.sh` plus existing Slack/encryption/hosted feedback suites pass; retries, edits, mismatched receipts, unallowlisted actors and checkpoint conflict cannot cause duplicate effects or plaintext exports.

### Phase 3 — Neutral adoption and whole-spec conformance

Reserved T-253–T-257 dependent T-252: adoption packaging/upgrade collisions, all14 AC route matrix, guard inventory and fault/restart/concurrency demonstrations; runbook and sanitized evidence. Exit: `bash .claude/scripts/test/factory-intake-adoption.sh`, all intake suites and required repository validation/verification pass. Each adapter records tested runtime/version; actual native CLI capability not observed remains an explicit enablement prerequisite, not a fabricated passing production claim. Default remains OFF; no source pilot activation or reviewer restart.

Likely edited files: new intake/controller/scout/console scripts and hook pair; `.claude/settings.json`; `factory-ledger.py`, `factory-routing.py`, existing supervisor boundary if needed for task-start guard propagation; `factory-bounded-process.py`; `factory-feedback.py`, `factory-slack-feedback.py`, hosted/encrypted-feedback validator only as needed; existing adoption owned-file inventory; neutral intake config example; docs and three test scripts. Determine actual manifest filename before edits; no unrelated refactoring.

### AC traceability

| AC | Plan and proof |
|---|---|
|1|Hook/Slack adapters, human-origin suppression, inventory; phases1–3 actual ingress tests|
|2|Submission sequence/token and source edits; retries/conflicts/identical text tests|
|3|Strict decision/intents/action matrix; disposition fixtures|
|4|Durable parent/context plus authoritative continuation; ambiguous/mixed/reply fixtures|
|5|Tool-free pinned assessment/private cwd/minimal environment; adversarial fake CLI and no-effects assertions|
|6|Dispatch hooks plus ledger/routing/publication/mutation guard; bypass/opaque Bash failures|
|7|Approved hash/OQ/path validation and draft slot separation; denial/new-scope fixtures|
|8|Defect disposition and legacy/isolation gates; reproduction cannot execute under Scout|
|9|Intent/reconcile transactions, existing claims, encrypted roundtrip; concurrent/restart/lost-ack tests|
|10|Blocked failure codes and separate answer/question contract; timeout/quota/schema/store failures|
|11|Policy/ref/scope/source invalidation, urgent owned cancellation; injection/revocation tests|
|12|Exact aggregate limits/no retries/no lightweight call; boundary/flood/descendant-held EOF tests|
|13|Maintained matrix through real hook and Slack bridge subprocess entry paths|
|14|Disabled neutral packaging/upgrade preservation; adopter end-to-end and no provider invocation|

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
|Native CLI lacks proven tool/config isolation|Scout entry cannot enable|Protected capability prerequisite; fake CLI contract test is not live verification|
|Native callbacks lack human provenance/stable turn identity|Repeated prompts collapse or rerun|Trusted console capture plus one-shot pending correlation; bare native sessions advisory; explicit retry token, never text identity|
|Model confidently invents task/spec authority|Unauthorized dispatch|Deterministic independent ledger and policy validation|
|Opaque command bypass|Unclaimed local effects|Block unrecognized commands on controlled hook paths; document ordinary local edits as outside boundary|
|Lost acknowledgement/concurrent continues|Duplicate task start|Durable intent plus existing task fence; unknown outcomes reconcile|
|Encrypted checkpoint compatibility/4MB bound|State loss or failed writes|Additive tables/preservation checks; retain existing cap, block overflow, existing safe retention only|
|Rollback disables guard but leaves workers|Ungated fallback|Pause protected enabled latch first, cancel/reconcile owned work; never downgrade enabled store silently|

## Rollback

Pause affected entry in protected contract/latch; guard continues rejecting dependent mutation. Reconcile or cancel owned active actions using existing guardian, preserve private evidence and unknown fences. Revert code only after no unresolved operation depends on new tables; keep additive tables, no destructive downgrade. Disabled legacy adopters remain unchanged. Phase2 can disable its bridge while retaining authenticated feedback capture and privacy, but cannot publish/dispatch intake-dependent work. No rollback flips protected review/activation or source pilot authority.

## Observability

Private events contain precise binding/reason/outcome and bounded evidence. Sanitized reports expose disposition, next_action, reason enum, source_kind, assessment_count and aggregate latency/limit failures; no raw text, actor/token, repository excerpts or secret-bearing stderr. Metrics are local private counts, not new telemetry or independent verification. Coverage inventory documents tested action boundaries and advisory surfaces; runbook covers stale decisions, provider failure, ambiguous delivery, unknown effect and pause/reconcile.

## References

- Approved `specs/active/050-request-intake-router.md`.
- ADR proposal `.claude/memory/decisions/0005-private-request-intake-and-guarded-scout-handoff.md`; allocated with the existing adr-new script.
- `.claude/scripts/factory-routing.py`: profile validation, pins, primary routing/native usage, task worker launch boundary.
- `.claude/scripts/factory-ledger.py`: approved task authority and routing_contract; `.claude/scripts/factory-runtime.py` and supervisor: durable claims/fences.
- `.claude/scripts/factory-bounded-process.py`: streaming bounded collection and process-group cleanup.
- `.claude/scripts/factory-slack-feedback.py`, `factory-feedback.py`, `factory-hosted-feedback.py`, `factory-encrypted-feedback.py`: authenticated receipt-bound capture, private SQLite and encrypted checkpoint precedent.
- `.claude/settings.json`, `.claude/hooks/skill-router.sh`: current hook installation and hint-only limitation.
- `.claude/skills/plan/SKILL.md`, `plans/templates/plan.md`: required architecture, independent shipping phases and ADR contract.

### Verified primary documentation and runtime prerequisite

The [official hooks reference](https://code.claude.com/docs/en/hooks#userpromptsubmit) documents generated callbacks alongside submitted prompts; its payload does not supply a human-origin marker. The [failure contract](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails) defaults to continuation and introduces fail-closed onFailure in2.1.295. The [CLI reference](https://code.claude.com/docs/en/cli-reference) documents foreground print, explicit UUID sessions/resume, tool restrictions and settings controls. Documentation supports this proposed adapter; actual pinned-runtime ordering, input delivery and control compatibility require demonstration before enablement. No model invocation was performed for this planning check.

Task decomposition omits redundant standalone cleanup and AC-parser work: existing cleanup is regression-tested with T-224; canonical spec AC formatting needs no code change. IDs T-225 and T-238 are not reserved. All remaining tasks are initially open; partial evidence never establishes full-spec completion.
