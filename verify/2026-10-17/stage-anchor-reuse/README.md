# Stage-local authenticated anchor reuse

Source base600e9ff36e4309a213c067f0d02ae31e6b1d2cc9. Spec014/T334 quota-engineering
preparation; no task closure, activation, live App or full cadence claim.

Only production change: stage_projection invokes existing private
_retained_time_from_anchor(api, anchor, store, stream, run_id, attempt) instead of
public retained_merge_time per chosen reference. Stage still verifies actual anchor,
projection lineage and exact retained record/artifact identity, and finally rechecks
fresh origin/head/approval/rawtrust before any publication. Public standalone
retained_merge_time remains byte-unchanged and retains its own initial/final checks.
No new helper API, caller ready flag, persistent cache or bound increase.

Genuine RED: actual eight-fact public stage through real RoutedAPI and local real-Git
provider produced20bootstrap validations,369requests (361writer/8source),170461bytes,
333GET/35POST/1PATCH; exits1 at excessive nested public-wrapper assertion.
GREEN: same bounded8-record shape produced4validations,241requests
(233writer/8source),141021bytes,205GET/35POST/1PATCH. Savings128writerGETs,29440bytes;
source8freshPR observations and publication operations unchanged. These actual
small-fixture measurements do not predict saved1001 quota/cadence or live provider
rate-limit behavior. Fixture authenticates records with real builder and validates
actual protected Git publication, but is not8native deliveries or producer capacity.

Eight typed fact identities, exact late merge timestamp and preserved encrypted worker
bytes are checked. Foreign PR identity and changes to trust bytes, approval bytes,
current protection or head during fact reads reject before patch. Existing17-case
stage real-Git suite passes CAS/lostack/restart/globalconflict/gap/namespace/mutable
origin guards; existing20-case standalone merge-time suite passes unchanged.

Compile, ShellCheck, diffcheck and structural validation pass (4existing warnings).
Focused scripts/source were frozen during execution. No core edits, native calls,
new paid model calls, producer regeneration, global cap changes or protocol redesign.
Parent owns integration and combined independent review.
