---
id: 046
slug: policy-bound-activation-planning
status: approved
owner: "@codex"
created: 2026-10-11
updated: 2026-10-11
complexity: M
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Plan activation against the adopting repository's policy

Remaining factory activation readiness: generated rules must include all policy-required producers and target the adopting repository. Legacy security review must bind to updated heads when re-enabled; it stays paused until Tuesday.

## Acceptance criteria

1. **AC-1**: Ruleset planning reads an explicit protected policy and selected ruleset ID, queries only that repository and base branch using GET, and produces no live mutation. A different repository/branch/App/ruleset works without source pilot constants.
2. **AC-2**: Preserve every existing rule, condition and unrelated producer pin. Add every policy-required check plus dedicated-App eligibility; repeated planning is idempotent. Missing legacy review/security requirements are included.
3. **AC-3**: Malformed policy, mismatched App, nonapplicable/inactive/bypass rulesets, nonstrict or ambiguous check rules, duplicate contexts and conflicting pins block before overwriting the output proposal.
4. **AC-4**: Legacy security workflow includes synchronize for exact updated-head checks, with comments matching real exemptions and concurrency. Workflow lint and authority/request regressions pass; no paused workflow or authority is enabled.
