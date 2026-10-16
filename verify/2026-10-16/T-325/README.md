# T325 — timestamped Actions command markers

Independent Sonnet review of ceae9f5 requested changes. The parent independently
reproduced the defect with actual public Actions job116777712471: runner
`[command]` lines reached JSON parsing. Safe selected reproduction/review metadata
are retained here, without raw job logs. This proves log-format incompatibility,
not live queue delivery or the prospective pilot's success.

Actual RED exercises the known timestamped `[command]/usr/bin/git version` format
followed by valid safe CLI result lines. The original parser raises ValueError
while attempting JSON decoding. Only after that failure, the implementation adds
a guard for the exact timestamp-prefixed `[command]` runner marker. Existing log
byte limits and all result JSON validation remain unchanged. The timestamp is
format recognition, not cryptographic evidence of origin.

GREEN adds one positive and five negative cases to the original35 source cases:
41 total. Unknown bracket markers, unprefixed command markers, arrays, malformed
objects and duplicate result keys still reject. Existing extra/duplicate result,
unprefixed JSON, byte/call bounds and credential isolation tests remain. Full
observe_runs fixtures now include the actual command marker before safe output.
The offline CLI11/source41/real Git journal12 regression shell passes. Compilation
also passes. Process-inspection permission is for fake child cleanup only; no
live GitHub or Slack calls, source push, settings or credential changes occur.

T317's first collector/aggregate attempt remains archived and pending. Its
artifacts and characterization marker are deliberately excluded from this repair
commit. Fresh independent review and committed-source collection remain required.
Full AC8/live T318 remain pending; these fixtures provide no live rollout credit.
