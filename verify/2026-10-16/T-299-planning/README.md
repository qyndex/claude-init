# Protected-main merge and T299 planning checkpoint

On 2026-10-16 this branch merged actual protected main
`6a004bc6d926e16f9b09efe949fbb8b50a843eac` without rebasing original
T275–294 commits or replacing their durable evidence. Parent confirmed PR110
merged with twelve checks restored. This is source integration and planning only.

TASKS conflicts were resolved under `with_tasks_lock`, preserving the union and
existing statuses. The ADR index preserves the receipt branch original bytes as
an exact prefix, appending only main ADR0008; ADR0007/0008 each occur once.
`analyze.txt` records actual DAG/status/index assertions and AC/task mapping.
`structural.txt` records the actual harness validator. The ignored analyze014
marker was refreshed with PASS for planning consistency only.

`imported-baseline.txt` records an actual archive-suite run after importing main:
exit0, 31 cases. This is neither a T299 RED/GREEN pair nor proof of complete
cross-version compatibility or all receipt regressions. No profile/archive code
was repaired during the merge. Imported runtime changes are the approved main
changes, including the current seventh receipt runtime dependency.

Pending T299 must support authenticated historical six-file retained facts through
current seven-file readers using strict reviewed merge-time closure families and
profiles. Current ingest must reject missing current helper bytes; selected trust
failure must never fall back implicitly to legacy. Revocation must annotate old
facts without erasing them or granting runtime task credit. T299 depends on T294
and T292; T295 depends on T294 and T299. Parent T286 remains pending.

T295 projection, T286 aggregate, T288 loader/campaign integration and actual archive
App-writer capability/hidden metadata/credential cutover remain pending. No live
profiles, state, credentials, rules, flags, merge mode or production authority changed.

T299 must allow reviewed historical six-file profile entries (including revoked
entries) alongside current seven-file entries in the protected trust document; an
old entry must not invalidate the whole document. Actual current source
authentication/build_record must still require all seven current dependencies and
exact selected pins, with a positive ten-material case. Retained integrity uses
its authenticated original known closure/material family, not a global current
tuple. Report-only historical compatibility is required; new six-file legacy
imports need not be broadened if unsupported and that limit must be explicit.
