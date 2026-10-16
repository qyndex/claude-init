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


## Approved policy visibility repair — T-292 — 2026-10-16

Protected shadow run38826696104 minted its App token but failed closed because
GitHub omits bypass_actors for Administration-read callers. Operator GET exposed
empty actors and the active twelve checks. The operator explicitly approved
option A: exact protected operator observations, preserving Administration read.
This authorizes source preparation, not flags, protection changes or a merge window.
GitHub documents the omission at https://docs.github.com/en/rest/repos/rules.

T-292 is an aggregate pending task. Execute sequential children T-296 → T-297 →
T-298, with independent actual RED/GREEN evidence; do not mark the aggregate done
until its combined acceptance passes. IDs293–295 remain reserved on the separate
approved Spec014 receipt continuation branch. ADR-0008 records this decision.

- T-296: stdlib-only factory-policy-observation.py and its behavioral tests.
  Strict bounded input/schema, repository/ruleset identity, full stable metadata
  projection/digest, settled timestamps and explicit actors. GET-only observation
  command cannot manufacture approval when actors are omitted. Visible nonempty
  or malformed actors always reject; visible empty can pass without observation.
- T-297: coordinator consumes explicit protected input; factory-merge.yml writes
  bounded JSON from a main-only factory-authority environment variable to a file.
  No candidate/body input, canonical-policy field, credential or permission change.
  Retain bounded audit observation/hash in a distinct artifact, leaving the
  existing receipt ZIP exactly receipt.json. Never call administrative observation
  a GitHub-native signature. Recheck all current effective pins/strict protection.
- T-298: integrate the helper into complete producer runtime closures (7→8),
  both roles' trusted-file hashes, preflight, native provenance materials/limits
  and fixtures. Policy changes are restricted to necessary runtime pins;
  merge_enabled stays false. Cross-runtime regressions must detect omitted helper.

Scope: the helper, coordinator, producer, provenance, preflight, receipt runtime
closure declarations, candidate-evidence validator, their scoped shell tests,
factory/policy.json, factory-merge.yml, activation/setup/producer docs and this
spec/plan/ADR/task evidence. New helper matches protected .claude/scripts/factory-*
(the current policy already includes that authority-path pattern). No live edits.

Spec014 integration remains pending on its separate branch: emitter closure6→7
and shared retained material count9→10, with corresponding strict fixtures and
profile hashes. There are no active content profiles. Do not claim durable receipt
or live shadow readiness from this source repair. Later publication requires all
nine normal checks and separately reviewed concrete maintenance before landing.

### T303 bounded failed-observation diagnosis — 2026-10-16

Actual protected shadow run38833564091 failed closed with `observation metadata
changed or foreign`; its existing administrative audit has checks[] because the
exception occurs before the success-only append. The operator's later full-admin
GET still matches the saved observation; that does not establish the App's actual
view or identify the mismatching component. Authority is off. No timestamp or
metadata normalization/acceptance relaxation is justified by this evidence.

T303 adds bounded safe failure diagnostics within approved AC5 operator-observation
scope. Before rethrowing the original validation failure, retain fixed-schema
semantic-component SHA256 digests, full semantic projection digest if valid,
repository/ruleset identity, and bounded canonical/raw created/updated timestamps
when valid. Record missing/malformed component status without echoing arbitrary
values. Compare expected observation metadata hash/timestamp only through fixed
validated fields. Diagnostics must describe the actual App-fetched response, never
a candidate-provided substitute or an administrator's later GET.

Use the existing separate bounded90-day administrative audit artifact, outside
the single-member receipt directory. No raw actor arrays, rule values, unknown
fields, authorization headers, credentials, protected observation JSON or provider
output may be logged. A diagnostic is not native attestation, exact-policy approval
or portable archive origin. Preserve original exceptions and failure check
invalidation; failure to construct a diagnostic must never authorize eligibility.

Strict real fail-first acceptance will demonstrate that a metadata mismatch
preserves a bounded component diagnosis while the same mismatch still rejects.
Test changed/missing/foreign/malformed/oversize/sentinel cases, timestamp spelling
and precision only as diagnostic evidence, and unchanged valid direct/observed
validation. Preserve all settled timestamps, exact hash/identity, visible actor
rejection, live pins, fresh protection rechecks, Administration-read permissions
and merge_enabled=false. Refresh only necessary runtime hashes for changed
protected source, with existing complete closures unchanged. No workflow event,
permission, secret or live configuration change is part of this task.

After normal source review and separately approved deployment/maintenance, obtain
a genuine protected App-view failure audit before proposing any root-cause fix.
This planning checkpoint implements nothing, does not claim the diagnosis is known
and does not certify hosted shadow readiness. Receipt tasks300–302 remain on their
separate branch; T303 does not reuse their reserved IDs or modify that branch.

Implementation boundary: capture the actual semantic component digests before
validation can fail; preserve ordinary success audit entries. Use fixed failure
category enums, never arbitrary exception text. Emit expected and actual overall
metadata hashes when strictly valid, per-SEMANTIC-field canonical hashes and only
bounded valid raw created_at/updated_at strings. SEMANTIC/exclusion sets and exact
timestamp enforcement remain byte-for-byte unchanged. Changed source requires
updated exact pins for both producer roles with existing8/7 closures intact; no
receipt trust extension or timestamp normalization is authorized.

T303 local implementation captures actual hidden-response component fingerprints
before validation and appends a rejected-observation audit entry only on failure,
then rethrows the original rejection. Bounded diagnostic errors cannot prevent
eligibility failure invalidation. A prewalk bounds both visited and queued nodes
before canonical hashing; emitted values are fixed digests/identities/valid
timestamps, never raw actors/rules/unknown payload. Original success audit and
all enforcement remain unchanged. Local acceptance27 and existing scoped
regressions do not establish the real hosted mismatch or diagnose its cause.

