# T305 lossless timestamp-equivalence repair

Canonical RED replays full safe semantic fields from actual captured anonymous
and operator GitHub GETs and reproduces rejection despite equivalent instants.
The fixture stores actual source response digests, the original lexical hash and
actual_app_view=false/native_attestation=false. It is not a live App response or
operator approval installation. GREEN33cases accepts the same snapshot with a
fresh canonical observation and rejects the actual old1cb lexical hash for both
hidden source spellings; no old-hash fallback exists.

precision-red.txt separately proves the old parser silently truncated a seventh
fractional digit. Strict ISO aware parsing now rejects unsupported precision and
invalid offset hours/minutes before fromisoformat. Canonicalization uses exact
UTC datetime/microseconds only for created_at and updated_at; no float epoch,
other-field normalization or identity/actor/settle relaxation. Tests reject1µs
created/updated/observation drift, unsupported7digits even trailingzero, invalid
offsets/date/missingzone, fractional settle and future boundaries. Supported
alternate offset/microsecond forms pass and input snapshots remain unchanged.

Raw diagnostic timestamps and component fingerprints remain available. Match
flags explicitly distinguish updated_at_raw from updated_at_instant, so lexical
spelling differences cannot be mistaken for authoritative semantic mismatch.
T303/T304 spelling-rejection evidence is accurate historical pre-T305 behavior;
the diagnostic regression is intentionally updated to semantic acceptance here.

Regressions diagnostic43/observation60/coordinator63/producers38/provenance42
passed. Compile and policy pin checks pass: exact16runtimepins, unchanged8/7
closures, all other policy fields exactunchanged/merge_enabledfalse. Ledger and
structural results are retained. No anonymous==App claim, live source rollout,
observation variable update, credentials, settings, push or authority activation.
Actual full-GET recapture after reviewed deployment and protected App proof remain
mandatory. The independently demonstrated public timestamp defect is the sole
basis for this narrow normalization; no other metadata is guessed or weakened.
