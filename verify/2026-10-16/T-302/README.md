# T302 — frozen projection aggregate review and idempotent stage repair

Reviewed base7f065bb09e2fd3f46ef9b0bc3807c4878a6c9a5d: bootstrap caching remains
invocation-only for immutable exact-SHA objects, with fresh mutable origin/trust
checks and unchanged numeric budgets/256-ancestor bound. The shared merge-time
helper still authenticates retained materials and exact repository/PR merge
identity. Fixed SQL remains reporting-only, rejects foreign schemas/rows, and
never grants task credit or treats SQLite as source authority.

Aggregate inspection found a real availability defect. T308 legitimately keys
stage hints by requested work limit. On a one-reference window, both limit8 and
limit1 therefore publish the same authenticated fact under distinct hint keys.
The actual producer re-entry succeeded in the regression; a fresh reconstruction
then failed with `reconstruction conflicting duplicate stage reference`.
The canonical red.log captures this failure before the production repair.

The minimal repair independently reauthenticates each overlapping reference,
retained material and exact PR merge time, then permits only canonically identical
derived facts. Every stored stage fact is still compared against those derived
facts. A contradictory overlap rejects before SQL changes, preserving existing
SQLite bytes. Distinct execution/task indices are not duplicated. There is no
winner selection, authentication skip, authority or schema expansion.

The aggregate fixture uses129 authenticated synthetic records, actual Git
checkpoint/stage history and separate fresh Python interpreters/SQLite files.
Most fixture stages are batched setup, not claims of129 live producer-issued
receipts; the new overlap is an actual stage_projection call. Current revocation,
128 interval-selected facts/129 historical facts, missing/tampered proof, privacy,
foreign SQL and unproven cache rows remain covered. Historical facts outside the
requested interval are retained, not assigned invented times.

No live API/Slack calls, credentials, activation, source push or new-main import
occurred. projection_complete concerns only the selected frozen interval;
coverage_complete remains false and the unchanged256-ancestor integration gap is
T310. This does not establish1000-delivery or unbounded reconstruction capacity.

The first regression command used the nonexistent factory-receipt-stage.sh name;
its exit127 is retained in stage-regression.log, not counted as a source failure
or successful check. stage-regression-corrected.log uses the actual approved suite.

Final results: canonical GREEN11 case groups; stage regression17; retained-proof
regression20; compile passed; structural validation passed with four existing
warnings. The final full aggregate exited0; all owned test sessions terminated.
