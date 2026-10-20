# Proposed bounded font review adapter — decision pending

This is a proposed amendment to Spec010 (protected proof producers) and Spec045
(hosted review runtime), for implementation and local verification only.

## Observed problem

The brownfield local-font repair passes its real offline production build and
27 browser tests, with one existing device-specific skip. Its seven WOFF2 files
are byte-identical to the retained baseline assets. An independent comparison
also matched all font-face descriptors, glyph metrics and document font usage.

The current protected reviewer deliberately rejects binary candidates with
`binary candidate needs an approved review adapter`. The ordinary review input
builder also assumes every blob is UTF-8. These are intentional fail-closed
boundaries; local browser success does not override them.

The complete current brownfield draft has 197 changed paths and 2,471,647 bytes
of before/after content: 2,252,759 text bytes and 218,888 font bytes. It exceeds
the protected 500,000-byte input limit before an adapter could grant any credit.
The ordinary builder's 1 MiB Git-output limit also rejects its diff. Most of the
size is diagnostic history (2,067,591 bytes under verify/), rather than code.
Facts: /private/tmp/factory-brownfield-local-font-review-context-20261020/capacity-and-binaries.json.

## Recommended scope

Add one explicitly registered adapter for the seven existing Inter WOFF2 assets.
Compact diagnostic history losslessly, or split candidates where needed, while
preserving current review limits. Do not introduce general binary acceptance,
larger prompts, omitted source, automatic registration or extra model calls.

### Acceptance criteria

1. Only protected-main, repository/spec-bound configuration can select the
   adapter and pin each asset's exact path, SHA-256 and byte length. Pin its
   license/provenance and expected face metadata. Candidate content, extensions,
   environment variables and PR prose cannot approve assets.
2. Both ordinary and protected review preparation handle only registered,
   hash-matching WOFF2 blobs through the adapter. Review input records immutable
   before/after object identity, exact digests, lengths, approved metadata and
   the protected registration binding. CSS, layout, tests, license text and all
   other textual source remain completely represented. No host font execution.
3. Unknown binaries, changed bytes, renamed paths, invalid registrations, wrong
   lengths/magic, missing provenance and candidate-supplied approvals fail
   closed before a model call. Existing text-only behavior stays compatible.
4. The trusted verifier independently checks the exact assets and runs the real
   local-font/browser contract in the bounded container. Static model review,
   binary metadata or local historical proof alone cannot establish native
   acceptance. Reviewer/receipt evidence binds the adapter and asset manifest
   to the same policy, spec, source head and verification observation.
5. Existing per-call, process, output, usage and aggregate input limits remain
   unchanged. Oversized candidates still block. Diagnostic archives must retain
   every original byte and original-path/digest inventory, have bounded safe
   extraction verification, and leave source/tests/specs/plans, readable
   findings, TDD RED/GREEN and full generated acceptance blocks available.
6. Genuine RED/GREEN covers each rejection and compatibility path. Independent
   review checks complete coverage and byte preservation. Local actual Linux
   font/browser outcomes remain distinct from hosted authenticated acceptance.

## Authorization boundary

Approval A permits this amendment's implementation and local verification.
It does not permit publication, merging, protection changes, protected registry
installation, activation, image publication, credentials, additional model-call
budgets, network relaxation or production. Any live cutover needs its concrete
reviewed source/configuration package and native proof. No adapter is implemented
or activated by this proposal; the existing gates remain in force.

## Options

- A — Approve this narrow adapter amendment for implementation/local verification
  (recommended). This supports the actual assets while preserving fail-closed
  defaults and current resource limits.
- B — Keep binary review unsupported and leave brownfield activation blocked.
  The local repair remains available, but it cannot receive autonomous review
  acceptance under the current policy.
