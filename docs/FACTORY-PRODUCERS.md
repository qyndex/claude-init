# Protected factory proof producers

Spec 010 adds separate default-branch verification/review workflows and publishes the prepared merge-authority workflow that was absent from PR #50's merged tree. `FACTORY_AUTHORITY_ENABLED` remains unset; both workflow-level and policy-level activation gates must be explicitly enabled after setup. They remain off until `FACTORY_PRODUCERS_ENABLED=true` and an approved enabled policy exists. Merge enablement remains a separate switch; this package neither restores paused legacy reviews nor claims a live authenticated shadow run.

Each workflow uses `pull_request_target` for its protected definition, checks out the protected commit, and never checks out PR code with Actions checkout. GitHub's [security guidance](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target) explains this trust boundary. The verifier fetches the exact candidate into a separate directory and executes only protected per-AC argv in a non-root, read-only, capability-free Docker container with no network or credential mounts. Logs, exit codes, image and argv are hashed into retained observations. Resource, time and aggregate proof limits fail closed. Container configuration tests do not substitute for the live isolation/shadow drill.

The independent reviewer receives the complete approved spec and full before/after text for every changed file. Binary or oversized candidates block until an approved adapter or smaller candidate is available. Claude tools and project settings are disabled; GitHub and factory credentials are removed from its environment. The reviewed default is `FACTORY_REVIEW_PROVIDER=oauth`, using the existing subscription after its reset on **13 October 2026, 21:00 Australia/Sydney**. There is no automatic paid fallback. CLI version 2.1.295 and official action commits are pinned.

Each producer creates a candidate-head status with a link to its authenticated run and uploads `factory-verification-pr-<number>` or `factory-review-pr-<number>`. The check succeeds only if proof generation and artifact upload succeed. The coordinator follows that check's run link, verifies protected workflow ID/base/runtime hashes and exact candidate/artifact bindings. This avoids selecting another PR's latest target-branch run. All transitive scripts and the workflow itself must be protected and hashed. Existing structural receipt validation still applies.

## Approved policy entry

Before activation, register each pilot spec with:

- `path`, `sha256`, full `ac_ids`, and explicit `allowed_paths`.
- `verification_image`: an approved image reference ending in `@sha256:<digest>`, with the actual test toolchain preinstalled. Candidate commands have no network access to install dependencies. The current checkout fetch supports public GitHub repositories; private-repository fetch requires a separate credential-isolated adapter before adoption.
- `acceptance_commands`: one explicit argv array for every AC, approved independently of the candidate.
- Distinct producer workflow IDs; event `pull_request_target`; check names `factory-verification` / `factory-independent-review`.
- Hashes for the role workflow, `factory-producer.py`, `factory-producer-check.py`, `factory-coordinator.py` and `validate-candidate-evidence.py`.

The App key belongs only to the main-only `factory-authority` environment. Producers receive no key and no merge authority. Preflight reports incomplete entries. Do not use fixture image hashes, fake PASS artifacts or local implementation proof as live producer evidence.

## Remaining order

Complete App registration/install and working reviewer capacity, approve/pin a pilot spec and image, restore review protection, and prove positive and negative shadow candidates. Then finish F-04 durable claims/supervision before unattended parallel auto-merge. F-05 digest, F-06 feedback, F-07 adoption/runtime/retention and F-08 service-specific production remain later packages. A production target and real health/rollback contract will be needed for F-08.


## Hosted review execution boundary

The protected pilot fixes subscription OAuth without an API fallback. Review uses a fresh neutral HOME/config/TMPDIR, scoped tool-free safe mode and no persisted session. The protected workflow hands off absolute Node and pinned CLI wrapper paths; the reviewer invokes Node directly, so neutral PATH does not rely on an inherited npm executable or shebang. Prompt bytes travel through private file-backed stdin; independent output streams are limited to 1 MB each during execution, with a 300-second deadline and owned process-group cleanup. A verdict requires the exact `claude-sonnet-5-5` modelUsage and valid structured result. Reported client cost remains an estimate, not subscription spend.

Claude PR Review and Claude Security Review were restored on 2026-10-16 after the approved date and a successful exact-model Claude Max probe; PR105 contains the merged Sonnet5.5 runtime. Local subprocess fixtures and that local probe are not independently authenticated factory verdicts. Protected producer enablement follows publication of the reviewed shadow policy, so genuine verifier/reviewer receipts can be obtained. Authority stays in shadow mode and merge mode remains disabled pending real shadow proof and the separate human decision.

