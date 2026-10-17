# Bounded PR response shape repair

Base b4c70bc. Spec014 / T334 source followup; no task status or activation change.

The actual read-only public response observed by the parent returned 96 PRs,
2,357,503 wire bytes and failed production encoding's JSON node bound at per_page=100.
The parent's per_page=25 response returned 25 rows, 902,432 wire bytes and passed
production encoding (906,501 normalized bytes). Metadata is retained separately at
/private/tmp/factory-native-pr-shape-20261017. This agent made no remote calls.

Discovery now requests at most eight 25-row pages per invocation (200 observations).
Global calls/bytes/response/node bounds and lifetime history limits are unchanged.
Oversized sources reject; no truncation or fallback grants authority.

A shared finite layout predicate accepts only current25 and legacy100 layouts.
Legacy incompatible scratch resets only the two PR scratch tables before fresh
observations; compatible short terminal scratch still requires fresh full-page
comparison. Existing fingerprint/count/selected-payload equality remains required.

RED: actual discovery test demands query per_page=25, fails old production source
with AssertionError (red.log, exit1). GREEN: both focused scripts exit0; includes
1000/1001 rows, manual/late insertion, process restarts, pending/confirmed immutability,
shared role budget accounting, oversized page rejection, malformed checkpoints,
legacy100 baseline/compare/ready migration and byte-identical actual confirmed
payload/receipt rows. Synthetic typed checkpoint construction is not native authority.
An intermediate fixture attempted confirmation after resetting its old snapshot and
failed `report changed`; fixture ordering corrected before final frozen GREEN.

Python compile, ShellCheck, diff check exit0. Structural validation exit0 with existing
warnings. No full producer/1001 capacity stage, new live authority proof, credentials,
policy changes, native writes, or independent review claims. Parent owns integration.
