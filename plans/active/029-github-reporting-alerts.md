---
id: 029
slug: github-reporting-alerts
status: approved
owner: "@codex"
created: 2029-10-10
updated: 2026-10-16
complexity: M
objective: KR-PLATFORM
service_tier: T2
spec: specs/active/029-github-reporting-alerts.md
---

# GitHub-only alert implementation plan

T-203: extend protected report JSON with a strict optional alert journal, retaining backward-compatible old checkpoints and preserving journal on every hosted digest snapshot. Add exact Slack alert reconciliation, durable pre-send intents, prolonged-incident deduplication and verified recovery. Validate failed GitHub runs independently of event payload. Add a protected default-off scheduled/workflow-run/manual workflow and a labelled notification drill. Prove uncertainty, storage failures and malicious input; merge only after required exact-head gates. Enable monitor and verify drill/recovery/repeat with unchanged digest cursor. Keep the third-party heartbeat explicitly disabled. GitHub/Slack shared outages remain documented limits.


## Approved queue-probe continuation — 2026-10-16

The operator approved proposal Option A. Existing alerts can wait behind the
worker they monitor. Source base is actual protected main6a004bc6d926e16f9b09efe949fbb8b50a843eac;
no unmerged Spec010 diagnostics or separate Spec014 code is imported. ADR0009
records this scheduling change. Existing AC1–3 and ordinary alert serialization
remain; new AC5–8 cover the isolated queue probe. Original created frontmatter is
preserved as historical metadata; updated reflects this actual amendment.

### State and authority boundary

GitState currently permits only README and reports/<64hex>.json data blobs,
loads the selected stream only, and commits with base_tree/nonforce ref updates.
Select SHA256(canonical(["factory-reporting-queue-v1",repository,destination,branch]))
for the queue journal: distinct from existing digest/feedback hash without new
inert paths, executable state, raw SQLite or private message content. The future
Spec014 state scanner already permits this reports namespace; this plan does not
claim its unmerged archive implementation is active. Keep exact protected branch
and policy checks and same factory-reporting environment/writer/Slack secrets.
No key copying or permission increase. Use a queue-specific default-off flag and
separate concurrency group; normal worker and ordinary alert groups stay intact.
The same protected environment may itself block both jobs, which remains visible
as a limitation rather than an independently monitored guarantee.

A missing role journal requires a separately reviewed exact current branch SHA
and explicit bootstrap_existing initialization. Do not treat arbitrary existing
blob, caller hash/cursor or missing journal as origin/reset authority. Journal
shape and role binding are strict and bounded. At most three CAS attempts reload
actual current branch, reconcile idempotent intent/outcome and rebase only the
queue path via base_tree. Preserve ALL other blobs opaquely, including concurrent
reports and encrypted feedback. Never decrypt private feedback to merge state.
Lost acknowledgement requires actual ref/blob reconciliation; absence/unknown
remains blocked. No reconstruction or resend before durable intent reconciliation.

### Bounded observations and delivery

Resolve approved workflow paths/IDs in the same repository and protected default
branch; inspect bounded run/job metadata and known protected health. Default
queue grace60minutes, configurable15–1440minutes with strict type/clock checks.
Use conservative bounded per-invocation page/call/byte controls with explicit
unknown when exhausted; never claim a short filtered list proves no older work.
If authoritative coverage cannot establish healthy, keep unknown/pending and do
not publish recovery. Metadata can establish an eligible reporting run is stalled;
it does NOT establish exact concurrency ownership or a deployment waiting cause.
Optional deployment metadata is read only with existing authority, and failure
stays unknown without adding permissions. Never act on candidate body/text.

