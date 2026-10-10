# Reporting pilot bootstrap — 10 October 2026

PR #63 merged at `a896dc065fa254950dc55f8aa81b751b9a202985` after all seven required checks passed. The live bootstrap used the authenticated GitHub CLI without extracting credentials.

The public, data-only `factory-reporting-state` branch starts at `d561118a73ca1f6f6c72f6ced5e65171e847be86`. Active ruleset 24826406 blocks deletion and non-fast-forward updates without bypass actors. Main ruleset 19653920 retains its seven strict required checks; the temporary independent review pause still requires restoration before autonomous merges.

Two independent state readers observed the same bootstrap parent. The first committed the initial cursor/origin snapshot. The second attempted an identical snapshot with a distinct commit and GitHub rejected its non-force update. A fresh reader restored the first checkpoint byte for byte at `8d520687622ccb84ecc26d4da6db9462be7bda5b`. Only the initial cursor/origin and no report batches were published. The helper did not instantiate Slack or send messages. This is live GitHub state evidence, not independent reviewer evidence or proof of an Actions-token/Slack delivery.

The pilot origin is the repository creation timestamp, `2026-05-28T12:08:38Z`, preserving historical merge coverage. The reporting environment stores the bootstrap SHA, state repository/branch, origin, team and channel; repository profile is `github-hosted`. The master enablement variable remains unset. No secret values are recorded here.

Live Slack bot credentials, identity/delivery drills and the hosted job's confirmed checkpoint remain activation prerequisites. Never reset the origin or delete/rewrite this branch to recover a failed report. Disable reporting before a protected code rollback, preserving state and receipts. Adopting repositories use their own configuration and state.
