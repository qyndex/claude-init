# T-319 — same-run fresh-process drill deduplication

Actual RED at 13:40:47 Sydney on 2026-10-16 executed the shipped workflow shell
through a safe CLI stub and required two distinct process IDs, both carrying the
same protected run ID, attempt, SHA and `--drill`. The original workflow invoked
once and failed that assertion before source changes. Actual GREEN passes all
64 boundary cases after the minimal verification-drill-only shell change.

The first fresh CLI must succeed and report notifications=1 before the second
starts. The second must succeed with notifications=0. The existing safe JSON
notifications/reconciled result is bounded to 4096 bytes, has exactly those two
fields with bounded real integer values, and rejects duplicates, malformed JSON,
boolean counts, mismatched counts and unexpected fields. Validation prints only
the checked safe result. No caller run ID or initialization authority is added.

The actual shell test launches the CLI stub in separate processes, then executes
the shipped result validator with real Python. It proves same identity/arguments,
normal single invocation, failure/invalid first-result suppression of the second,
second-call failure and invalid result rejection, plus non-interpolation. Runtime
receipt reconciliation is not replaced by the stub: the existing 39-case delivery
suite also passes, including uncertain-history no-resend cases. This is local
contract evidence, not an actual Slack duplicate-suppression observation.

The older workflow-baseline shim needed RUNNER_TEMP and valid JSON results for
this deliberate second-process contract. Its pre-update failure is retained; the
updated fixture still executes the actual shell, checks one/two calls and fixed
arguments, and delegates result validation to real Python. Full baseline/actionlint
passes. Task scope was expanded under the sanctioned tasks lock for that fixture.

No live calls, source push, configuration activation, token changes or T320/T318
completion occurred. Normal monitoring still invokes the CLI once. A failed or
uncertain first invocation stops; it is never blindly retried by this change.
