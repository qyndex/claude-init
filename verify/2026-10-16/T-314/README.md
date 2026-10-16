# T314 — bounded protected queue observations, corrective rework

The initial implementation attempt was NOT compliant original fail-first TDD.
Its first command failed on an accidentally future fixture cutoff, then source
was prepared before that setup failure was recognized. Its retrospective baseline
replay is not relabelled original RED. Root required discarding that candidate:
attempt-1 retains the entire discarded source and every initial/retrospective log.
rework.md records exact commit/source/test hashes and chronology; nothing erased.

Source was restored byte-exact to 323f3e9, corrected tests then produced NEW actual
missing-observer RED at 13:08:53. A fresh _QueueReader implementation was written
AFTER that RED without restoring/copying quarantined source. Root reviewed this
corrective sequence and source. Supplemental future-clock-red.txt demonstrates
supplied now=actual UTC + 1 hour was not rejected; minimal clock guard fixes it while
historical fixture clocks remain supported. Final GREEN: 33 cases is actual, not
fabricated earlier evidence. Root independently reran 32 cases and later all 33 cases before task completion.

Observer accepts no caller health/run IDs. It reads actual same-repository/default-
branch workflow path/IDs and five supported nonterminal status queries, validates
exact run repository/head-repository IDs, branch/event/path/attempt/head/time and
fixed attempt-job metadata, then repeats complete metadata/health observations.
Run pages<=2/query,100/page; total>=1000 is saturated/unknown, not filtered-history
completeness. Global limits: 16 active runs, 64 jobs, 100 steps, shared 128 calls/32 MiB and existing
raw transport bound are fail-closed controls. Short/inconsistent/duplicate counts,
foreign/missing/changed metadata, invalid/future clocks, disabled workflows,
unknown schema, inaccessible API, protection or budget failure never means healthy.
Primary status/cap reference: https://docs.github.com/en/rest/actions/workflow-runs

Old unstarted waiting digest plus pending ordinary alert fixture is observed as a
stalled eligible worker; current or recently updated metadata is conservative
metadata-current only. Latest known activity controls grace; no exact concurrency
owner or deployment cause is inferred. Protected typed worker health is read
independently using its existing exact stream, without private-feedback stream
reads. No Slack API call or send; receipt_verified and recovery_eligible ALWAYS
false. T315 must independently authenticate exact current remote digest receipt
before recovery. Optional deployment context stays unknown without new permission.

actual-job-shape.json is root's selected safe actual administrative GET from
qyndex/claude-init job 116774008258/run 38838848785 on 2026-10-16. It confirms actual
created_at/run_attempt/head_sha/step status/timestamp compatibility. It is not an
actual queue incident, signed proof, live probe or Slack/recovery verification.

Final journal 60/CAS 20 regressions, fresh-process CAS fixture, Python compilation,
whitespace, structural and ledger checks retained. No T315 outbox/workflow, credential,
live variable/protection/state mutation, push or provider changes. Same-environment
blockage and Actions-wide outage remain limits. Task completion is local only.

Final self-review found workflow lookup IDs lacked the existing int64 bound.
workflow-id-red.txt reproduces false metadata-current for one overflow identity;
a minimal upper bound fixes it. The first all-ID-overflow fixture already rejected
as ambiguous, and its passing attempt is retained separately. No assertion is
claimed to fail when it passed. Final 33-case source was independently rerun by root.
