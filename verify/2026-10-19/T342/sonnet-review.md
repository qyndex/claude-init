# Source-only Sonnet5.5 review

Actual tool-free subscription review; no native receipt or live root-cause proof.

**No blockers.** This is a review of the pasted diff, context and test only. The working directory is empty, so I did not run the test or the code.

**Checked and holding**
- **Guards:** every `require`, the validate call, the origin comparison and the return value are unchanged and in the same order. `current` and `body` are only read after the `try` completes normally, so scoping is fine.
- **Original exception:** the bare `raise` keeps the same object, type, args and traceback, with no extra frame. The attribute assignment is wrapped in `except Exception: pass`, so an exception that rejects attributes can't replace the original failure.
- **Privacy:** the only new output is `'worker-'+stage+'-invalid'`, and `stage` must be a `str` in a fixed four-element set. The attribute is not part of `str(error)` or `args`. The `_QueueObservationError`/`_QueueBlocked` override still runs afterward and isn't reachable from `worker()`.
- **Spoofing:** `worker()` overwrites `_queue_worker_stage` unconditionally. Any forged value elsewhere is limited to the whitelist and only honoured when the traceback contains the `worker` frame.
- **Error coverage:** `JSONDecodeError` and `UnicodeDecodeError` are `ValueError` subclasses, so the parse stage is covered.
- **Test:** it exercises all four stages through the real `run_queue`. It asserts exception identity for load and schema, and the message for origin. It also asserts that no state head moved and no post was sent, and that the private string never reaches the details.

**Non-blocking findings**
1. **`load` is still coarse, and it is the most likely place for the live failure.** It covers both `GitState(...)` construction, which presumably does the bootstrap, policy and state-view checks, and the `current.bytes is None` guard. If the live result is `worker-load-invalid`, you won't know which. A cheap fix is to set `stage = 'missing'` after construction and before the `require`, add `'missing'` to the whitelist, and add one test with `bytes=None`. Anything finer inside `GitState` would need separate instrumentation.
2. **`origin` also covers `state.digest.stamp(start_time)`.** A `ValueError` from `stamp` on a bad `start_time` would be labelled an origin mismatch. This is acceptable, but worth knowing when reading the label.
3. **Only `ValueError` is labelled.** `KeyError`, `IndexError` or `TypeError` from `validate` or the `body['tables']['digest_origins'][0]` lookup stay `unexpected`. That matches the existing behaviour and the live category, but a test pinning it would document the intent.
4. **Phase masking, which was already there.** When `verified_worker` calls `worker()`, the last matching frame wins, so the phase is `worker-checkpoint` rather than `worker-receipt`. The diagnostic can't tell the first `worker()` call from the receipt-proof calls. The test covers only the direct path, so a `verified_worker` case would pin down what is reported there.
5. **Test fragility and gaps.**
   - Fault injection patches `importlib.util.spec_from_file_location` and wraps the loader. That depends on how `queue_alert_runtime` is loaded.
   - The forged-attribute check only covers a frame outside `worker`, which gives phase `entry`. Adding a `ValueError` raised from a `worker` frame outside the `try` (no attribute set) would confirm it stays `guard-failed`.
   - The parse stage doesn't assert that the original exception is a `JSONDecodeError`.

This change adds diagnostics only. It does not show that the live `worker-checkpoint/guard-failed` cause is fixed. It narrows the next failure to one of four stages, or to five if you take finding 1.

## Adjudication

No blocking findings. Coarse load boundary, ValueError-only categorization, receipt-path phase masking and fixture coupling remain explicit limitations. The reviewer hypothesis that load is most likely is not an observation of private state and is not treated as the established cause. Origin category identifies its validation stage, not proof of an actual unequal origin. No guard is weakened and no state/config repair is selected from this result.
