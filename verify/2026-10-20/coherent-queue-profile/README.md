# Coherent T344/T345 local verification

Actual source3aea4db4de8e8ffff5bf89fa38831055c50c8999 integrates only queue T344 and native-profile T345 work on verified PR131 merge9e60a678b4cf7b6ccd8b9963bad0656fbea24ff3. Both task records and all main lessons remain; no duplicate collector/T343 implementation appears in the diff.

The final producer, preflight, queue and test bytes equal their separately reviewed/tested source. Exact candidate policy changes only both producer trusted-file hash values; every other policy field and activation/profile selection is unchanged. Source-pin consistency is not live policy/profile cutover authorization, and the canonical policy binding changes. Old receipts cannot be represented as current proof for the candidate hash.

Fresh coherent preflight, seven profile controls,42 producer regressions and queue retry pass. Required full collectors ran sequentially, without skips, with the exact main comparison base: Spec010 FAIL0/5 and Spec029 FAIL0/9, both unskipped smoke0. This complete broad-spec evidence remains failed; the local controls do not fabricate full AC tags. observation.json binds the actual observed source and historical bundle hashes before refresh. The subsequent proof-only commit has no independent native CI or signed receipt claim.

Actual local Linux probe evidence remains scoped to d68e8df's unchanged producer bytes: strict/native execution/isolation controls pass. Brownfield lint/type/unit pass, but actual offline GoogleInter build fails and browser was not attempted. Original driver/setup and missing-base failures remain historical rather than productRED. Encoded probe originals are lossless with18 independent hashes; decoded raw data was independently scanned, not hidden from secret scanning.

No registry/source publication, ready transition, merge, protection/runtime/profile activation, protected log/state read, secret export, Slack or deployment happened here. A human must separately review exact public payload and any ready-for-review exception despite failed broad collectors. Any later live source/runtime/policy cutover requires its own concrete decision and fresh native chain.