Reuse existing exact Slack auth/receipt semantics through a queue-specific fixed
text/metadata adapter. Persist immutable role-bound pending intent first; on
restart reconcile exact bot/channel/key/text/metadata receipt before sending.
Unknown/altered/ambiguous history cannot cause blind resend. Prolonged incident
suppression and exactly one verified recovery use strict journal transitions;
a labelled drill uses run/attempt identity and never represents a real outage.
Capacity is fail-closed, with no pruning or implicit retention change. No job
cancellation, deployment approval, automatic retry of unknown deliveries, ruleset
changes or merge authority are in scope.

### Sequential tasks and phase exits

1. T312: strict role-journal identity/schema; AC6.
2. T313 after312: protected initialization and real Git CAS/restart/lostack opaque
   preservation; AC6. Existing API/protection guards remain required.
3. T314 after313: bounded same-repo stalled-worker/health observations, grace and
   explicit unknown; AC5. No owner/cause inference.
4. T315 after314: durable outbox, exact Slack reconciliation, incident/recovery and
   labelled drill transitions; AC7.
5. T316 after315: separate-group main-only default-off workflow/configuration,
   same environment/credentials and bounded ingress; AC4/5/8.
6. T317 after316: aggregate regressions, source-bound collector, operator setup
   and live-evidence checker; AC1–8 local portions. No local fixture equals live.
7. T318 after317: reviewed-rollout activation and explicitly labelled real drill,
   recovery/repeat/worker-state preservation evidence; AC8. Blocked on rollout and
   exact protected initialization, not on a new provider/VM.

Every implementation task uses actual fail-first evidence. No source code or
workflow implementation is included in this planning checkpoint. Later source
review/normal CI and explicit live verification remain necessary. The receipt
branch and PR111 stay separate. Healthchecks disabled; no Actions-wide outage
coverage or cancelled historical-digest delivery claim.

The labelled live drill proves independently scheduled probe execution plus actual
Slack deduplication/recovery, not an actual concurrent stalled production worker.
The observed old waiting-run detection is metadata/configuration fixture coverage;
no injected drill may be labelled proof of a real queue incident.

### T317 verification decomposition — 2026-10-16

This checkpoint follows actual protected main `2fd54dbc6912af3f2ddfe445793152ba2b8b533e`
integration in `9c329e5`, preserving the queue task/evidence history. Earlier source-base
statements above describe the original planning checkpoint, not an unmerged import.

Routine decomposition within the approved AC8 scope keeps implementation atomic:
T319 depends on T316; T320 depends on T319; T321 depends on T320. Parent T317
now depends on T316 and T321. T318 still depends on T317 and remains blocked on
reviewed rollout and exact initialization. All new tasks are pending; this
checkpoint implements no runtime or workflow changes. No additional operator
permission or credential decision is required.

- **T319:** only an explicitly selected verification drill launches a second
  fresh CLI process with `--drill` under the same protected run/attempt/source.
  The first invocation must succeed before the second starts. First notification
  count one and second count zero establish the local contract. Use the existing
  bounded safe JSON `notifications`/`reconciled` result, not a new proof schema;
  execute the actual workflow shell with a process stub to prove sequencing and
  no second invocation after first failure. The second
  invocation uses the existing exact receipt reconciliation; uncertain history
  blocks rather than authorizing a retry. Normal monitoring still invokes once.
  No caller-selected run identity, cursor or initialization authority is added.
- **T320:** default execution tests the evidence-checker contract offline and
  cannot complete T318. Explicit `--live` uses bounded read-only same-repository
  GitHub run/workflow/source/journal observations. Run IDs and revision inputs are
  selectors to independently read, never authenticated claims. Require reviewed
  protected source/run/attempt and actual journal/effect bindings; inaccessible,
  ambiguous, foreign, truncated or over-budget inputs reject. Pure JSON claims
  cannot establish live authentication. Exact Slack receipt verification remains
  inside the existing reviewed protected Actions queue execution using its
  existing environment token: no locally retrieving that secret, copying it,
  adding a secret path, or pretending the checker independently rereads Slack.
  Any stronger proof needing source changes requires a concrete protected
  verification-only design review before coding it, without arbitrary inputs.
