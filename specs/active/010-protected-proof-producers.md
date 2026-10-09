---
id: 010
slug: protected-proof-producers
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

# Protected proof producers

Implementation scope authorized by the operator's instruction to complete the factory plan in dependency order. Completes the producer implementation slice of F-02/F-03. Live activation is a separate gate under spec 009; this specification does not claim an authenticated production or shadow run.

## Acceptance criteria

1. **AC-1**: Protected policy selects the approved spec bytes, complete AC set, path scope and pinned producer runtime. Foreign candidates, authority changes, wrong workflow/event/base and incomplete diffs fail before running candidate code.
2. **AC-2**: Each approved AC executes an explicit argv in a digest-pinned Docker image with no network, credentials, host writes, capabilities or root user. Fresh candidate state, bounded resources/output and exit-code-bound observation digests form the verifier artifact; failed or missing commands cannot emit a passing verdict.
3. **AC-3**: A separate tool-free model reviewer receives complete spec and before/after sources within a bounded input size. An explicitly selected credential route is used, never an automatic metered fallback. Missing/quota-limited credentials, model errors, malformed verdicts and PASS with unresolved findings fail.
4. **AC-4**: Candidate-head check receipts identify authenticated protected workflow runs; the coordinator validates the producer's workflow ID, protected base, runtime hashes and exact artifact bindings. A forged run link, changed base, wrong event or wrong workflow is rejected. Automatic reevaluation resolves the candidate from the completed producer artifact.

## Activation dependencies

Default producers stay disabled until App installation, reviewed runtime/image/command/spec pins, working reviewer capacity, required check registration and live shadow proof are available. Keep merge_enabled false throughout shadow testing. The operator selected the existing subscription after its quota resets; API fallback is not authorized.
