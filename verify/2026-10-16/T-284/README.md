# T284 — protected segmented discovery progress

Local foundation for approved Spec014 AC7/8, based on receipt source `ef8b4fc575081743beed56b1bc8eb7909dea1aaa` and merged protected main `6606a1b3392bc8f867b46e5b1e81bbf86be34d6e`. No live checkpoint, workflow activation, credentials, permissions or settings were changed. Analyze014 remains PASS.

The same acceptance command's RED records the absent protected restartable checkpoint. GREEN passes 11 scenarios using actual temporary Git objects/ref CAS and fixture GitHub metadata. The initial global pending-list draft was replaced before commit: 500 unresolved run/attempt/source identities now survive fresh invocations and concurrent checkpoint writers in bounded immutable watch segments, with a constant-size manifest and fixed sharded identity lookup. No failed/rerunnable run is silently discarded to meet a global pending limit.

Only checkpoints read from the actual bootstrap-authenticated protected branch are accepted. They bind exact repository ID/name/privacy, branch, reviewed origin/tree/coverage, protection policies/App writer and approval digest. A pre-bootstrap checkpoint cannot be imported automatically. Frozen scan and saved verified heads/trees are checked on actual ancestry; only checked scanner output is persisted, and callers cannot supply cursor JSON. Every row remains explicitly pending, and `coverage_complete` is always false. Source page identities are observations, not engineering proof.

Pending segment, immutable lookup and progress updates share one parent/base-tree commit and non-forced CAS. Max-three conflicts re-read/reconcile; a lost acknowledgement verifies all intended protected material before reporting success. Actual fixtures cover report-writer races, checkpoint-writer coalescing, restart, foreign metadata, altered immutable identity, changed protection, caller cursor rejection, retained encrypted-report bytes and rejection of pre-bootstrap progress imports. The 500-row fixture retains every original identity; it does not claim production archive authorization.

The segmented fixture exposed the old one-window tree scan failure; `segmented-bootstrap-red.txt` retains that actual failure. Bootstrap now continues its own checked in-memory tree frontier for at most ten 100-page windows, with one shared 2,048-read/32MiB bound across all ancestry commits. It still requires a complete tree and never trusts an external partial cursor. Discovery shares a 4,096 actual state-call/32MiB budget across three observations, plus at most three bounded source page requests; each observation reads at most 100 runs and ten frozen tree pages and prepares one watch segment. Object/segment/encoded sizes and paths remain strict and inert.

Actual verification:

- `bash .claude/scripts/test/factory-receipt-discovery.sh`: 11 real-Git scenarios PASS (`green.log`).
- State paths: 33 cases; bootstrap: 15; CAS: 11; retained proof: 20; existing projection: four AC groups; coordinator: 63, all PASS (`regressions.txt`).
- Python compilation PASS for all three modified/new modules, using a temporary cache.
- Structural validation PASS with four existing warnings (`structural-results.txt`).
- Whole ledger PASS: zero failures, zero enforced warnings; 70 pre-T111 legacy-incomplete entries not enforced (`whole-ledger-results.txt`).

Pending integration is material: T285 must reconcile reruns/late visibility and authenticated delivery/non-delivery outcomes, retaining cold watch identities with trust epochs; terminal failure alone is not permanent non-delivery. T286 must partition capped filtered run queries and integrate trusted resumable ancestry anchors and bounded retained projection/read windows. T286–288 must remove the current 256-commit/128-projection-segment invocation stops through real protected progress, including fresh hosted SQLite reconstruction that resumes verified windows rather than restarting at zero. Exhaustion remains a visible gap until then. Neither a short/empty API page, complete tree scan nor this journal proves complete history or authorizes autonomous merge. No compact proof is pruned.
