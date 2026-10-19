# Scoped Sonnet5.5 diff review

**Findings (diff-only review; the surrounding code isn't visible, so the first two are unverified)**

1. **Medium, `factory-git-state.py` ~L563-566: the rebuild isn't gated on a genuine coverage failure.**
   - `maintenance.maintain(...)` runs whenever `coverage_complete is not True`, and its result is ignored.
   - The comment says an interrupted acknowledgement alone keeps its selectors. The code can't tell that case apart from a transient or other incomplete projection.
   - In the maintenance change, a `verify` journal without `reporting`/`selecting` resets to `backfill`. That is the discard behavior the patch is meant to avoid, so a valid campaign can still be thrown away.
   - If the source keeps changing, the cycle is verify, then backfill, then incomplete, with no convergence guard.
   - A raise from `maintain` also replaces the `projection-pending` return.
   - Please confirm that `coverage_complete=False` can only come from a fresh failed validation. Otherwise pass an explicit reason or epoch comparison, and handle exceptions.

2. **Medium, `factory-reporting-maintenance.py` ~L175-179: the new early return in `verify` may skip freshness checks.**
   - It returns `projection-ready` with the existing `history_head` and `campaign` when `reporting or selecting` is set.
   - I can't see whether this path is reached only after the origin, trust, policy and source-epoch comparisons that precede it. The AC-7/8 requirement is fresh origin, trust, policy and revocation before delivery.
   - The `ack-resume` test covers trust, policy and ordinary changes. It does not cover revocation or an origin change.
   - `interval_scoped=True` is set unconditionally. Verify that it matches the journal's actual scope.

3. **Low/Medium, `factory-reporting-maintenance-liveness.sh` `stale-source` case: the assertion can pass without exercising the bug.**
   - If `before['phase']` is already `backfill`, `after=before` and the final `assert after['phase']=='backfill'` is vacuous.
   - The test should assert that the journal was in `verify` with a stale campaign before the retry. Alternatively it should fail when it sees `backfill` early, so the RED/GREEN distinction is real.

4. **Low, same file: the `ack-resume` fixture is weaker than its stated purpose.**
   - The synthetic refusal fires on the first `project` call, before any acknowledgement (`not blocked`). It therefore exercises the rebuild path, not "refusal after an interrupted acknowledgement keeps selectors".
   - The `source_epoch` equality check does not prove that no backfill reset happened, since a reset can leave the epoch unchanged. Assert the journal `phase` and `campaign` across the retry.
   - The fixture also replaces `importlib.util.spec_from_file_location` globally and never restores it. Also check that the module-level `archive.advance_origin` patch is restored on every path.

5. **Low: the `all` runner may mask failures.**
   - The appended `bash "$0" ack-resume` and `bash "$0" stale-source` run only if the earlier `python` heredoc exits and the script isn't under `set -e`. Confirm `set -e` or explicit status propagation, so a failing earlier case can't be hidden by the final command's exit status.
   - The `ack-resume` selector also falls into the `quiet` tail assertions, so it does extra work.

No secret, injection or environment-mutation issues were seen in the visible diff. The test restores `trust` bytes and the git ref in `finally`.

## Independent full-context adjudication

No remaining production blocker found. Actual false coverage is returned only for protected projection/coverage pending; API errors fail closed. Typed projection commits only after full validation. The selector retry follows current origin/bootstrap/binding/journal/policy/trust guards; selectors remain scheduling-only and current projection/coverage plus exact acknowledgement still run. A fixed stale-source case may already be backfill because recovery occurred inside the first actual consumer call; the retained partial-fix baseline RED establishes the regression. Epoch is captured at the acknowledgment interruption after the separate refusal, so final-ready sameepoch excludes campaign rebuilding. Import monkeypatches are fixture-process scoped, and the shell header has set-euo-pipefail. Final all-case acceptance is the actual green.log, not inferred from earlier cases.