### T304 independent-review diagnostic completion — 2026-10-16

Independent local Sonnet review of T303 requested two low-severity corrections:
the generic diagnostic reason and missing expected updated_at/identity-match
facts cannot distinguish non-hash rejection causes, and the inner audit catch
skips unexpected validation exceptions outside ValueError/KeyError/TypeError.
The review was static; it did not execute tests or establish hosted behavior.
Root independently reran the27-case acceptance. PR111 remains draft at this
planning checkpoint; no actual App-view mismatch cause has been established.

T304 remains within approved AC5 bounded observation diagnostics:

- Retain expected updated_at only through the same bounded valid timestamp
  representation as actual timestamps. Add fixed-schema mismatch/match flags for
  safely typed repository/ruleset identity, metadata digest and exact updated_at
  facts; malformed/missing values have explicit unknown/invalid status. Never
  dump the observation object, actors, arbitrary error text or unknown fields.
- Classify fixed known authoritative validation failures into a small bounded
  rejection-category enum. Derive it from the original failure, not a second
  validator deciding authority. Unknown exceptions receive a fixed unexpected
  category; diagnostic flags cannot relax exact enforcement or reorder validate.
- Broaden ONLY the inner audit-and-reraise handler to Exception. Inject a
  RuntimeError in validation and prove the prebuilt bounded diagnostic survives
  while the exact same exception propagates unchanged. Preserve the main CLI's
  existing handled exception tuple and its demonstrated ValueError same-head
  failed-check invalidation. Do not claim unexpected exceptions now acquire CLI
  failure-check invalidation when that outer handler does not catch them.
- Remove unused contextlib and replace the unexplained initial test count with
  explicit case accounting where local. Preserve the repository's shared fixture
  extraction pattern; do not rewrite unrelated test infrastructure. Retain the
  meaningful tracemalloc queued-frontier regression and describe its CPython
  allocation-threshold assumption, already exercised on the actual local runtime.

Strict actual RED/GREEN must first demonstrate missing expected/mismatch facts
and skipped unexpected-exception audit; preserve existing diagnostic resource
bounds, sentinel safety, ordinary success audit and all exact validation tests.
Refresh all16 actual producer runtime pins with unchanged8/7 dependency closures;
all other policy fields, merge_enabledfalse and permissions remain unchanged.
No timestamp normalization, SEMANTIC/exclusion changes, private receipt trust
extension, new credentials, workflow events or live configuration is authorized.
After implementation, normal source/independent review and separately approved
rollout are still required before genuine protected App-view diagnosis. This is
planning only; T304 remains pending and receipt T302 is untouched.

T304 local implementation adds bounded valid expected_updated_at and nullable
fixed identity/hash/exact-timestamp match facts. Fixed known original validation
messages map to rejection enums; unknown failures use a fixed unexpected category
without error text. The inner Exception audit-and-reraise preserves the exact
RuntimeError instance; the authoritative validate() and main CLI body remain
byte-identical to pre-T304. Existing ValueError CLI invalidation still passes.
Actual separate REDs exposed missing expected facts and skipped unexpected audit;
GREEN42 cases include resource/sentinel safety and explicit local case accounting.
No time normalization or hosted App diagnosis is implemented by this review fix.

### T305 observed cross-caller timestamp defect — 2026-10-16

Actual anonymous public GET and actual full-operator GET differ in exactly two
semantic fields, created_at and updated_at. Operator created_at
2026-07-24T12:14:58.274+10:00 equals public2026-07-24T02:14:58.274Z; operator
updated_at2026-10-16T11:49:11.557+11:00 equals public2026-10-16T00:49:11.557Z.
All other semantic fields are equal. Current helper hashes differ and actual
current validation rejects `observation metadata changed or foreign`. The bounded
observed reproduction is retained under T305-planning, with actual raw response
digests and an explicit actual_app_view=false label. This demonstrates a real
cross-caller equivalent-instant defect independently of the unproven App cause.

This new evidence supersedes the earlier speculative no-normalization/App-audit-
before-any-fix guard ONLY for these two observed timestamp fields. It does not
prove anonymous metadata equals the actual App view, remove the need for genuine
protected App-shadow verification, or authorize other semantic changes. T303/T304
timestamp-spelling rejection evidence remains honest pre-T305 behavior.

T305 canonicalizes only created_at and updated_at in the semantic projection to
a deterministic UTC representation preserving every supported microsecond.
Compare observation/server updated_at by that same exact instant, while retaining
raw diagnostic strings and clearly distinguishing raw spelling flags from
authoritative semantic equality. No other field, identity, condition, rule, actor
handling, field allowlist, settle60seconds or future bound changes. Support actual
GitHub milliseconds and full microseconds; reject unsupported submicrosecond
precision or invalid offsets rather than truncate, round or silently coerce.
Avoid floating-point epoch conversion. One-microsecond drift must still reject.

Actual fail-first acceptance must replay complete safe semantic snapshots from
the captured real GETs, show current failure then equivalent-instant success, and
reject changed non-time fields, one-microsecond created/updated drift, invalid
offsets, unsupported precision, and observation before fractional settle expiry.
Fresh full-GET operator capture is mandatory after rollout: do not accept old
lexical metadata hashes as fallback or silently rewrite saved approvals. Existing
old-hash observations must fail until explicitly recaptured into main-only input.
Refresh exact16 runtime pins with the same8/7 closures; all other policy fields and
merge_enabledfalse remain unchanged. No permissions, receipts trust, live
observations, App setup or settings changes. T305 is pending, planning only;
normal independent review, source rollout and actual App-shadow proof remain.
