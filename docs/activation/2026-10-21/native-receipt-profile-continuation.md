# Spec014 native receipt profile continuation

Continues plans/active/014-authenticated-receipt-recovery.md without changing
its historical execution record.

### Approved additive native-source profile, 2026-10-21

T-347 adds only `merge-native-source-20261020` to the protected source registry.
The two existing profiles and empty legacy map remain unchanged. Local fixtures
verify the current seven-file source closure and canonical policy, reject missing,
wrong, ambiguous and revoked profiles, and preserve historical annotations.
Existing receipt suites retain current-task, archive-origin, signature and
checkpoint isolation checks. These fixture observations are not hosted signed proof.

Publication, merge, protection changes, profile activation and protected signing
remain separately pending. The eventual cutover changes preflight, policy and
receipt-trust pins; unchanged-runtime maintenance cannot restore this upgrade.
No application profile, image, budget, provider or acceptance command is assigned.

Canonical implementation plan: `plans/active/014-authenticated-receipt-recovery.md`.
