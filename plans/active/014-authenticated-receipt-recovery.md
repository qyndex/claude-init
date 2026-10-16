---
id: 014
slug: authenticated-receipt-recovery
spec: specs/active/014-authenticated-receipt-recovery.md
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-16
---

# Authenticated receipt and worker recovery

Authenticate coordinator artifacts through GitHub API run/workflow metadata, historical source pins, archive digest and actual merged PR identity. Read the policy at the pinned run revision and bind the task mapping/spec hash. Write delivery and provenance in one local transaction; never accept a candidate-provided file as receipt input. Pin the coordinator checkout to the Actions source SHA.

Wrap the actual worker in a separate guardian owning the worker process group and inherited resource descriptors. The supervisor alone owns the liveness pipe writer. EOF after supervisor death triggers bounded worker cleanup before fencing/requeue; cleanup failure blocks recovery. Preserve an attempt outcome and uncertain outbox actions. Test live disposable process trees and fake authenticated GitHub responses with real ZIP digests.

The initial receipt contract accepts one explicitly approved task per delivery. Automated fixtures cover artifact/source/PR negatives, immutable replay, a real SIGKILL process tree, duplicate exclusion and fenced retry. Live receipt ingestion and simultaneous guardian death remain separate readiness work.

## Approved durable receipt continuation — 2026-10-16

Approved option A and retention A extend AC-1/2 and add AC-5–8. Guardian AC-3/4 and existing T-187 remain unchanged. No runtime implementation or activation is claimed by this planning change.

### Architecture and authority

Load fixed `factory/receipt-trust.json` separately from `factory/policy.json`; profiles never hash themselves and never mutate canonical source policy. Each profile has unique immutable ID, active/revoked state, exact canonical source-policy digest and complete exact emitter runtime closure (merge workflow, coordinator, activation preflight, evidence contract, provenance and bounded helpers). Fetch immutable run-head source bytes as bounded data after checking GitHub repository/workflow/event/default branch/run attempt/success. Reject missing dependencies and unknown schema fields. Explicit legacy source mode has no mismatch fallback. Both modes enforce current revocations; retained reported facts acquire a withdrawn-trust annotation instead of deletion. Current task/spec checks stay separate from historical merge-time projection.

Use the existing state branch/protected writer, not a new service. Append content-addressed compact proof records and deduplicated policy/spec/runtime material plus segmented indices; retain original bounded receipt artifact bytes and origin metadata sufficient for reconstruction. The bootstrap explicitly binds repository, branch and coverage origin. Writer trust is inherited from reviewed GitHub API authentication and the protected writer; arbitrary copied JSON/blob digests are insufficient origin proof. Protect the new profile and archive writer under existing authority paths. No additional workflow signing permissions.

### Data and bounded API contracts

Profile schema version 1: repository, profiles (id/status/policy_sha256/runtime hashes), explicit legacy revisions. Archive schema version 1: repository, origin, record identity run_id/attempt/artifact_id, archive/receipt digest, profile identity/hash, source SHA, policy/spec/runtime material references, authentication facts and immutable delivery. Discovery schema version 1: audited coverage boundary, per-run attempts, unresolved journal, continuation cursor, last complete reconciliation and coverage status/reason. APIs remain GitHub GET for run/source/artifact reads and existing non-forced branch CAS for writes; reject identity conflicts before projection. No new package dependency.

Conservative fail-closed implementation budgets: receipt ZIP 4 MiB, individual retained record 1 MiB, shared source object 1 MiB, index segment 256 records/1 MiB, per invocation 100 run pages of 100 and 100 new artifacts, aggregate downloaded bytes 32 MiB. Validate decompressed size/member counts using existing bounded archive conventions. Reaching any limit persists a resumable unresolved boundary and reports incomplete coverage; never prune or imply success. Budgets limit each operation, not lifetime history. Append additional bounded segments indefinitely. Exhausted storage/write errors block coverage claims and alert through existing reporting.

Discovery combines existing protected coordinator completion signals with paginated periodic reconciliation. Persist every observed run/attempt needing resolution, including failed/in-progress runs subject to later reruns. Revisit unresolved attempts before moving completeness boundary; recognize new attempts for old run IDs. Use overlapping created-time reconciliation only as optimization, never as sole completeness evidence. Retain non-delivery outcomes after authenticating/classifying their receipt so expired shadows do not block forever. Cold start/backfill is restartable; absent artifacts before approved origin are labelled outside coverage, absent required artifacts after origin are explicit gaps. An operator-reviewed initial boundary is required before first unattended merge; no automatic origin reset.

### Sequential phases and exit criteria

1. Content trust: strict profile parsing, immutable source equivalence, revocation/current-task separation; AC-1/2/5 fixture tests reject all authority changes and accept two ordinary source commits. Existing receipt behavior remains explicit legacy mode.
2. Retained proof: bounded archive authentication, origin/bootstrap and append-only CAS preservation; AC-6/8 tests reconstruct after artifact expiry and reject tampering/conflicts/private leakage.
3. Complete discovery: resumable indices, reruns/late visibility/backfill and budget exhaustion; AC-7 tests exceed 1,000 historical runs with bounded new work, restart and expose missing history.
4. Integration: hosted digest and alerts use profiles/archive/discovery; docs/preflight distinguish local completion from actual retained-proof/CAS/coverage activation. Cross-layer tests preserve guardian AC-3/4. No live activation in implementation tasks.

### Risks, rollback and observability

