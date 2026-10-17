# T287 reconstruction capacity repair — proposed equivalent transport

Status: PROPOSED for parent review. No new archive origin authority, live settings,
credentials or permission grants. The observed failure is real: 380 retained
records, all48 protected windows staged, fresh reconstruction exhausted2048GETs
while reading stage/index blobs. Evidence: lineagecache-consumer-diagnostic.log;
actual complete stage history: t287-lineagecache-consumer-result-20261016.

Options:

1. Exact-commit ZIP/pack. Verify every blob/tree against independently authenticated
Git identities and bound compressed/uncompressed bytes. This reduces calls but
reads unrelated opaque report/feedback ciphertext, downloads every historical
record, and eventually makes the32MiB entire-store threshold a lifetime cliff.
Not recommended as the normal reporting transport.
2. Fixed same-repository immutable Blob batches (recommended). An internal query
capability retrieves only requested40hex blob IDs discovered from authenticated
strict archive trees. It has no arbitrary GraphQL/endpoint/mutation passthrough.
The fixed GitHub.com GraphQL POST is a query, not a write operation; all existing
ref/protection/PR reads stay REST/fresh. Same existing Contents-read capability,
no new key/token permission. Actual reporting-App compatibility remains a later
protected probe, never inferred from a local fixture.
3. Protected projection capsules across invocations. Feasible but changes storage
schema and retained-proof validation composition; more moving parts and a wider
review than an equivalent immutable transport. Defer unless selected interval
bytes, not request count, are the next demonstrated blocker.

Minimal contract for option2:

- Strict protected repository name AND numeric ID; no rename-following or foreign
object source. Fixed bounded query aliases, max32 per request, exact alias set.
- Only archive100644 JSON leaves, exact SHA and known size, never report/feedback
content. isBinary must be False, isTruncated False, typename Blob, text actualstr,
UTF8 byte length == byteSize == expected size, Git blob SHA matches requested ID.
- Reject GraphQL errors, partial/null/extra/duplicate aliases, mismatched identity,
unsupported transport and response/call/byte exhaustion. No invalid-response REST
fallback or permission escalation. All transport bytes share2048calls/32MiB;
individual response stays2MiB. Batch planning also uses known leaf sizes.
- Per-invocation cache only, byte bounded, fresh copies; no persistence claiming
origin. Each existing retained_record/material/schema/profile/revocation check
still executes. Batch-prefetch stage documents, then referenced records/indices,
then deduplicated material wrappers; dependency discovery remains bounded.
- _retained_time_from_anchor already requires independently authenticated and
finally rechecked anchor. Reuse its exact repo binding, validate each fresh PR's
base repo identity/number/merged/exact merge SHA/timestamp, and finalfresh bootstrap
repo/ref/protection. This avoids1001 redundant repository GETs without globally
caching mutable metadata. Transport failure/time-unavailable remains a gap.
- Ordinary small callers can use unchanged REST; large reconstruction explicitly
requires the supported batch capability, without pretending failed GET fallback
is complete. T288 must wire the concrete hosted adapter, not leave fixture-only
scale support. Exact integration scope must be recorded before implementation.

Proof before completion: actual realGit multi-object response SHA/bytes agreement;
strict forged/null/truncated/foreign/binary/errors/alias/size and bounded process
negatives; current PR/repository/ref/policy drift still rejects atomically; compare
before/after actual request+byte counts. Fresh full1001append/origin/window/stage/
SQLite/source-coverage composition remains mandatory. No mock budget resets,
SQLite trust, archive pruning, hidden historical gap or lifetime-scale claim.
For larger selected intervals32MiB remains an explicit per-invocation limit;
progress/indexing must select relevant protected windows rather than downloading
all lifetime data. A demonstrated byte-bound blocker requires a separate concrete
continuation proposal, not an inflated guard.

Primary references inspected (2026-10-16):
- https://docs.github.com/en/graphql/reference/git#blob
- https://docs.github.com/en/graphql/reference/repos
- https://docs.github.com/en/graphql/guides/forming-calls-with-graphql
These document Blob integrity fields, repository queries and query/mutation
semantics. No actual reporting-App or private-repository capability claim.
