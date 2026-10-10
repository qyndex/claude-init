---
id: 022
slug: reporting-policy-approval
status: approved
owner: "@codex"
created: 2026-10-10
updated: 2026-10-10
spec: specs/active/022-reporting-policy-approval.md
---

# State policy approval plan

Use a protected operator observation when GitHub hides bypass actors from the reporting writer. The operator helper reads only rulesets using its existing configured CLI identity, requires complete policy and explicit no-bypass proof, waits for a settled server timestamp, and emits a non-secret approval. Normalize timestamp representations and exclude actor-relative fields from the explicit policy fingerprint. Reporting compares every fingerprinted field and the server update timestamp to the protected environment approval; unknown/mismatched policy remains blocked. Do not expand reporting token permissions or relax either live ruleset. Live producer/reviewer and merge authority gates remain separate.

T-195 implements AC-1 through AC-4 with failure fixtures and the actual least-privilege pilot afterward.