Archive writer compromise remains a distinct trust risk: document it, protect writer/profile paths and never describe unsigned retained JSON as portable cryptographic proof. Revocation applies at read time and retains immutable withdrawn facts. CAS conflicts re-read/reconcile at most three attempts then fail closed, preserving encrypted envelopes byte-for-byte. Privacy/store mismatch blocks writes. Roll back to paused reporting/merge-disabled operation; explicit legacy imports remain available for audited history, not automatic fallback. Never delete retained records during rollback. Emit bounded counts of scanned/pending/authenticated/revoked records, completeness reason, CAS retries and archive bytes; exclude tokens, provider output, Slack plaintext and private payloads from public logs.

### Verification and references

Every following task requires fail-first behavioral fixtures and actual acceptance before completion. No current implementation PASS is asserted. References: `docs/FACTORY-DIGEST.md` retained-proof limitation; `.claude/scripts/factory-receipts.py`; `.claude/scripts/factory-git-state.py`; `.claude/scripts/factory-coordinator.py`; ADR-0007 `.claude/memory/decisions/0007-content-approved-durable-delivery-receipts.md`. Operator approval was communicated in this session on 2026-10-16; retention is indefinite compact proof and 90-day detailed Actions artifacts.

### Task DAG, scope and acceptance mapping

Execute sequentially T-275 → T-276 → T-277 → T-278 (phase 1), T-279 → T-280 → T-281 → T-282 → T-283 (phase 2), T-284 → T-285 → T-293 → T-294 → T-295 → T-286 → T-287 (phase 3), T-288 → T-289 → T-290 (phase 4). T-275–285 are locally implemented with retained evidence; T-293–295 and T-286–290 remain pending. T-286 is an aggregate acceptance gate and depends explicitly on all three child tasks. Pending named acceptance scripts describe future checks, not current PASS. No live archive activation is implied.

Scope: `factory/receipt-trust.json`; `.claude/scripts/factory-receipts.py`, `factory-receipt-archive.py`, `factory-receipt-discovery.py`, `factory-git-state.py`, `factory-preflight.py`; the two existing reporting workflows; the nineteen `test/factory-receipt-*.sh` acceptance scripts listed in TASKS; `docs/FACTORY-DIGEST.md` and `docs/FACTORY-ADOPTER-SETUP.md`. Protect fixed new profile and archive-writer paths. Extend current data-only allowlist explicitly from README/reports to exact bounded archive object/index/discovery paths; never allow arbitrary executable paths. Existing state and encrypted feedback files survive every CAS unchanged.

AC mapping: AC-1 T-275/276/279; AC-2 T-278/283; AC-3/4 unchanged completed T-187 plus regression T-290; AC-5 T-277; AC-6 T-279/280/282/283; AC-7 T-284/285/293/294/295/286/287; AC-8 T-281/282/283/288/289/290. Final integration acceptance runs each constituent receipt test and existing guardian/recovery suites; it cannot mark earlier tasks done on declarations alone. Pending scripts must behaviorally cover malformed schemas, dependency omissions, revocation, real CAS conflict/restart, private fixture rejection and no runtime task mutation.

Public Git history cannot provide deletion guarantees; only approved public facts may be archived there indefinitely. Indefinite means no automatic compact-proof pruning. Detailed Actions retention remains 90 days. First unattended merge remains blocked until reviewed coverage bootstrap and actual retained-proof/CAS verification; profile metadata alone is insufficient. Live application of that bootstrap remains an operator activation gate, not permission to fabricate historical coverage.

### Transitional T-278 boundary (not end-to-end readiness)

T-278 enforces revocation when the protected external document is supplied and adds reporting-only withdrawn-trust annotation. Existing pre-profile callers temporarily retain legacy compatibility without the document. T-288 must remove this omission path at CLI/ingest/project/report-loader integration: require the fixed protected document and explicit mode everywhere profiles are enabled, with no automatic fallback. Until then end-to-end revocation is not ready and the empty default profile stays disabled. Archive integration must independently revalidate retained identity/material and protected writer origin before annotation; copied JSON never becomes proof through the annotation helper.

### T-280 protected-writer capability and pending activation

Bootstrap origin requires an explicitly reviewed approval from protected authority, exact repository ID/name/privacy and nondefault state branch, exact bootstrap commit/tree, coverage origin and settled current protection hashes. The supported capability model is one update-only ruleset whose sole bypass actor is the exact approved existing dedicated GitHub App, plus separate rewrite/deletion policies with no bypass. Source authors, blob hashes and an authenticated flag cannot establish exclusive origin. Bound each verification to 256 first-parent commits, 1024 entries per tree, 1 MiB per API response and 32 MiB aggregate; a bound is a visible gap requiring resumable continuation, not a successful reset. T-281 alone may extend current data-only paths.

Existing reporting uses `FACTORY_REPORTING_STATE_TOKEN` and is not certified as this exclusive App writer. Therefore the current live state remains unsupported for trusted archive bootstrap until a concrete operator-reviewed capability/cutover package proves the updater, current policy hashes, writer protection and coverage boundary. This plan does not authorize reading token values, silently migrating credentials, applying update restrictions or breaking existing feedback/reporting. No new credential/signing permission is implied. Coverage before the reviewed origin stays labelled outside coverage; unavailable required history at/after origin remains an explicit gap. Bootstrap alone cannot complete runtime tasks or enable unattended merging.

T-284 must persist and validate a previously authenticated chain anchor and resumable per-invocation traversal cursor: 256 is a work budget, not a replacement lifetime commit cliff. T-281 and later index/discovery tasks must segment retained objects and make progress within tree/object/page bounds, or expose an explicit capacity gap without claiming indefinite complete coverage. Until that integration, the bootstrap validator may refuse long chains; it does not certify indefinite operation. Live bootstrap anchors the reviewed actual current state before first unattended merge, never retrospectively asserts missing historical coverage.