The operator-selected local reviewer, `/review` skill and three hosted review paths use `claude-sonnet-5-5`; other local roles retain their selections. The bounded Claude Max probe established model availability only. Fixture acceptance proves execution and validation without a live model request; it does not provide an independent hosted verdict or merge approval. Refresh protected source pins from the merged runtime revision before shadow activation.

## Signed protected execution provenance

REST `pull_request_target` run `head_sha` identifies the immutable candidate; it is not the protected checkout revision. Run `pull_requests` associations can change after the run, so neither their base nor head supplies execution provenance. Producers require the actual checkout, `GITHUB_SHA`, `GITHUB_WORKFLOW_SHA`, protected workflow/ref/repository/run/attempt and current PR base to agree before provider or candidate execution. Local protected runtime bytes and the protected/candidate source hashes must match policy pins.

Each successful producer signs the exact `evidence.json` with the pinned official `actions/attest` action and uploads its bounded signature bundle alongside evidence and hash-addressed observations. The final candidate check requires successful proof, signing, bundle preservation and artifact upload. The coordinator verifies the artifact's GitHub run metadata and ZIP digest, then uses bounded `gh attestation verify --bundle` with exact repository, certificate identity, OIDC issuer, source ref/digest, signer digest and hosted-runner restriction. It additionally requires certificate-derived workflow, execution source, event and run/attempt claims; user-controlled predicate provenance cannot substitute for these claims. Existing spec/policy/AC binding rejects stale same-head evidence after a base change and forged artifact bases. There is no unsigned protected-producer fallback.

Signing requires explicit `id-token: write` and `attestations: write` permissions in the two producer workflows. This source preparation does not enable either job, merge mode, production delivery or the factory App. Refresh complete producer and receipt runtime pins from the reviewed merged revision before any fresh pilot run. Public repositories support GitHub artifact attestations; private/internal adopters require GitHub Enterprise Cloud capability. Unsupported adopters remain blocked rather than silently losing provenance guarantees. A separate reviewed private-compatible mechanism would be required to remove that prerequisite.

Offline acceptance uses injected verified-certificate results to test policy enforcement and actual bounded ZIP/context handling. A genuine official GitHub CLI public signed fixture and tampered-subject pair establish CLI/cryptographic compatibility only; they are not a factory producer attestation, authenticated review or live shadow eligibility proof. The public pilot remains a separate required gate, and the user decision about attestation portability is recorded in the activation review package.

## Complete policy-observation runtime coverage

The protected runtime closure is eight files per producer role: its workflow,
producer, producer-check helper, coordinator, provenance helper, bounded-process
helper, candidate-evidence validator and policy-observation helper. Every byte is
pinned in protected policy and checked against both execution source and candidate
source. Omitting or changing the observation helper rejects the candidate. The
helper reuses the already included bounded-process module; it adds one dependency.
Metadata preflight requires all eight paths. It does not authenticate key material
or establish hosted proof simply because declared configuration is complete.

The receipt emitter closure is seven files, adding the observation helper to its
existing six. There are no configured trusted receipt revisions; this source repair
registers no historical runtime and migrates no active profile. The separate
Spec014 continuation must expand retained shared material bounds9→10 and its
six-path profile fixtures to seven when it integrates this source. Existing native
producer proof ZIP limits remain unchanged: the helper is pinned source runtime,
not a new arbitrary ZIP member or a candidate-supplied signature claim.

The main-only factory-authority environment supplies FACTORY_POLICY_OBSERVATIONS
as described in [activation setup](FACTORY-ACTIVATION.md#exact-administrative-observations-for-omitted-bypass-metadata).
Administrative observations are retained in a separate bounded audit artifact for
90days; receipt.json remains the only receipt ZIP member. This retention is distinct
from the approved future indefinite compact receipt archive, which is not active.
No source pin or fixture PASS proves a genuine current-source hosted shadow run.

The future archive bootstrap's App-only writer policy is not covered by this
explicit-empty observation format. Its protected bootstrap metadata model and
caller-field projection require separate reviewed integration and activation;
never inject an actor list into a live API response. Existing reporting/feedback
operation is not migrated by this source change.
