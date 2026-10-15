---
id: 010
slug: protected-proof-producers
spec: specs/active/010-protected-proof-producers.md
status: approved
owner: "@codex"
created: 2026-10-09
updated: 2026-10-16
---

# Protected proof producers

T-182 implements AC-1–AC-3 in a default-branch producer with injected regression fixtures and sandboxed acceptance. Separate pull_request_target workflows use only protected source. Candidate execution takes place in a fresh non-root Docker container; the tool-free reviewer runs outside the candidate checkout and never inherits the factory key or GitHub token. Protected policy supplies the image digest and per-AC argv. Artifacts retain observations and are machine-validated; no candidate-supplied PASS input is consumed.

T-183 implements AC-4: producer-created head checks link to authenticated protected workflow runs. The coordinator obtains each run from its required check receipt, checks the default/base runtime hashes, validates exact bound proof and preserves conditional merge semantics. Completed target workflow runs resolve PR numbers from uniquely named artifacts; no candidate code runs in merge authority.

Account bootstrap and genuine shadow proof remain blocked in T-180 until the dedicated App exists and subscription capacity resets. Do not advance to unattended delivery before the shared execution and recovery package F-04 also passes. Test fixtures are implementation evidence, not live independent attestation.


## Live provenance repair — 2026-10-16

Actual protected runs38813649635/38813649657 stopped before acceptance/model execution because REST run.head_sha identifies the candidate, while GITHUB_SHA and the checkout identify protected default source. REST pull_requests associations are mutable: historical run38139128097 retained its old immutable head_sha but now reports the updated PR base/head. Do not treat those associations as execution-base provenance.

Repair the existing AC-1/AC-4 contract with immutable run candidate identity, protected execution-context/checkout validation and authenticated artifact base binding. Preserve exact workflow/event/repository/runtime/spec/policy/AC authentication. Same-head stale-base, candidate updates, foreign origins, missing/ambiguous metadata and tampered artifact bases must block. No candidate checkout with credentials, fallback, merge enablement or new external service is authorized. Refresh producer runtime pins only after recording the repaired source commit. Resume the pilot only after the reviewed fix is merged.

T-274 prepares pinned official GitHub-native artifact signing of the exact evidence root. The coordinator verifies the uploaded bundle cryptographically with `gh`, then checks immutable certificate source/signer/ref/repository/event/hosted-runner/run-attempt claims; user-controllable predicate fields never establish execution origin. Protected execution validates its actual checkout and GitHub-provided context before effects. Signing permissions (`id-token: write`, `attestations: write`) and public/Enterprise Cloud private-repository capability are explicit review items; preparation does not activate them. No unsigned fallback is allowed. The helper and bounded subprocess dependency enter complete producer, preflight and receipt runtime pins. Local certificate fixtures and official unrelated signed CLI vectors do not complete the live pilot tasks.

## References

- Accepted ADR: .claude/memory/decisions/0006-signed-protected-producer-execution-provenance.md
- Operator approved option A and solely proof-signing permissions on 2026-10-16; docs/activation/2026-10-16/producer-provenance-decision.md records the exact boundary.

## Latest producer run binding repair — T-291 — 2026-10-16

Public pilot head45f3a9c3513855ea701778c5f2fe5c468f3c461e passed genuine signed runs38821253115 (verification workflow379732143) and38821253085 (review workflow379732140), but shadow coordination rejected GitHub-normalized check URLs. A fresh public API read confirms verifier check116718131349 URL `/runs/116718131349` and reviewer116718157648 URL `/runs/116718157648`; both point to suite105208672410. Neither URL nor suite reliably identifies a workflow run.

Select the latest run by immutable configured workflow ID from the existing paginated candidate-head run listing, before event/status filtering. Require unique positive integer run ID and attempt, re-fetch that exact run and reject stale/changed attempt or identity/status snapshots. Require exact workflow/event/path/repository/candidate head and successful conclusion; then retain every protected runtime, signed certificate/source/base and artifact check. Latest failure/cancelled/in-progress/wrong-event must block even with older successful evidence. Ignore display URL contents; never infer workflow identity from suite IDs. Keep unique App/head/success check guards intact.

Scope is T-291 source/test/policy and approved spec/plan plus task evidence. Refresh only each producer's coordinator trusted-file hash to actual candidate source bytes; all other policy values and merge-disabled state stay identical. Existing signed provenance/source/artifact tamper regressions remain required. Tests include actual normalized URL/shared-suite metadata, URL independence, latest failure/older pass, wrong workflow/event/repository/head/path and run-attempt drift. No permission, live flag, ruleset or merge activation changes. Local proof is not a live fix until merged protected source and fresh pilot proof succeed. This repairs ADR-0006's immutable workflow-run authentication without changing the signing trust boundary.