### T-281 exact inert namespaces and bounded traversal contract

A shared neutral `.claude/scripts/factory-state-paths.py` defines both readers' allowlist: existing README/reports, sharded `receipt-archive/{objects,materials}/<two-hex>/<matching-64-hex>.json`, `receipt-archive/index/<64-hex-stream>/<12-digit-segment>.json`, and `receipt-archive/discovery/<64-hex-stream>.json`. Only known directories and 100644 JSON blobs are permitted; archive entries are bounded to 1 MiB. Existing report/encrypted-feedback blobs remain byte-identical when unrelated reporting checkpoints update. Index segments have exact repository/stream/number, 1–256 records and 1 MiB maximum, exact positive run/attempt/artifact identities and unique content hashes. T-282 must validate actual encoded object size before writing; conservative capacity failures never truncate material.

Immutable nonrecursive subtree scanning returns explicit partial entries/cursor/completeness with a per-invocation page/byte budget. Continuation is bound to the same root tree; cursors require independently authenticated protected checkpoint origin before reuse. A cursor/root hash alone is not origin proof. T-280 bootstrap uses this walker and fails when continuation is required; T-284 supplies durable authenticated continuation/anchors. The former 1024 lifetime entry cap is removed; tests traverse 1600 objects over separate one-page invocations. Truncated or oversized individual directories/frontiers remain explicit capacity gaps, never hidden omissions or deletion. Long-term shard/index expansion must retain this fail-closed contract; no indefinite complete-coverage claim is made by path acceptance alone. Existing GitState recursive reads still reject truncated listings.

The new protected factory-* helper is a reviewed writer dependency. Keep preflight runtime imports unchanged in T-289 unless the full emitter closure/profile tests are explicitly expanded; never omit a transitive pin silently. Archive CAS writes and trustworthy archive projection remain pending. Exclusive writer App identity stays generic/operator-reviewed: reuse of a privileged merge App versus a separate contents-only writer App is a pending live capability/credential decision. No private key copying, PAT migration, reporting restriction or existing workflow disablement is implicitly authorized by this source change.

The legacy GitState reporting protection guard still rejects bypass actors. Any eventual App-only update policy must be integrated through the exact reviewed archive capability gate before live cutover; do not relax generic legacy policy checks to trust arbitrary Apps. Existing reporting remains untouched until that concrete cutover is reviewed.

T-282/T-288 must replace or stream the legacy GitState recursive whole-tree constructor path when archive mode is enabled: its current response bound would otherwise eventually block reporting as retained archive data grows. Reuse authenticated append-chain/incremental verified anchors and checked scanner cursors rather than retaining an unbounded full path inventory. Persisted cursors must originate from checked scanner output inside an authenticated protected checkpoint; caller-provided root/pending JSON is never origin proof.

### T-282 atomic authenticated append and identity protocol

The archive stream is fixed per repository as SHA256(canonical `['factory-receipt-archive-v1', repository]`), independent of Slack/report destination. Execution identity is repository/stream/run/attempt; a changed artifact ID cannot evade its existing identity entry. Add exact inert `receipt-archive/index/<stream>/identities/<two-hex>/<matching-64-identity>.json` lookup paths with strict payload identity and content-addressed record reference. Numeric index paths are sharded as `<stream>/<first3>/<next3>/<next3>/<12-digit-segment>.json`, bounding each sequence directory to1000 children rather than introducing an8k-file directory cliff. Prefix digits must match the full sequence. Each current segment contains one immutable record; the256-record contract remains an upper bound. No flat/generic index paths are accepted.

The appender uses separate authenticated source and state API adapters. Authenticate incoming proof with build_record, then verify the reviewed exclusive writer/bootstrap capability before every observed-base attempt. Read only bounded fixed paths/subtrees; never invoke the legacy recursive GitState constructor. Put content-addressed record/material objects, immutable execution/sequence indices and derived discovery counts in a single tree based on observed base_tree and one unique single-parent commit. Advance the branch only through non-forced CAS; on conflict/lost acknowledgement re-read and reconcile, at most three attempts. Never overwrite a differing immutable identity/content or reset a missing journal over an existing stream. Preserve all unrelated report/feedback blobs through base_tree. Discovery progress advances only with the same atomic proof commit; no runtime task transitions.

Current bootstrap checks still require a complete bounded origin proof. Long ancestry/scan bounds fail closed pending T-284 authenticated incremental anchors; T-282 does not make partial scanner cursors trustworthy or certify indefinite complete coverage. Reporting workflow/App/PAT cutover remains a separate concrete operator review. Source preparation neither copies credentials nor relaxes the legacy no-bypass policy guard. Existing authenticated snapshot differences remain immutable conflicts; no automatic rewriting of retained trust evidence is permitted.

T-282 also binds source and store repository IDs/privacy (same-name foreign repositories reject), checks current reviewed writer policy hashes again before ref update, and caps shared checked API observations at32MiB with conservative source-file accounting. Provider adapters retain their own transport controls. A lost ref acknowledgement followed by unavailable authoritative observation remains explicitly uncertain; a fresh process reconciles the retained identity before reporting success. Actual disposable Git tests exercise two archive writers, report-writer races, max-three conflicts and lost acknowledgement/restart. No global archive readiness gate applies to merge-disabled shadow: durable profile/writer/coverage is required before merge-enabled unattended delivery, while existing reporting/feedback stays operational until separately reviewed cutover. Selected profile failures must never fall back to legacy mode.

### T-283 retained reporting reconstruction

