# Hosted reporting pilot activation proof

The claude-init pilot is enabled for the private qyndex-alerts channel in qyndex at 08:00 Australia/Sydney. GitHub-hosted Actions checks the latest due cutoff every fifteen minutes; GitHub scheduling delays can move actual delivery after 08:00. Each adopting repository owns its configuration and durable reporting branch.

The first catch-up contains 34 merged PRs from repository creation through 10 October 2026 at 08:00 Sydney. Slack accepted the post as two fragments. Earlier receipt checks correctly kept the batch uncertain; no reset or resend occurred. Spec 023 recovers both authenticated fragments, verifies the complete report and stores both original message IDs.

- [Live recovery run](https://github.com/qyndex/claude-init/actions/runs/38019626144): successful private-channel identity/history preflight, wrong-workspace negative probe, exact fragment receipt readback and durable confirmation.
- [Repeat run](https://github.com/qyndex/claude-init/actions/runs/38019653271): successful, not due, checkpoint/document unchanged.
- Recorded source: `f0826c9afcc580cccaa96941b0f92c5e045a697a` (PR #71); all seven current required checks passed before merging.
- Authoritative checkpoint: `333104acce138924243515a24b0071c28e356f7a` on the protected data-only reporting branch.

The JSON records only non-secret configuration and delivery metadata. The Slack credential remains in the effective Actions secret; no credential was extracted or copied into this audit.

This proves reporting activation and transport recovery. It does not prove autonomous feature merging, independent review, production release readiness or historical verified delivery. Historical PRs explicitly show authenticated evidence missing. Quota-paused independent review and required contexts still need restoration before merge authority can be enabled. Oversized attachments, external schedule watchdog, authenticated feedback intake and remaining adoption/release adapters stay open in the factory plan.
