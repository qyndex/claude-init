# T339 CLI composition fixture repair

Source4188466 changes ONLY the offline CLI fixture relative approved/published1a6626a. Production bytes, runtime maps and profile hash are identical. The stub previously read argv[6] as path, so the newly explicit raw-log opt-in was mistaken for an endpoint. Both failed native harness invocations were the same fixture (direct and through queue aggregate). No failed job is relabeled.

Actual pre-edit composition RED reproduces the failure at1a; repaired GREEN runs11CLI cases,43source cases and13real-Git journal cases. The direct queue aggregate passed in20.313seconds. Three additional stub negatives reject missing raw opt-in, opt-in on JSON and unknown options. Full exact argv shape remains strict; no permissive stripping or fallback. Shellcheck/diff checks pass. An independent source review found no actionable blocker; it did not rerun these tests.

Production repair's earlier scoped Sonnet review stays bound to its original immutable input, not relabeled as a new current-head review. Fresh ordinary Sonnet checks and full harness remain required. Actual native signing/retention/replay remain pending; all four tasks stay open. PR117 remains unmerged with all12requirements in place, authority/automaticmergingoff, historical proof/retainerdisabled and ordinarywritersfrozen. No new native attempt has been dispatched.

Collectors each actually run unskipped on source4188466. Structural smokePASS; nativeFAIL0/9 remains honest. Their newly generated artifact bytes are retained under collectors/014 and029; original capture directories are documented in collector-observations.json. Existing public1a proof bytes were restored exactly and retained. Actualtimestamps/source/digests were not rewritten or backdated. PRbody attaches both latest blocks verbatim with this mapping.

The display red.log omits only trailing empty lines. Exact observed bytes and their digest are preserved losslessly in red-raw.json; source, command, output text and outcome are unchanged.
