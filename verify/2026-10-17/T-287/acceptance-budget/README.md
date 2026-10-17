# T287 acceptance-budget correction

**Status: the full command passed under the explicitly authorized local600-second TDD configuration in381.911seconds.** T287 remains doing in this child checkout for sanctioned parent closure. No300-second or CI pass is claimed.

The required collector at production source `d965ac0c2e2b59cdc68f7f8f4f93ab8f62978c3c` timed out after 300 seconds, around 375 genuine retained appends. `red.log` preserves that observed failure. The first optimized acceptance still timed out at 300.004 seconds after 650 genuine appends. The second authorized acceptance timed out at 300.006 seconds after all 1,001 genuine appends, complete protected discovery/watch, and four protected stage pages (489 facts). Neither reached fresh SQLite consumers. Both failures are retained, not relabeled GREEN.

The current candidate changes only the local real-Git fixture provider. Persistent native `git cat-file --batch` reads actual immutable blobs, trees and commits. Bounded caches retain exact-object comparisons and linear path histories, including mode changes. Comparisons derive ancestry from actual parent objects; merge path-history simplification falls back to Git. Mutable refs, policies, source authentication, production budgets and receipt implementation files stay outside those caches.

Every API call and intermediate Git tree remains. A persistent native `git mktree --batch -z` now creates trees from actual base-tree entries, replacing per-tree index subprocesses. Native Git still writes blobs, every tree, commits and ref CAS. There is no shared/reused index in this candidate. The earlier second attempt used a provider-private index; its results and source hashes remain separate from this candidate. The native writer restarts after fixture `git fetch`, because a pre-existing writer can retain an object-database view that excludes a newly fetched pack. No missing-object validation was disabled.

The actual-Git equivalence suite covers binary blobs, tree/commit results, ref movement, missing-object recovery, divergent/merged ancestry, create/delete/missing/mode-only path history, native tree writes versus the original index adapter, nested UTF-8/tab/newline names, deletion with empty-directory pruning, stale base trees, opaque siblings, unchanged refs and stale CAS rejection. History-provider initialization also compares fresh/repeated/stale-base writes with the original adapter without changing the retained-history branch. These fixtures use UTF-8 paths; they do not claim arbitrary non-UTF-8 filename support.

Focused regressions preserve genuine RED/GREEN evidence for the missing persistent writer, the mode-only history omission, and the fetched-pack writer refresh. The first review source hashes, second bounded source hashes and subsequent candidate hashes are recorded separately. First-attempt review hashes identify reviewed files rather than claiming captured interpreter input byte for byte.

Targeted measurements are diagnostics, not acceptance substitutes:

- Initial 16 actual appends/origin progress: 8.481 seconds; current persistent-tree candidate: 1.997 seconds.
- Current 16 late actual appends/origin progress on a clone of genuine 1,001-entry history: 2.784 seconds.
- Two current actual stage writes on a clone of the newly generated genuine prefix: 1.018 seconds versus 1.709 seconds before native tree batching. The current measurement includes a one-time 0.445-second cold path-history load.
- Current fresh-process consumers against the unchanged preserved genuine fixture: projection 18.443 seconds, coverage 25.108 seconds; both exit 0. Their actual SQL counts and coverage outputs are retained separately.

No existing genuine fixture was modified, no fixture binary was published, and no 1,001-entry history was regenerated for targeted diagnosis. Only the explicitly authorized bounded acceptances regenerated history. The new genuine prefix is preserved at the path printed in the second timeout log. No production receipt algorithm, native provider, cloud policy, factory-bound process budget or default CI300-second deadline was changed. The separately authorized local TDD configuration is recorded below.

The declared T287 acceptance command uses the same separate-process-group 300-second timeout contract as the required acceptance runner. Only a terminal successful result from a final reviewed candidate permits restoring T287 closure. Full publication validation remains the parent task's responsibility.

## Final 300-second invocation

The explicitly authorized final invocation at frozen executing source `3889aa2d501076ce18c0121493d1d343d8c1d4ff` **failed with exit124 at300.009seconds**. It completed all1,001 actual appends and protected discovery/watch, then reached six stage pages (745 facts). The fresh SQLite and coverage consumers were not reached. `final-acceptance.json` records exact UTC timestamps, the unchanged command, source hashes, timeout and output digest; `final-acceptance.log` preserves the complete terminal output. All recorded executing hashes remained unchanged. No300-second pass or task closure is claimed.

## Authorized local600-second complete invocation

After preserving the final300-second failure, the parent explicitly authorized exactly one full invocation using the existing local `TDD_LEDGER_TIMEOUT=600` execution configuration. The runner already supports this configuration range; no source, default CI deadline, factory process/network budget, CAS rule or acceptance assertion changed. This was an explicit execution decision with no automatic retries.

The exact T287 command completed with **exit0 in381.910570459seconds** under that600-second local deadline. Executing source hashes match reviewed baseline `3889aa2d501076ce18c0121493d1d343d8c1d4ff`; checkout `5e89730422323c32fafd39b21082cf1e4f0ed9aa` adds only prior terminal evidence. The complete actual output and source/configuration/timestamp/digest record are preserved in `local-600-acceptance.log` and `local-600-acceptance.json`. The captured log SHA256 is `6d991264fde94df2ad1a38accafb0b905c5d1d4d1974c75a52f37cc9b9f849a7`.

All1,001 genuine retained appends, protected discovery/watch, eight stage pages/1,001facts, and both fresh-process consumers completed. Each of the five SQLite tables contains1,001rows. Observed-interval coverage is complete; `all_history_complete` and `task_credit` remain false. The newly generated full source/stage fixture is preserved at the path printed in the complete log.

**This proves local600-second acceptance only.** The command exceeded300seconds; default CI300-second execution remains separately unproven. This is offline real-Git fixture acceptance, not native capability, production activation or engineering-delivery certification. The parent will integrate this proof, decide ledger closure, and run its shared verification with its explicitly selected local configuration.