- **T321:** run the actual local aggregate and prepare source-bound AC1–8 evidence
  with the live portion explicitly pending. Document exact current configuration
  names, reviewed queue initialization SHA/flag, initialization-race failure,
  uncertainty/no-resend recovery and existing backend bounds. Document GitHub-wide,
  Slack-wide and common-environment limitations; Healthchecks stays disabled.

Live administrative evidence must separately show the labelled drill, a second
fresh invocation with no duplicate, verified recovery and unchanged repeat. Do
not persist private Slack history or feedback content. Safe selected IDs,
statuses and hashes are administrative observations, not native attestations.
Opaque worker preservation is proved from each actual queue-path publication's
parent/tree delta; unrelated reporting commits may occur between publications,
so equality over the whole observation interval is neither required nor proof.
The live checker must not grant credit from copied fixture/capture booleans.
T318's acceptance command explicitly requires `--live`; missing live selectors or
unverified observations remain blocked, never fall back to the offline self-test.
Completion of T317 establishes local readiness only, not rollout, all-plan
completion, a real stalled-worker incident, or full outage coverage.

### T320 bounded administrative-checker decomposition — 2026-10-16

The reviewed T320 design is split before runtime implementation to keep each
contract atomic. T322 depends on T319; T323 on T322; T324 on T323. Parent T320
now depends on T319 and T324. T321/T317 remain the later local readiness layer;
T318 remains the actual live rollout, with explicit `--live` acceptance. T320 and
all three children are pending. There is no new policy, attestation, credential
or operator decision in this decomposition.

- **T322, protected run/source/log observation:** use a small fixed GitHub.com
  GET-only adapter with the existing authenticated `gh` session, not extracted
  Slack or state-writer secrets. Bound calls and total bytes (128 calls/32 MiB),
  individual JSON responses and selected job logs (2 MiB), timeout and parser
  work. Inputs identify repository and three run IDs/attempts; they are selectors,
  not trusted claims. Require actual completed-success queue workflow runs in the
  same repository/default branch and exact attempts. The clean reviewed local
  checkout SHA, actual current default-branch SHA and all selected run source SHAs
  must match; recheck source at the end and reject drift. Match the unique successful
  monitor job/step and select exact safe JSON results from actual bounded job logs:
  drill [1,0], recovery [1], repeat [0]. Reject extra or duplicate matches. Never
  save raw logs. Offline fixtures test this boundary without claiming live proof.
- **T323, protected journal/publication proof:** authenticate the actual protected
  role journal through existing QueueStore guards, then validate one isolated
  pilot drill/recovery pair, both confirmed, with exact drill run/attempt and
  recovery incident binding and no unresolved/extra effects. Freeze the actual
  state revision, inspect bounded queue-path publication history and validate
  each relevant single-parent transition. Compare each publication's parent/tree
  leaf maps: all other blob paths, modes and hashes remain equal, without reading
  worker/feedback plaintext. Unrelated worker commits between publications are
  allowed. Check ordered nonoverlapping run windows and publication times, strict
  journal transitions and final unchanged role bytes; unrelated state-ref advance
  alone does not invalidate the role proof. Missing history, truncation or exhausted
  capacity rejects. This is isolated-pilot evidence, not generic retained-history
  completeness or Spec014 exclusive-writer provenance.
- **T324, explicit live composition:** compose those two verified boundaries in
  `--live`; default test execution remains offline-contract self-tests. Actual
  GitHub reads are mandatory in live mode; copied capture JSON, `authenticated`
  booleans, fixture results or unavailable data cannot supply completion. Emit
  only safe selected IDs, revisions, hashes and counts, with an administrative
  observation label and no raw logs/private messages. The normal CLI exposes no
  arbitrary API host, endpoint, fixture transport or input capture authority.
  A final source/role consistency read fails on relevant drift. T318 may consume
  this live administrative result only after its separately reviewed rollout.

