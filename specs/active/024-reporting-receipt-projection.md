---
id: 024
slug: reporting-receipt-projection
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Authenticated hosted reporting evidence

Authorized F-05 refinement: ephemeral GitHub-hosted reporting currently restores only digest tables. Load actual protected coordinator artifacts as read-only evidence without enabling merge authority or inventing evidence for historical manually merged PRs.

## Acceptance criteria

1. **AC-1**: Fresh reporting disks reconstruct authenticated delivery/provenance tables consumed by the actual digest. Exact repository/PR/head/merge/task/spec/run/artifact identity determines evidence links. A later approved spec revision does not erase valid merge-time reporting proof; runtime ingestion still requires the current revision.
2. **AC-2**: Share existing receipt authentication for successful protected coordinator runs, approved producer source bytes, artifact archive digest, approved merge-time policy/spec/task and actual merged PR. Reject altered/foreign/expired/ambiguous evidence. Validate all observations before atomically replacing reporting proof; do not create or transition runtime tasks.
3. **AC-3**: Discover every page of successful configured-workflow runs, reject duplicate identities and histories above 1,000 runs. Unapproved source revisions and explicit non-delivery artifacts earn no proof. An unconfigured workflow is allowed only with no approved revisions and performs no run requests; malformed or conflicting delivery observations block before sending a report.
4. **AC-4**: The main-only hosted workflow reads receipt policy from its trusted checked-out factory/policy.json and adds only Actions read permission. Project evidence before preparing a due report, rebuild on each fresh disk, and keep typed public checkpoints limited to digest tables. Existing hosted/Slack/digest/receipt ingestion/guardian regressions and structural checks pass. Unproven merges remain explicitly missing; live independent producer evidence remains pending quota restoration.
