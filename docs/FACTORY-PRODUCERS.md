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