The protected reviewed Actions job already performs exact Slack checks using its
existing environment token. The checker attributes those checks to verified
source plus actual successful job results; it does not independently reread Slack
and does not retrieve or copy its token. The recovery journal schema has no
producer run ID, so attribution is administrative correlation of protected
source/logs, ordered publication transitions and nonoverlapping execution windows,
not cryptographic provenance. The isolated one-pair/no-overlap restriction makes
that limitation explicit; ambiguous observations fail rather than infer a match.
If actual API authorization cannot read source, state protections/journal or job
logs, live acceptance stays blocked without adding credentials or permissions.
Any stronger source capture or protected verification-only mode requires its own
concrete review before implementation. No generalized evidence framework is added.

### Disabled auxiliary workflows — 2026-10-16

The operator manually disabled Issue lifecycle (284902557), Lighthouse CI
(284902562), and E2E on Preview Deploy (284902548) because they kept executing.
GitHub workflow metadata confirmed all three as `disabled_manually` on this date.
This disables only these three workflows; the AI software factory improvement
plan remains active and implementation continues. Keep their disabled state
unless the operator authorizes reactivation. Their execution supplies no current lifecycle,
Lighthouse, or preview E2E evidence. Diagnose triggers and applicability before
proposing reactivation; do not interpret their disabled state as permission to weaken
required checks or remove applicable verification obligations.

### T321 local aggregate and operator readiness — 2026-10-16

The aggregate runs the existing journal, real Git CAS, observer, delivery,
protected Actions ingress, offline live-checker contract, workflow baseline,
ordinary alerts, watchdog, hosted digest, attachments and policy regressions.
Source/journal proof suites run once through the offline live-checker script.
Documentation records exact variable names and separates repository/organization
job-if gates from main-only environment configuration available after job start.
Existing worker settings remain intact; queue enablement is still default off.

Local AC1–8 contract results do not complete AC8's live rollout portion. T318 is
PENDING: reviewed source/configuration, exact initialization, actual labelled drill,
fresh-process duplicate suppression, recovery/repeat and per-publication opaque
preservation remain required. No source settings, credentials, actual sends or
API authorization have been changed by this task. Healthchecks stays disabled;
the factory plan stays active despite the three disabled auxiliary workflows above.

The final published collector bundle must bind the committed T321 source as an
ancestor, so it is prepared after this implementation commit. Retain actual
aggregate output and task GREEN, then rerun the existing AC-tagged commands and
smoke at that committed source. Record local-contract scope and live PENDING;
never turn offline fixture results into a live activation certificate. T317 is
still the subsequent aggregate readiness checkpoint, and T318 remains separate.

### T325 actual Actions log-format correction — 2026-10-16

Independent review of ceae9f5 and an actual public Actions job showed that the
strict JSON selector rejects timestamped `[command]` runner lines before reaching
valid safe CLI results. T325 recognizes only that known timestamped control
marker; malformed/extra/duplicate result JSON, arrays, unprefixed JSON and unknown
bracket lines still reject. The first T317 collector attempt is retained as
local contributions with changes requested, not source ready for merge. T317 now
depends on this repair and fresh review/evidence; live T318 remains pending.

## T318 actual bounded pilot acceptance — 2026-10-16

Reviewed source91839087a769bd45670df5b84cb96993bcb97d42 is merged. The exact
reviewed queue initialization was performed, then initialize=false restored.
Actual protected drill38850566089a1 produced[1,0] across fresh CLI processes,
recovery38850688638a1 produced[1], and repeat38850871872a1 produced[0]. The explicit
--live checker reran successfully against actual GitHub metadata/logs and the
protected role journal, with five publication parent/tree opaque-preservation
checks. docs/activation/2026-10-16-queue-probe/README.md records safe source-bound
observations. Earlier live-pending entries describe their historical checkpoints;
T318 now closes the actual AC8 pilot portion without rewriting T317 local records.

