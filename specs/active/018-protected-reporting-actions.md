---
id: 018
slug: protected-reporting-actions
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Protected self-hosted reporting Actions

Operator selected a dedicated persistent self-hosted Actions runner. Prepare disabled reusable integration; activation requires a real host, workspace/bot identity and read-only organization runner-policy access. No registration token or Slack credential enters source/evidence.

## Acceptance criteria

1. **AC-1**: A hosted preflight verifies the target repository default branch and a selected, nondefault organization runner group restricted exclusively to this reporting workflow at that branch, selected repository and supported online reporting runner. Missing metadata, broad group policy or offline/mislabelled runners block dispatch.
2. **AC-2**: Reporting jobs consume a separate protected main-only environment and exact Actions source revision, with read-only GitHub permissions and no merge App key. Disabled-by-default master activation guards schedule/dispatch; only the trusted reporting group is selected after preflight.
3. **AC-3**: Persistent state must be a pre-provisioned private POSIX directory outside candidate checkout/workspace trees. Runtime config uses typed non-secret environment values; credentials remain environment secrets. Scheduler invokes the due-time runner and reports missed delivery via read-only watchdog without cache/artifact cursor restore.
4. **AC-4**: Fixtures reject wrong repository/ref/group/workflow, broad repository access, missing runner, insecure state and candidate-writable paths. Valid policy/config pass; actionlint and digest/Slack/coverage regressions pass. A documented setup path names secure secret storage and remaining live activation prerequisites.
