---
id: 010
slug: protected-proof-producers
spec: specs/active/010-protected-proof-producers.md
status: approved
owner: "@codex"
created: 2026-10-09
updated: 2026-10-09
---

# Protected proof producers

T-182 implements AC-1–AC-3 in a default-branch producer with injected regression fixtures and sandboxed acceptance. Separate pull_request_target workflows use only protected source. Candidate execution takes place in a fresh non-root Docker container; the tool-free reviewer runs outside the candidate checkout and never inherits the factory key or GitHub token. Protected policy supplies the image digest and per-AC argv. Artifacts retain observations and are machine-validated; no candidate-supplied PASS input is consumed.

T-183 implements AC-4: producer-created head checks link to authenticated protected workflow runs. The coordinator obtains each run from its required check receipt, checks the default/base runtime hashes, validates exact bound proof and preserves conditional merge semantics. Completed target workflow runs resolve PR numbers from uniquely named artifacts; no candidate code runs in merge authority.

Account bootstrap and genuine shadow proof remain blocked in T-180 until the dedicated App exists and subscription capacity resets. Do not advance to unattended delivery before the shared execution and recovery package F-04 also passes. Test fixtures are implementation evidence, not live independent attestation.
