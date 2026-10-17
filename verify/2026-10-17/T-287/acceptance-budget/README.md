# T287 acceptance-budget correction

**Status: incomplete; T287 remains doing.** No final bounded GREEN exists yet.

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

No existing genuine fixture was modified, no fixture binary was published, and no 1,001-entry history was regenerated for targeted diagnosis. Only the explicitly authorized bounded acceptances regenerated history. The new genuine prefix is preserved at the path printed in the second timeout log. No production receipt algorithm, native provider, cloud policy, acceptance threshold or 300-second budget was changed.

The declared T287 acceptance command uses the same separate-process-group 300-second timeout contract as the required acceptance runner. Only a terminal successful result from a final reviewed candidate permits restoring T287 closure. Full publication validation remains the parent task's responsibility.

## Final 300-second invocation

The explicitly authorized final invocation at frozen executing source `3889aa2d501076ce18c0121493d1d343d8c1d4ff` **failed with exit124 at300.009seconds**. It completed all1,001 actual appends and protected discovery/watch, then reached six stage pages (745 facts). The fresh SQLite and coverage consumers were not reached. `final-acceptance.json` records exact UTC timestamps, the unchanged command, source hashes, timeout and output digest; `final-acceptance.log` preserves the complete terminal output. All recorded executing hashes remained unchanged. No300-second pass or task closure is claimed.
