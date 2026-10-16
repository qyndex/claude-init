# T303 failed-observation diagnostics — local implementation only

Actual behavioral RED preserves the real rejection but exposes audit[] instead of
a bounded App-view diagnosis. GREEN27cases retains component hashes while the
same metadata mismatch still rejects. Current validation SEMANTIC/exclusions,
settled timestamps, exact metadata/timestamp/identity and actor enforcement are
unchanged. Successful audit entries remain unchanged.

Diagnostic prewalk bounds canonical input262144bytes, depth32 and total visited
plus queued nodes8192 before field hashing. The supplemental queued-frontier RED
actually measured1,186,328tracedbytes for an invalid8192-key fixture; pre-extend
frontier guard makes that same bounded allocation regression pass. This resource
fixture is not hosted App evidence. Emitted diagnostic is capped8192bytes and
contains fixed categories, semantic component hashes, safe repository/ruleset
identities, expected/actual metadata hashes and valid raw/UTC timestamps. No raw
actors, rule values, unknown values, observation JSON, headers or provider output.

The coordinator constructs the diagnostic before hidden-response validation and
retains it on failure, then rethrows. Tests prove actual CLI merge evaluation
still posts failed same-head eligibility even if diagnostic construction throws.
No receipt is emitted on rejection. Existing separate90-day administrative audit
is reused; no receipt ZIP/provenance contract or permissions change.

Actual initial regressions: observation60/coordinator63/producers38/provenance42
and workflow baseline allPASS; outputs retained. Final narrow resource-guard
followup reruns are retained separately. Compile2 and workflow actionlintPASS.
All16runtimepins match actual bytes, same8/7closures; all other policy fields
remain exactly unchanged including merge_enabledfalse and no trustedrevisions.

Real hosted shadow38833564091 is still undiagnosed. Operator full-admin GET
matching saved observation does not prove App-view equivalence. Genuine protected
App-view audit after normal reviewed rollout is required before proposing any
normalization or root-cause fix. No push/settings/liveauthority/profile changes.
