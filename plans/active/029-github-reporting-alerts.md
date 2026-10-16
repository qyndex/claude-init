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
