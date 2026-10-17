# Scoped final operational review correction

Spec029 AC9; supplemental regression proof, preserving original T336/T337/T338 canonical proofs.

Both RED runs preceded production changes: signature-red accepted a forged certificate repository identifier; inventory-red silently omitted a real Git non-ASCII Python filename. GREEN fixes bind the documented immutable numeric repository identifier in both shared signature paths and parse NUL-delimited Git inventory before rejecting unsupported Python names. Ordinary supported runtime behavior is unchanged.

Primary schema: https://github.com/sigstore/sigstore-go/blob/v1.1.4/pkg/fulcio/certificate/extensions.go lines103–104 declares SourceRepositoryIdentifier string with JSON key sourceRepositoryIdentifier; summarize.go lines24–28 embeds Extensions in certificate Summary. Fixtures remain explicitly synthetic; no actual gh/Sigstore verification occurred.

The numeric certificate binding makes the primitive explicit. The claimed recreation exploit is not demonstrated through the consumer: replay independently checks actual repository ID against the current protected registry, and signed records bind the full registry entry hash. No owner-ID field or new authority was added.

Remaining two review findings are contextual non-findings in production callers: injected runner is an internal test seam and neither producer nor replay CLI accepts a runner override; the real path always executes the patched-gh version prerequisite. completion_profile and retained_profiles construct both profiles from one independently authenticated active registry entry, sharing branch/status/full hash. A mismatched branch primitive caller cannot arise in these entrypoints. No signature or protected-profile validation is bypassed.

Existing signature-contract and historical-observation review verdicts remain changes_requested, not relabelled PASS. Parent will obtain an actual scoped independent follow-up. No native registration, activation, readiness, delivery or merge credit is claimed. T318 remains blocked on T339.
