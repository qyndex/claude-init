# Historical queue completion proof (inactive template)

The shipped `factory/operational-proof-profiles.json` contains no profiles. Neither
workflow runs unless `FACTORY_OPERATIONAL_PROOF_ENABLED` is exactly `true`.
Registration, main-only environment protection, runtime hashes, exact bootstrap,
App access, native signing and live acceptance remain separately reviewed T339
work. This document does not authorize enabling them.

A future protected profile selects one repository identity, default branch,
original source/workflow/runtime, three exact native run/attempt selectors,
queue configuration, frozen original state/ancestor bootstrap, retention bootstrap,
and separately reviewed producer and retainer workflow/runtime families. Each
runtime family is exactly every top-level `.claude/scripts/*.py` at its immutable
source plus that role's workflow. Profiles do not pin their own registry commit:
native run/certificate identity resolves the exact allowed source. The entire
validated entry is SHA256-bound into both signed subjects. An entry's semantics
cannot reinterpret an earlier record. Register a new profile identity for a new
historical observation; retained role contents cannot be overwritten.

The signer is `workflow_dispatch` on protected current default-branch code in the
main-only `factory-operational-proof` environment. It re-reads original native
attempts/jobs/raw logs, hashes exact reviewed source bytes, and validates the frozen
journal's actual protected-state ancestry and bounded immutable transitions.
Current run APIs,32MiB/128-call source limits,2MiB responses,24 historical commits
and1024-entry directory bounds remain in force. Administrative notification counts
are not independent Slack readback or exhaustive history coverage. Original times
are preserved; producer verification time is recorded separately.

The signer signs one canonical record, uploads exactly `evidence.json` and
`provenance.sigstore.json` with90-day retention, and finishes. Its permissions are
Contents/Actions read and OIDC/Attestations write. It receives no reporting key.

The protected `workflow_run: completed` retainer independently authenticates the
successful exact upstream attempt/job/artifact and first certificate before
preparing a second purpose-bound completion observation. That subject binds the
original record and bundle hashes, native completion window/job/artifact, full
profile hash and retainer execution identity. The retainer signs that already
completed observation, then verifies both signatures before App-scoped CAS. It has
Contents/Actions read plus OIDC/Attestations write. This signing permission is a
source-design change, not a live permission approval. Its own eventual final status
is not asserted; demanding it would create a completion cycle.

Only the final retain step receives the dedicated reporting App token; the key is
referenced only by the pinned mint action in main-only `factory-reporting`.
App mode is mandatory with no credential fallback. Existing fixed protected
receipt/archive configuration authenticates state origin. The opaque role is
`reports/<sha256>.json`, domain-separated by repository/profile/original source.
The envelope holds both subjects and both bundles, capped at1MiB so existing
base64 Git blob responses remain below2MiB. No delivery/archive leaf schema changes.
At most three non-force CAS attempts reconcile authoritative state. Identical
upstream evidence with a different valid observer completion is a quiet retry;
existing valid bytes remain unchanged. Missing roles after an unapproved bootstrap,
wrong upstream evidence, corruption, revocation or unresolved writes fail closed.
Opaque encrypted feedback and other worker blobs are preserved via `base_tree`.

Durable consumers must independently load the current protected active profile,
validate the recorded immutable source families, and verify both native
certificates with `verify_durable`. They must not trust an unsigned cached native
run response, a candidate registry or a source SHA merely because it appears in a
record. Run metadata is required when making the completion observation, not
forever: both signed subjects/bundles survive Actions run/artifact retention.
Historical proof is never current readiness, delivery, task, merge or production
approval. The original current-source live checker remains unchanged.

Actual attestation verification requires gh>=2.93.0 because of
[GHSA-8xvp-7hj6-mcj9](https://github.com/cli/cli/security/advisories/GHSA-8xvp-7hj6-mcj9).
Older installed CLI versions fail before native verification. Local tests use
explicit synthetic verifier output and real Git fixtures; they establish no
native Sigstore/App/private-repository capability.
