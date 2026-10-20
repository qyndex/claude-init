# Actual tool-free Sonnet5.5 source review

Local static review of candidate738526ec7c06f7ccbaa316eaffce5ec001134921 versus based99db50910b74692b00724cdc4bc2d7483b86fc5. This is not a native protected reviewer receipt, final-head CI result, live retry observation or whole-spec acceptance. Exact implementation/test hashes remain those in observation.json. Raw review and input hashes are recorded separately; returned findings follow with trailing whitespace normalized for Markdown; the raw JSON hash preserves original-byte provenance.

**No actionable findings.** This is a static review of `738526e..d99db50` with tools disabled. The live cause of the incomplete or changed run list is not established, and I make no claim about live retry behavior, the delivered digest, or wholeSpec029.

**What I checked**

- **Full-sweep retry, at most 2:** `runs()` (`factory-reporting-queue.py:305-313`) makes two attempts at most. `approved`, `found`, `listed`, `total` and `meta` are locals of `_runs_once`, so a failed sweep's partial state is dropped. The test's `discard-partial` mode exercises this.
- **Exact retry condition:** only `type(error) is _QueueObservationError` with `args == ('run-list-incomplete-or-changed',)` is retried. This excludes:
  - plain `ValueError`
  - other `_QueueObservationError` categories
  - extra-arg variants
  - budget errors, which are plain `ValueError`

  Both raise sites for this category (the per-page check and the `len(listed) == total` check) are covered. The final failure is re-raised with its original traceback, so `failure_details` still maps it via the `runs` frame to `run-metadata` and `run-list-incomplete-or-changed`.
- **Shared client, store, clock and budget:** the retry stays on the same `self.store` and `self.now`. `calls` and `consumed` are reset only in `read()` and `checkpoint()`, so a retry cannot refresh the 128-call or 32 MiB bounds. The budget tests are well constructed:
  - At `calls=126`, the failed page makes it 128, so the retry's `meta` request trips the bound.
  - For bytes, the failed sweep lands exactly on 32 MiB, so the retry's `meta` request exceeds it.
  - Both tests also assert that the store and clock identity are unchanged.
- **Outer guards unchanged:** `observe()` is untouched. It still runs two `runs()` and `jobs()` passes, requires equality, and re-checks health and repository after. The `late`, `partial_jobs`, and health and repository drift tests confirm these are not retried.
- **Negative cases:** the `invalid:*` kinds each fail in `run_fact` or the capacity checks with a different category and assert `sweeps == 1`. The exception-identity test covers a wrong class, a wrong message and extra args, and asserts exactly one attempt.

**Non-blocking notes (not defects)**

1. **Sweep count in `observe()`:** the bound is two sweeps per `runs()` call, not per observation. `observe()` calls `runs()` twice, so the worst case is four sweeps. Each sweep costs at least 18 requests. Together with health and jobs, this can reach the 128-call bound, which fails closed as `observation-unavailable-or-invalid`. The result is a possible `unknown` outcome, not a false-current one. If you meant "max 2" for the whole observation, the code does not enforce that.
2. **Test coverage gaps, none affecting correctness:**
   - There is no test of a retry followed by a different, non-retryable error on the second attempt.
   - There is no test of a subclass of `_QueueObservationError` carrying the same args, which the code does reject.
3. **`discard-partial` fixture dependency:** the `waiting` run is a copy of the base `run`. I cannot see the base fixture, so I cannot confirm that the base `run` has `status == 'waiting'`. If it doesn't, `run_fact` would raise `metadata-invalid` before the injected workflow-10 failure, and the test would fail instead of exercising the discard. Run it once to confirm.

## Adjudication

No actionable finding. Documentation now explicitly states two sweeps per runs() call and at most four per outer observation, with the original shared budgets. Exhaustion remains unknown. The optional second-attempt-different-error and exception-subclass coverage gaps do not change the exact rejection code; no test or code was changed for those notes. The referenced base fixture does define status waiting, and the actual discard-partial regression already passed in green.log. The returned range label is not a claim that the base ran the new test; exact candidate/base and input source are bound here. Full Spec029 stays FAIL0/9 with final unskipped smoke0; no added native/live acceptance credit.
