---
id: 007
slug: required-verification
status: approved
owner: "@codex"
human_owner: "@operator"
created: 2026-10-09
updated: 2026-10-09
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Required verification

Implements the approved factory plan's remaining A06 controls. Approval records the operator's instruction to continue implementation; it is not independent verification or production authorization.

## Acceptance criteria

1. **AC-1**: Newly completed tasks are rerun in detached checkouts as well as branches, against an explicit resolvable base or a known main merge-base. Missing base, ambiguous IDs, missing acceptance commands, command failure and timeout block. Commands containing legitimate shell redirection are accepted. Task metadata is parsed without executing it.
2. **AC-2**: Candidate-writable skip markers and CI environment flags cannot waive required verification. A requested waiver blocks pending the separately trusted policy service. Browser provisioning failure blocks an applicable journey.
3. **AC-3**: Stack detection errors, malformed output and unknown stacks block. Every detected language stack must execute its own test command; another stack's success cannot satisfy it.

4. **AC-4**: Existing percentage-based coverage gates reject null, strings, out-of-range and insufficient values; valid decimals are compared without truncation.

## Non-goals

This slice does not establish cryptographic review identity, complete coverage adapters for every runtime, protected policy hosting, exact-head merge authorization or live deployment. Acceptance commands execute untrusted candidate code: callers must use isolated unprivileged runners without merge or deployment credentials.