`project_retained` authenticates the reviewed bootstrap and exclusive writer chain before reading any retained delivery. It binds discovery/segmented index/execution identity to each exact content-addressed record, original receipt ZIP, source policy/spec/runtime and selected trust material; a second origin observation must remain unchanged before SQLite writes. Source Actions artifacts are never fetched on this reconstruction path. Current protected trust marks a revoked or removed profile as withdrawn while preserving immutable merge-time delivery/provenance facts. The projection only inserts reporting facts and updates a separate trust annotation; it cannot create or transition runtime tasks. Missing material, conflicting facts, privacy mismatch or untrusted origin rejects the entire observation before projection; existing reporting facts cannot silently disappear.

This is a bounded callable reconstruction primitive, not a live archive activation or complete-history claim. At most 128 segments and 32 MiB of checked observations are processed per invocation; exhaustion is an explicit gap. T-284 must integrate authenticated resumable chain/discovery anchors rather than treating these as lifetime limits. T-288 still must wire fixed protected trust inputs into reporting loaders and expose trust annotations in reports; the existing live reporting/feedback path stays unchanged until reviewed cutover. No credentials, protections, workflow permissions or live state are changed by T-283.

Archive append accepts an explicit reviewed `legacy` mode as well as the default selected `profile` mode. Both require a protected external trust document; exact legacy revision imports cannot bypass matching revoked profiles, and profile mismatch never falls back to legacy. Retained legacy facts survive artifact expiry with the same current withdrawn-trust annotation rules.

### T-284 protected bounded progress foundation

A separate exact `receipt-archive/progress/<64-hex-stream>.json` inert blob preserves the existing append discovery journal unchanged. The checkpoint binds repository ID/name/privacy, branch, reviewed bootstrap/tree/coverage, approval digest, exact protection hashes/App writer, receipt workflow and page size. It stores the last fully verified protected head/tree, a frozen immutable tree scan frontier produced by the checked scanner, and a constant-size pending-watch manifest. Immutable 1–128-row watch segments use exact `receipt-archive/pending/<stream>/<3>/<3>/<3>/<12-digit-number>.json` paths; fixed `pending/<stream>/identities/<2-hex>/<matching-64-hex>.json` lookup binds every run/attempt/source to its segment. There is no global 128-unresolved lifetime cap. Only actual protected Git state can supply an existing checkpoint; no caller cursor/checkpoint argument is accepted, and a pre-bootstrap progress blob requires an explicit reviewed import rather than automatic trust. Both saved anchor and frozen view are checked on the protected ancestry. A completed tree scan does not establish delivery or history coverage.

Each CAS observation reads at most one source page (1–100 rows) and 1–10 frozen tree pages, preparing one new watch segment of at most 100 identities. An invocation has at most three CAS observations, sharing 32 MiB checked observations and 4,096 actual state API calls (plus at most three source page requests). All observed rows remain pending until T-285 authenticates outcomes. Immutable run/attempt/source conflicts fail; the coverage frontier never advances from the reviewed origin. Fetch pagination may advance only while every unresolved observation is retained in the atomic checkpoint; per-page/encoded/API budget failure leaves the old cursor intact. New segments and identity lookups commit atomically with that cursor; duplicate immutable identities revalidate their retained segment. An empty/short page cannot imply completeness because filtered GitHub run queries may cap at 1,000. Non-forced max-three CAS reconciliation preserves reports, encrypted feedback, archive/index bytes and concurrent progress; a lost acknowledgement is reconciled from actual protected bytes before any further fetch-page advance.

This foundation intentionally still requires full bounded bootstrap authentication. Its own checked in-memory tree frontier may continue through at most ten 100-page windows, sharing a 2,048-read/32 MiB invocation budget across every ancestry commit; it never accepts caller partial origin. T-286–288 must integrate trusted resumable ancestry anchors and retained projection windows before claiming unattended capacity: remove repeated 256-commit origin walks and the 128-segment projection ceiling using protected checkpoints whose provenance is independently established. A partial caller JSON/hash or unfinished tree scan must never be upgraded into a trusted anchor. Freeze an exact head/tree and required coverage interval, authenticate bounded record windows, and persist the verified window references/results atomically in exact inert protected index segments. Fresh hosted SQLite must resume those protected windows and reconstruct the requested report interval from verified retained facts; it must not discard the saved frontier and restart at segment zero on every invocation. Introduce any additional read-window path/schema explicitly, preserve original facts, reapply current revocation at read time, and keep reports incomplete until every required window and unresolved attempt is reconciled. T-286 must partition/reconcile source listing to defeat the filtered-query 1,000 cap; `--paginate` alone is insufficient. Until those later tasks pass, this journal is usable progress, never complete engineering proof or permission to enable autonomous merge.

### T-285 cold watch, reruns and source-authenticated outcomes

Protected checkpoint schema 3 adds a cold segment/row cursor and a frozen-cycle overlap cursor. Known exact schema1/2 checkpoints migrate only after protected-origin verification, preserving all immutable watch rows and keeping coverage false. Each reconciliation visits at most 16 rows in one retained segment, cycles without dropping failed/skipped/running attempts and asks for the latest metadata of each old run ID. New attempts are appended through the same immutable watch identity protocol; old attempt metadata is fetched explicitly when necessary. Discovery also revisits one page from a frozen finite prior-page prefix alongside its next fetch page, catching delayed older IDs without a creation-time-only watermark. At most two source pages/200 newly observed identities per observation are split into 128-row watch segments; three observations share the existing 4,096-call/32MiB budget. Full filtered-query partition/completeness remains T-286.

A retained execution lookup validates protected origin, exact identity/discovery/segment/record/material binding before any Actions artifact access. Previously retained delivery facts remain usable after artifact expiry and acquire current withdrawn-trust annotation when approval changes; they never grant current task credit. An unavailable API or missing artifact cannot create a delivery. New positive delivery archival still calls the full original live receipt/PR authentication and atomic archive builder, then resumes from the actual retained index. No SQLite/task lifecycle call exists on this reconciliation path.

