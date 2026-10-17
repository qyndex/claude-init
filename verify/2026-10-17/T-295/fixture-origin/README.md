# T295 bounded-origin fixture correction

The exact existing T295 acceptance failed in the shared verifier at source `de769cf1696cbd3c2f567c5585c643f2666cea34`. The nested 129-record projection-resume fixture published a large batched retained/stage namespace, then called ordinary bootstrap verification before completing authenticated bounded origin continuation. The unchanged guard correctly rejected its incomplete tree scan.

Approved plan 014's T-310 boundary requires bounded origin continuation for a suffix too large for one verifier invocation. Analyze 014 is PASS; the approved spec, plan and analysis input hashes are recorded in `inputs.json`. This is a fixture setup correction, not a production defect.

The only source delta is eight added lines in `factory-receipt-projection-resume.sh`: call existing `advance_origin(CachedState(), approval)` with unchanged default per-call limits, resume at most 256 invocations, require coverage to remain false, require actual multi-invocation continuation, and retain the original bootstrap assertion. No caller completion flag, copied capsule, page/call/byte limit increase, production edit, task ledger edit, or skipped case is introduced. All original SQL, interval, withdrawal, missing-history, material, privacy, schema, overlap and conflict assertions remain.

Actual verification:

- Original focused command: exit 1 in 8.521 seconds at `archive bootstrap tree incomplete; authenticated cursor continuation required` (`red.log`, `red-input.json`).
- Corrected focused projection-resume: exit 0 in 170.300 seconds; all 11 real-Git fresh-process/fresh-SQLite 129-reference cases passed (`focused-green.log`, `focused-result.json`). T302 and T309 declare this identical acceptance command; this result covers their directly shared entry without redundant reruns.
- Directly dependent stage-anchor fixture: exit 0 in 6.611 seconds; source extraction, eight-fact anchored publication, actual accounting, foreign facts and trust/approval/policy/head races passed (`stage-anchor-green.log`, `stage-anchor-result.json`).
- Exact T295 `bash .claude/scripts/test/factory-receipt-projection-windows.sh`: exit 0 in 187.335 seconds, under the existing local 600-second TDD execution configuration. It includes the public two-task chain, all 11 resume cases, 11 runtime compatibility cases and 6 historical/current integrity/origin cases (`full-green.log`, `full-result.json`). Executing hashes stayed unchanged throughout. This is a local full-command result, not a claim of a separately run CI job.
- Structural validation: exit0 with four unchanged unrelated warnings: three disabled intake hooks are unreferenced in settings, and the legacy T-111/T-114 acceptance is a no-op (`validate.log`).

Independent read-only review of the exact eight-line delta found no blocker; that reviewer did not execute tests or edit source. The diff and its digest, before/after input hashes, and unchanged-production/ledger checks are retained in `source.delta.patch` and `inputs.json`.

No 1001-entry generation, full shared verifier rerun, native API write or live activation was performed for this correction. The fixture still explicitly represents batched local test publication, not 129 live merges or engineering/task credit. Parent integration and sanctioned T295 ledger closure remain separate.