This is bounded administrative correlation, not native attestation, independent
local Slack readback, actual stalled-worker proof or global-history certification.
One isolated pair, ordered nonoverlap windows,24 commits and1024 tree entries
remain explicit checker bounds. Per-adopter rollout, same-environment/GitHub/Slack
outage limits remain; Healthchecks stays disabled. Factory authority/merge mode
remain off. This documentary verification introduced no code/settings/credential
changes, sends or dispatches.

## Approved historical operational-proof replay — 2026-10-17

The operator approved option A; public upload is separately pending. Preserve the original current-source live checker unchanged. Supporting work belongs to T318's publication acceptance repair; it does not redefine the original16-task objective.

1. T336 (AC-9): implement a strict distinct historical-queue-completion record and native certificate/run/source authentication. Scope: .claude/scripts/factory-operational-proof.py and test/factory-operational-proof.sh. No writer, live workflow or delivery/task authority. Strict TDD, malformed/forged/source/profile/signature negatives; local injected verifier seams must be labelled fixtures.
2. T337 (AC-9): protected-main historical observation producer and durable authenticated record/CAS storage, using existing reporting state and native signing architecture. Scope additionally permits .github/workflows/factory-operational-proof.yml, .github/workflows/factory-operational-proof-retain.yml, focused operational-producer/state tests, factory/operational-proof-profiles.json (empty/inactive until separately reviewed exact producer/source registration), and adopter/activation documentation. Independently re-read original native source/run/job/log and immutable journal lineage; no candidate-owned summary fallback. Preserve actual historical times, opaque feedback and non-forced state. Native signing/write permissions remain main-only and default-off until reviewed bootstrap.
3. T338 (AC-9): bounded read-only PR replay consumer and acceptance integration. Scope additionally permits existing evidence-gate read permissions only as required, operational replay tests and TASKS acceptance declarations. Authenticate trusted producer/profile/revocation and exact purpose. No protected variables/secrets in PR execution. Reject operational records at delivery/current-task/merge/readiness boundaries. Preserve current-source live checks.
4. T339 (AC-9/AC-8): reviewed bootstrap, genuine authenticated original-source record and real read-only PR acceptance. Defer T318 source-publication closure until this proof exists; retain the genuine original administrative observation. Existing exact-head maintenance/profile/cutover decisions remain in force. Full actual publication checks are required; never replace a source, bypass checks or fabricate a native pass.

Dependencies: T336→T337→T338→T339→T318 publication closeout. T179's portable PR selector repair is already separately verified. No repeated1001-history producer is required for this typed operational-proof repair. The original T180 and T222 sequence remains unchanged.

Operational trust integration: T336 accepts an explicitly expected profile only as an internal verification primitive. T338 must obtain the real active/revocation profile from independently authenticated protected-main configuration, never from a candidate record or candidate-owned registry. Retain a distinct registry rather than widening delivery producer roles in factory/policy.json. Use the existing domain-separated reports/<role-sha256>.json opaque sibling for retention where compatible; do not add a new state-root or change delivery archive schemas. PR access adds only demonstrated read requirements; a retained Sigstore bundle can be verified without forwarding the reporting/merge credential. No independent Slack readback or global-history claim is inferred from the original bounded administrative queue observation.

Producer sequencing constraint: a record cannot authenticate its own still-running workflow as a completed producer. The manual protected signing workflow finishes and uploads bounded record/bundle artifacts first. A separately protected `workflow_run: completed` retainer authenticates the successful source run, certificate/record and active profile before existing App-scoped CAS storage. The retainer has no signing role; the signer has no state-write credential. Both stay default-off/main-only. Consumer acceptance and real completion cannot be inferred from a merely running producer. Artifact, identity, signature, source/revocation or uncertain-write failures remain blocked.
