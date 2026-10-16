# T336 local contract proof

Exact acceptance: `bash .claude/scripts/test/factory-operational-proof.sh`.
The original RED is an actual missing-contract assertion, not a missing executable.
The final GREEN passes 55 negative assertions. `strictness-red.log` preserves a
subsequent actual invalid-offset rejection failure before the narrow correction.
`bounded-focused.json` binds final source/test bytes and pinned interpreter to an
actual 60-second bounded runner invocation (exit 0). The ordinary ledger reports
its existing missing timeout utility warning; it is not represented as bounded.

The certificate/verifiedTimestamps output is a **synthetic verifier fixture** using
the documented gh2.89.0 / sigstore-go1.1.4 shape. No native signature, installed
App capability, Slack readback, current readiness, delivery or merge approval was
established. T337–T339 remain pending. Original notification observations retain
the original bounded administrative scope, not exhaustive history coverage.

API: `canonical(record) -> bytes`, `validate_record(raw, trusted_profile, now=...)`
and `verify(raw, bundle, trusted_profile, actual_completed_run, runner=..., now=...)`.
The profile is an explicitly trusted primitive input; later consumers must load it
from protected reviewed configuration. Records cannot select/approve their profile.
Strict root/nested schemas are implemented alongside the API. All times retain
original RFC3339 text; signing comparisons use exact nanoseconds and native end
precision. The verifier ignores predicate claims and binds the signed digest and
certificate to the explicitly expected source/workflow/repository/run/attempt.
No storage, producer, PR consumer or live CLI is implemented here.

Primary timestamp shape: sigstore-go v1.1.4 pkg/verify/signed_entity.go,
TimestampVerificationResult (type, uri, timestamp), and Go RFC3339Nano.
https://github.com/sigstore/sigstore-go/blob/v1.1.4/pkg/verify/signed_entity.go
https://github.com/cli/cli/blob/v2.89.0/go.mod
https://cli.github.com/manual/gh_attestation_verify

Focused bounded test, canonical GREEN, ShellCheck, Python compilation, structural
validation, ledger and silent-failure checks passed. Structural validation retains
four pre-existing warnings. No broad mutable-registry Semgrep scan was claimed.