Derived outcome blobs use only exact `receipt-archive/outcomes/<stream>/<two-hex>/<matching-64-hex>.json` paths, keyed by run/attempt and canonical external-trust/mode epoch. They retain bounded exact approved source-policy/runtime bytes. Only independently authenticated source with `merge_enabled:false`, or a successful exact-source digest/origin-verified `merged:false` receipt, can be labelled non-delivery. A failed merge-capable run remains watchable even if its current attempt is terminal. Cached non-delivery proof is revalidated offline under the current epoch, while latest attempt metadata is still checked. Revocation/profile mismatch has no legacy fallback; a later reviewed profile or explicit legacy import changes the epoch and revisits prior unapproved observations. No raw provider log, Slack plaintext or unrelated API payload enters these public records.

Copied bootstrap data is not an authenticated import: discovery/index/segment/record/material and outcome capsules present at bootstrap are rejected absent an explicit reviewed import protocol. Existing report and encrypted-feedback bytes remain untouched. The current bootstrap implementation still requires full protection metadata and complete bounded ancestry/tree validation; GitHub App read-only omission of bypass metadata is an outstanding activation blocker, not permission to relax validation. The separately proposed operator approval model is not implemented here. T-286–288 still must establish complete partitions, resumable verified ancestry/projection windows and fresh-hosted SQLite progress; no complete unattended coverage is claimed by these outcomes.

### T-286 decomposition — planning only

The coordinator approved routine decomposition within the existing operator-approved Spec014 scope after inspecting the three independent restartability obligations. T-292 is reserved for separate protection-metadata work; IDs293–295 were checked unused in active/archive ledgers and appended under the sanctioned task lock. No child is marked done and no implementation or live setting changes accompany this planning update.

1. **T-293 (after285): origin and scan windows.** Independently bind repository ID/name/privacy, exact branch/ref/head/tree, reviewed bootstrap/tree/origin and unchanged settled exclusive-App/no-rewrite protection. Investigate GitHub's documented compare response only as an ancestry assist: bind the exact requested immutable head separately, validate actual base/merge-base/status metadata, and never treat truncated files/commits lists as proof of every intermediate commit. Preserve single-parent ancestry and inert-tree checks through bounded protected windows, not a weaker all-history trust rule. Persist only checked scanner/ancestry progress under independently authenticated origin; a copied checkpoint/hash cannot authorize itself. Fresh calls must progress beyond256 commits and large trees without restarting at bootstrap, while partial windows remain incomplete. Copied bootstrap index/discovery/record/material/outcome capsules remain denied.
2. **T-294 (after293): partitioned cold start/backfill.** Freeze the required origin/time interval and persist bounded interval/page/identity reconciliation under that protected origin. Split source-created time partitions before relying on filtered listing's1,000-result cap; verify all partition counts/pages/identities, expose late visibility or count changes as unresolved work, and report an explicit gap if the smallest supported dense bucket still exceeds the cap. Empty/short pages or `--paginate` cannot imply coverage. Keep cold watched reruns/trust epochs and all original facts, preserve CAS/restart semantics, and never advance completeness past unavailable required history.
3. **T-295 (after294): retained projection/read windows.** Freeze exact protected head/tree and required report interval; persist bounded verified record-window references/results in explicit inert paths with strict schemas and CAS. Fresh hosted SQLite instances must reconstruct/resume the requested interval from those protected windows across invocations, rechecking every source/material binding and current revocation rather than starting at segment zero. Partial windows never publish a complete report or mutate tasks; conflicts, private/public mismatch, copied origin and missing proof fail atomically. Demonstrate progress beyond128 retained segments without a lifetime cliff or automatic pruning.

T-286's original `factory-receipt-coverage.sh` remains the final aggregate gate after all three children. Its result must cover source partitions, required-history gaps, actual protected ancestry/scan progress, fresh-process retained projections, unresolved attempts and current revocation together. T-287 then verifies beyond1,000 histories; T-288–290 integration/readiness/guardian contracts remain unchanged. No new vendor, credential, signing permission, policy-visibility approval model, source-profile fallback or live cutover is authorized by decomposition. If an individual child still exceeds its atomic scope, decompose again before accumulating unrelated source changes.

