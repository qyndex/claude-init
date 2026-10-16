# T304 independent-review completion

Actual canonical RED exposes missing expected timestamp/mismatch facts. Separate
unexpected-exception-red.txt injects RuntimeError and demonstrates audit[] while
the same exception propagates; unexpected-exception-green.txt verifies retained
audit plus unchanged exception identity after the repair. GREEN42cases retain all
existing resource, sentinel, timestamp-spelling rejection and actual ValueError
CLI failure-invalidation checks. New local case helper replaces count=6; unused
contextlib removed. Shared fixture extraction remains the repository pattern.

Expected_updated_at accepts only exactly typed valid aware timestamp strings up
to40characters. Fixed nullable match flags describe typed identity/hash/exact raw
timestamp facts; invalid/missing values are unknown, not approval. Known original
ValueError messages map to fixed enums; unknown types/messages map to a fixed
unexpected category without arbitrary exception text. No second authority
validator or acceptance fallback is introduced.

Only the inner audit-and-reraise handler catches Exception. Injected RuntimeError
is re-raised unchanged. This does not claim the unchanged main CLI tuple now
invalidates prior eligible checks for RuntimeError: its existing ValueError path
is still actually tested and passes. source-invariants.txt proves validate() and
the main CLI body byte-identical to pre-T304 HEADdd891af. All16pins match exact
bytes with same8/7closure and all other policy fields unchanged/mergefalse.

Observation60/coordinator63/producers38 regressions pass, along with compile2 and
ledger/structural checks. The meaningful CPython tracemalloc frontier regression
is retained: it tests bounded allocation, not timing; its threshold assumption
was exercised locally and remains subject to actual hosted CI, never skipped.

Actual hosted App-view cause remains unproven. Parent separately captured a
public/full-operator equivalent-time representation defect for later T305 review;
T304 intentionally preserves current timestamp rejection behavior. No anonymous
response is claimed to equal the App response. No push, live settings, model or
credential changes, normalization, receipt work or authority activation.
