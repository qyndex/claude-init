# Reporting acknowledgment resume investigation

Base: a76b258353c0c692a80c0e40ae0ccf4d2cb4c246. Private isolated checkout; no native configuration or reporting state mutations.

Spec014 AC7 requires bounded restartable reporting and visible coverage gaps, with no cursor past unresolved work. AC8 preserves non-forced CAS/restart and encrypted sibling state. The plan requires fresh source observations and current revocation before complete coverage. It does not require rebuilding a newer source epoch after every interrupted acknowledgment; that exact behavior was an implementation comment.

Scheduling selectors are not coverage authority. Retry may retain an authenticated verify journal only after existing origin, policy, trust, publication and selector checks. The hosted consumer must run actual project/coverage again before exact acknowledgement. Incomplete coverage must separately route through ordinary maintenance recovery, which resets stale verify scheduling only after those same fresh checks. Incomplete origin may delay either operation; it cannot grant credit or delivery.

Historical source pins remain immutable: neither receipt trust nor operational profiles are changed here. These two Python modules are not receipt-emitter runtime pins. Operational producer/retainer inventories name their historical exact bytes; future signer registration may require separately reviewed updates, while existing retained proofs continue using their exact immutable source.

Initial fixture setup AttributeError is preserved as setup-error.log and is not a defect RED. Initial genuine red/green pair uses the first actual hosted acknowledgment interruption fixture. Later expanded tests add resumable selection, consumer refusal, changed trust/policy, wrong selectors and ordinary maintenance controls; no synthetic verifier output is claimed native.
