---
id: 022
slug: reporting-policy-approval
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Reporting policy approval without ruleset administration

The live hosted runner passes Slack identity/history but cannot inspect bypass actors with its contents-only Actions token. GitHub exposes that field only to actors with ruleset write access. Preserve rejection of unknown bypass actors; bind a protected operator observation to exact visible policy metadata instead of granting ruleset administration to reporting.

## Acceptance criteria

1. **AC-1**: Visible active empty bypass lists remain accepted; nonempty lists and disabled rules reject. A hidden bypass list cannot be assumed empty and rejects without protected operator approval.
2. **AC-2**: A GET-only operator helper emits approval only after observing a complete active repository branch policy with explicit empty bypass actors, matching repository/ID and a server update timestamp at least 60 seconds old. It uses existing CLI authentication without extracting credentials or issuing mutations; missing fields, recent policy changes, wrong source and nonempty/hidden bypass lists reject.
3. **AC-3**: Hidden-field approval binds typed schema, repository, ruleset ID, empty bypass list, normalized UTC update timestamp, settled observation time and SHA256 of all contract policy fields. Changed identity, source, conditions, rules, timestamps or hash and invalid/future observation clocks reject. Actor-relative response fields and equivalent timezone representations do not affect the fingerprint. No API omission becomes an implicit empty list.
4. **AC-4**: The default-branch-only hosted job consumes per-adopter approvals from the protected reporting environment without merge App or administration credentials. Regression/HTTP fixtures and workflow validation pass. Documentation states the protected operator trust boundary, API timestamp dependency and reapproval on any policy change; reporting remains disabled until actual delivery/readback/repeat-run proof passes.