Primary API contracts inspected: [GitHub compare commits](https://docs.github.com/en/rest/commits/commits#compare-two-commits) and [workflow runs](https://docs.github.com/en/rest/actions/workflow-runs). Compare metadata and exact request identity are distinct from paginated commit/file completeness; filtered run discovery has a documented cap and requires partition reconciliation.

### T-293 local origin-window foundation — 2026-10-16

`advance_origin` is a separate bounded scanner, not a replacement for the existing
strict bootstrap gate. It reestablishes exact repository/privacy/default-branch,
settled exclusive App writer/no-rewrite protection and reviewed bootstrap on every
invocation. Immutable compare metadata establishes ancestry only; every intervening
single-parent edge and inert tree still must be checked before a frozen snapshot
is complete. Neither files nor a truncated commit list establishes completeness.

The fixed `receipt-archive/origin/<repository-stream>.json` checkpoint is inert
100644 data. Resume is loaded only from the actual protected branch, absent at the
reviewed bootstrap, bound to the exact approval/repository/branch/frozen head/tree.
The actual path-history publication must have one parent equal to its recorded
observed parent; immutable tree comparisons prove that publication changed only
the checkpoint path. Its persisted checked-window facts derive from the approved
exclusive App writer, not a JSON hash or caller-supplied cursor. Writer credential
compromise remains the existing explicit protected-writer risk, not new portable
signature trust. The scanner accepts no external resume object.

Per invocation, at most32commit windows with up to8tree pages each share2048API
observations/32MiB across up to3CAS retries. Partial tree cursors resume only under
that protected publication origin. Nonforce base_tree updates preserve concurrent
reports and encrypted feedback; uncertain acknowledgements require reconciliation.
A complete frozen view still exposes newer suffixes as pending. A later invocation
can scan that suffix using the previously authenticated complete prefix; no256
ancestor lifetime bound is introduced. coverage_complete remains false throughout.

Actual local acceptance uses300commits and fresh Python processes, concurrent
reporter/lost-ack retry, checkpoint-only publication, copied bootstrap/tampering,
merged ancestry, a temporary executable later deleted, partial trees and byte
budget negatives. Existing append/project continue to use strict verify_bootstrap;
T294/T295/T286–288 must integrate complete origin windows and retained projections
before claiming unattended capacity. Shared tree frontier/object bounds still
raise explicit capacity gaps rather than claim complete coverage. No pruning.

The current archive writer's Administration-read omitted actors remain unsupported.
The main-policy observation repair approves explicit-empty actors only and cannot
be injected into the archive App-only-actor model. Separate reviewed bootstrap/
credential/capability integration remains required; no active archive or live state
was provisioned by this local task.

### T-294 local partitioned backfill — 2026-10-16

An explicit backfill operation joins the existing atomic discovery/CAS writer.
Its immutable campaign starts at reviewed coverage_from and fixes a protected
whole-second UTC end, workflow/default source branch and query size. A changed end
or binding rejects; no candidate boundary or caller checkpoint grants authority.
Filtered counts >=1000 split inclusive time ranges, with boundary overlap deduped
by the existing immutable run/attempt pending index. A saturated one-second bucket
is an explicit gap, persisted and revisited in later epochs rather than omitted.

A constant <=64 DFS frontier selects strict sharded partition records. Each record
bounds its page/count/unique identity facts below the filtered ceiling, checks
exact row counts and retained page digests, and confirms the first page/count
before calling a partition observed. Rounds revisit completed and gapped intervals
so late old-created IDs and reruns join the existing segmented cold watch. Old IDs
and attempts are never removed. Source observations are not retained delivery proof;
missing artifacts/unapproved or unavailable sources remain pending under T285.
Network/access/count/identity inconsistencies are gaps or blocked writes, never
valid engineering proof; source/state observations share existing32MiB/API bounds.
Page facts, partition/frontier and pending-watch progress publish in one nonforce
base_tree commit; CAS conflicts/lost acknowledgements reconcile exact changed bytes.
All complete/coverage flags remain false, including short or empty listings.

Local acceptance separates full1100-run partition algorithm fixtures from actual
Git atomic/CAS/fresh-process paging and boundary-dedup integration. It does not
claim full large-state hosted bootstrap integration: existing strict bootstrap and
T293 frozen-origin suffix boundaries remain until T286–288 complete integration.
T295 retained-projection windows and aggregate T286 remain pending.

T288 must extend a campaign only through a new protected campaign that retains the
original coverage_from and old partition/seen facts. It may not overwrite history,
reset origin or substitute a forward watermark. T288/T290 must also preserve
historical authenticated six-file retained facts after the seven-file helper
upgrade: validate against reviewed merge-time closure families/profile snapshots,
while current ingest rejects omission of a current helper and revocation annotates
old facts. Arbitrary self-asserted runtime sets or implicit legacy fallback are not
acceptable cross-version proof. These integration acceptances are pending, not
implemented by T294. Actual main PR110 source is intentionally not imported midtask.

### Actual protected-main integration and T-299 — 2026-10-16

Merge actual protected main6a004bc6d926e16f9b09efe949fbb8b50a843eac after PR110
landed and twelve checks were restored; do not rebase or replace the original
receipt commits/ledgers. The merge imports the approved seven-file current receipt
closure and eight-file producer closure unchanged. Conflict resolution preserves
the task union, T180blocked/T222pending, completed T275–285/T291–294/T296–298 and
pending T286–290/T295. ADR0007 and0008 each retain their original index bytes once.
No profile, archive or compatibility implementation is added during this merge.

T299 depends on T294 and completed T292; T295 now depends on T294 and T299. T299
must adapt current seven-file closure/material count10 while retaining strict
report-only support for authenticated historical six-file facts. Use known reviewed
closure families/schema/profile snapshots; arbitrary runtime sets and self-asserted
versions cannot establish origin. Current ingest must reject omitted current helper
bytes, selected-profile mismatch never falls back to legacy, and current revocation
annotates old merge-time facts without erasing them or granting runtime task credit.
The dedicated runtime-compatibility acceptance must demonstrate old retained six
through current seven readers, strict new-source omission rejection and revocation.

The source import is not a claim that all receipt tests are green: existing bounds
and fixture assumptions may fail until T299's separate implementation. Structural
and DAG planning checks establish consistency only. T295 projection, T286 aggregate,
T288 campaign/loader integration and live archive App-writer hidden-metadata/
credential cutover remain pending. This checkpoint changes no active profiles,
secrets, flags, live protections, state stores or deployment authority.

T299 must allow reviewed historical six-file profile entries (including revoked
entries) alongside current seven-file entries in the protected trust document; an
old entry must not invalidate the whole document. Actual current source
authentication/build_record must still require all seven current dependencies and
exact selected pins, with a positive ten-material case. Retained integrity uses
its authenticated original known closure/material family, not a global current
tuple. Report-only historical compatibility is required; new six-file legacy
imports need not be broadened if unsupported and that limit must be explicit.

### T299 local implementation — 2026-10-16

The strict schema1 parser accepts exactly the reviewed historical six-file and
current seven-file families in one trust document. Current source/build paths
still require all seven and never fall back from selected-profile mismatch.
Retained readers validate their authenticated capsule's exact family, with a
ten-material bound for current distinct source objects. No archive-origin gate
was relaxed. Actual compatibility acceptance includes a real disposable Git
protected-writer fixture: six-file fixture issuance, seven-file reader after API
artifact expiry, fresh SQLite restart, revoked historical/current profile mix,
withdrawal without task credit, encrypted byte preservation and missing-origin
rejection. Fixture-only historical emitter modeling is not live issuance proof.
T295, T286 aggregate and remaining loader/readiness/live archive cutover remain
pending; no active trust or runtime settings changed.

### T295 routine atomic decomposition — 2026-10-16

T295 remains pending as an aggregate retained-projection acceptance. Its existing
approved scope is decomposed into sequential children; no source implementation
is included in this planning checkpoint:

1. **T300 (after294,299): bounded frozen-view validation.** Validate one strictly
bounded record/material/index window against an independently authenticated
protected archive view. Bind exact repository/privacy/stream/bootstrap/head/tree,
coverage interval and window range/count. No arbitrary caller reference, hash,
cursor or partial scan establishes origin. Preserve all current material, known
closure-family, conflict and copied-bootstrap protections. Return checked facts
and explicit continuation only; a partial result never claims complete coverage
or grants runtime task credit. Acceptance: factory-receipt-projection-window.sh.
2. **T301 (after300): protected checkpoint publication.** Define exact inert
manifest/window paths and complete bounded schemas. Persist only checked frozen
window references/results through protected writer/bootstrap origin, publication
identity and checkpoint-only delta checks. Use bounded base-tree CAS/reconcile,
preserve reports/encrypted feedback, reject copied checkpoints and concurrent
conflicts, and never treat content hashes as origin. Acceptance:
factory-receipt-projection-checkpoint.sh.
3. **T302 (after301): fresh-process reconstruction.** Resume authenticated protected
window progress and reporting reconstruction across fresh hosted SQLite processes
instead of resetting at segment0. Demonstrate more than128 retained segments
with per-invocation bounds and real Git/restart/CAS tests. Reapply current trust
revocation while preserving immutable historical reporting facts, including known
six-file receipts; no task lifecycle credit. Freeze the requested interval/view;
newer unscanned suffix remains pending. Missing/conflicting proof rejects atomically,
partial reports remain explicitly incomplete, and no retained history is pruned.
Acceptance: factory-receipt-projection-resume.sh.

T295 now depends on294,299,302 and remains pending until its aggregate acceptance
passes. T286 remains pending after all original children; T288 must integrate
T293 ancestry windows and these projection windows. These tasks cannot silently
claim that the existing256-commit full-bootstrap reader has been replaced, nor
use it as an unbounded retry loop. Its remaining origin-budget gap is explicit
until integration. Exact current hidden-App metadata/capability cutover remains
pending. No new authority, credentials, retention policy, active profile, state
write or live configuration is approved by this decomposition.

### T300 bounded retained window — 2026-10-16

`projection_window` authenticates the protected view itself before reading a
requested bounded segment range. It shares a2048-call/32MiB observation budget,
validates all index/record/material/source/trust bindings, preserves known6/7
historical families, and rechecks actual origin plus protected trust/approval
bytes before returning checked references/facts. Caller requested SHA/range are
constraints, never cursor-origin proof. Result binds exact frozen head/tree,
bootstrap, repository/privacy, source policy, approval and current trust hashes.
It performs only GETs and never writes SQLite or archive state. The legacy
all-at-once project_retained reuses this validation before its existing atomic
SQLite mutation, and explicitly rejects incomplete windows.

The requested interval_end is validated and bound as a campaign label, NOT used
to filter facts by authenticated delivery time. T302/T288 must apply correct
report/merge-time interval semantics and cross-window duplicate/conflict checks
before any interval-complete claim. all_segments_checked means traversal of this
entire snapshot only when starting at0 and ending atcount; coverage_complete is
always false. The legacy256-commit bootstrap bound, protected window publication
(T301), fresh-process progress beyond128segments(T302), and T295/T286 aggregate
remain pending. No caller JSON is a reusable trusted checkpoint.

### T301 protected window publication — 2026-10-16

One strict inert path `receipt-archive/projection/<stream64>.json` stores one
bounded checked window and its previous immutable Git blob SHA. Original windows
remain reachable in protected branch history; no unbounded window list or pruning
is introduced. A current capsule must bind exact reviewed repository/privacy,
branch/bootstrap/approval/policies, current policy, frozen head/tree and campaign
interval. Actual path-history identifies the publication: require its single
observed parent, descent from reviewed bootstrap, exact checkpoint-only tree
delta and previous file blob/contiguous range at that parent. Ordinary reporter
commits between checkpoint publications remain allowed and preserved. A hash or
caller JSON never establishes this origin.

The window reader can now constrain an older frozen view only after independently
authenticating the full current protected chain, exact ancestor comparisons and
actual immutable commit/tree binding. It rechecks current origin before returning
references. Checkpoint publication validates those references internally, uses
base-tree non-force CAS with three bounded observations/reconciliation and shares
2048APIcalls/32MiB across attempts. Per-invocation record limits may change within
1–128 without resetting a retained prefix; they are not a lifetime campaign lock.
The capsule retains references only, never provider output/private feedback or
runtime task authority. Current trust is rebound per checked window and must be
reapplied by the later reporting reader. A completed frozen prefix does not cover
a newer unscanned suffix or grant delivery coverage.

T302 must authenticate/read every prior window through actual publication history
and previous-blob continuity in bounded work, validate all retained materials and
apply current revocation/global conflict/interval semantics before reconstruction.
No fresh SQLite reconstruction, >128segment completeness, T293 replacement of the
256commit bootstrap reader or report-loader integration is implemented here.
T295/T286/T288 remain pending; actual App hidden-metadata/writer cutover is still
unsupported. No live bootstrap, profile, credential, flags or protection changes.

### T302 atomic decomposition and origin ordering — 2026-10-16

Inspection confirms compact immutable schema1 has no merged_at. Its existing
interval_end is only a campaign label: neither coordinator run time nor checkpoint
publication time can legitimately filter delivery merge time. The recommended
backward-compatible engineering choice is a derived exact same-repository PR GET
observation; no schema2, invented historical date or new authority is needed.
Retain schema1 facts unchanged even when time cannot be authenticated.

T302 remains a pending aggregate, now depending on301 and309. Its approved scope
is split into sequential bounded children, all pending:

1. **T306(after301): authenticated lineage reader.** Read bounded checkpoint
   history only after independently authenticating current protected origin. Bind
   actual publication descent, exact single-parent checkpoint-only delta and
   previous-blob continuity to the frozen repository/branch/bootstrap/tree and
   campaign. Raw Git blobs, caller JSON/hashes/cursors or a complete flag cannot
   establish origin. Return only checked window references with explicit partial
   continuation; current frozen suffix remains pending. Acceptance:
   factory-receipt-projection-lineage.sh.
2. **T307(after306): derived exact merge-time facts.** Use a trusted fixed same-
   repository PR GET and bind PR number, merged=true, exact retained merge SHA
   and base repository ID/identity before accepting supported aware merged_at.
   Preserve source proof identity and immutable schema1. No caller-supplied time,
   run/publication time fallback, rounding or unsupported precision. Missing or
   unavailable PR/time metadata is an explicit required-time gap, not deletion or
   invalidation of a retained historical delivery fact. Stage only bounded checked
   facts under the existing protected writer; no new credentials or permissions.
   Acceptance: factory-receipt-projection-time.sh.
3. **T308(after307): protected derived-fact stages.** Define strict inert staged-
   fact/cursor namespaces and bounded complete schemas, protected publication
   identity and CAS/lost-ack reconciliation preserving reports/encrypted feedback.
   Retain immutable source references and global cross-window task/execution
   duplicate/conflict indices; never silently select a winner or trust arbitrary
   serialized SQLite/schema/SQL. Stage progress must originate only from checked
   lineage/material/time facts. Per-invocation limits cannot become lifetime
   history caps; no source archive pruning. Acceptance:
   factory-receipt-projection-stage.sh.
4. **T309(after308): fresh-process SQLite reconstruction.** Materialize only
   authenticated requested-interval facts from protected stages, revalidating
   original retained source/material binding and current revocation. Fresh SQLite
   processes must advance/reconstruct beyond128 retained segments using protected
   progress rather than restarting at0. Real Git, restart, partial continuation,
   CAS/feedback preservation and global conflicting/copy/private negatives are
   required. Time/required-proof gaps and unfinished scans keep reports explicitly
   incomplete; no runtime task creation/credit. Report-time filtering uses checked
   PR merged_at, not the campaign label. Every old historical fact remains in the
   archive even when outside this requested interval or withdrawn. Acceptance:
   factory-receipt-projection-resume.sh.

**T310(after293 and completed302)** is the completed-origin integration foundation
BEFORE T286 and therefore before T287's >1000-history acceptance. This fixes an
ordering defect: real append histories can exceed the existing256-ancestor reader
before the old T288 integration point. T310 must authenticate completed T293
checkpoint publication and checked-prefix provenance, validate any current suffix
within invocation budgets and preserve all single-parent/inert-tree/bootstrap/
copy/rollback/policy-binding guards. Raw completed:true or compare ancestry alone
never substitutes for checked historical content. Integrate the shared origin
entry point into core append/discovery/projection paths; incomplete origin stays
a gap. No hidden-App metadata model or live writer capability change is included.
Acceptance: factory-receipt-completed-origin.sh. This is an outline requiring
implementation review, not a claim that T293 already removes256 everywhere.

T286 now explicitly depends on310 in addition to its existing children. T287
continues to depend on286; it must exercise genuine >1000 append/source history
with completed-origin integration, never mock away or bypass the256 guard. T288
retains final CLI/report-loader/profile configuration integration, not the first
origin foundation needed by earlier acceptance. T309's >128-segment test can use
a real sub256-commit history while that foundation is pending; it must state this
limit honestly. T295/T302/T286/287/288 and306–310 remain pending.

No new signature boundary, App permission, credential, store, retention policy,
live profile, rules or authority is authorized by this routine decomposition.
Any shared parser/helper adaptation must use actual merged protected source, not
unmerged diagnostic candidates. This checkpoint adds no source implementation.

T306 local implementation reads bounded GET-only publication pages after actual
protected origin verification. Exact history SHA is independently authenticated,
so concurrent reporter commits cannot shift that requested view. Each returned
publication checks single parent, checkpoint-only delta, previous actual Git
blob/continuity and frozen commit/tree bindings. Empty late-page is explicitly
partial with unknown/pending suffix; coverage remains false. Actual16 real-Git
lineage cases and checkpoint20/window17 regressions pass locally. No timestamp,
retained-proof reconstruction or protected staging is implemented here. Global
cross-page reconciliation and the256-origin integration remain pending; no live
configuration, archive credential/capability, settings or push changes.
