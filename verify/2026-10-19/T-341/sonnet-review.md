# Initial static review

Actual tool-free Sonnet5.5 subscription review; not native protected proof or execution evidence.

I reviewed this statically and did not execute anything. I found no privacy leak and no control-flow regression. All of the findings below are diagnostic-quality or hardening issues.

**Confirmed OK**
- The output is a fixed `{phase, category}` pair. Neither `str(error)`, `args`, traceback text nor `__context__`/`__cause__` reaches stderr. `category` comes only from a fixed allowlist or from `guard-failed`/`unexpected`/`metadata-unknown`. `phase` values are literals.
- The exit code stays 2 in both the normal path and the `diagnostic-unavailable` fallback. The fallback is a literal string, so it doesn't depend on `json` or `Path`.
- The change touches only the `__main__` handler. Authority, retry, CAS and state paths are unchanged, and the message still says to preserve intent and inspect the protected run before retry.

**Findings**

1. **Medium: `failure_details`, `_QueueObservationError` branch (~line 685), and `observe_queue` (~line 483).**
   - `observe_queue` catches every `_QueueObservationError` and every other expected exception. It turns them into `result['reason']`, so the diagnostic's `_QueueObservationError` branch is effectively unreachable in production. Only the unit test reaches it.
   - If the live failure comes from queue observation, `run_queue` raises the generic `require(observation['status'] != 'unknown', ...)`. That reports as `queue-reconcile/guard-failed`, discarding the fixed-vocabulary reason (e.g. `run-list-capacity`, `protected-health-missing`) that was already computed and is safe to print.
   - Since the live cause is unknown, this loses the most useful field.
   - Fix: have `run_queue` raise a dedicated `_QueueBlocked(reason)` carrying only a reason from the existing safe set. Have `failure_details` allowlist it the same way.

2. **Medium: the phase walk (~lines 676-682) uses deepest-frame-wins by `co_name`.**
   - A failed or uncertain write in `QueueStore.checkpoint` that re-enters `_load` reports `journal-load`, not `journal-checkpoint`. That hides the "write uncertain, never resend or assume" state, which is the one that most needs distinguishing for retry and state safety.
   - Every failure in `main()` before `build_config` or after `execution_context` collapses to `entry`. That covers `create_api`, the `git rev-parse` subprocess, `state.API`/`http_client` construction and module loading.
   - The `run_queue` closures (`worker`, `verified_worker`, `notice`, `persist`) are unmapped and all report `queue-reconcile`.
   - Fix: add fixed stage markers in `main()` and `run_queue`, or map the closure names. Prefer the shallowest mapped frame for the uncertain-write case.

3. **Low: `__main__` handler (~lines 696-705).**
   - If `print(..., file=sys.stderr)` raises (closed or broken stderr), the exception escapes and exits 1 with an interpreter traceback. That violates the exit-2 contract and the no-traceback rule.
   - Imports at the top of the file, outside the `try`, have the same exit-1 behavior. That one is pre-existing.
   - Fix: wrap the print in `try/except Exception: pass`, and make `sys.exit(2)` unconditional.

4. **Low: `own_files` (~line 674) does filesystem work in the failure path.**
   - `Path(__file__).resolve()` can fail. The fallback then masks the real phase as `diagnostic-unavailable`, which the test exercises by patching `resolve`.
   - Fix: compare `code.co_filename == failure_details.__code__.co_filename`. It needs no IO and is robust to relative paths and symlinks, and the hardcoded relative-path literal can go.

5. **Low: the `category` logic (~line 684).**
   - `isinstance(error, ValueError)` marks `guard-failed` for things that are not guards. Examples are `json.JSONDecodeError` from `json.loads` and `fromisoformat`/`int()` parse errors. The `unexpected` bucket likewise merges `CalledProcessError`, `TimeoutExpired`, `OSError` and `RecursionError`.
   - Fix: emit `type(error).__name__` only if it is in a fixed builtin/stdlib allowlist. It cannot carry data.

6. **Low: test gaps in `factory-reporting-queue-diagnostics.sh`.**
   - It does not cover a failing stderr write (finding 3).
   - It does not cover the production observation path through `observe_queue` and `run_queue` (finding 1).
   - It does not cover the uncertain-write phase (finding 2).
   - It does not cover an unmapped frame, such as a failure inside a `run_queue` closure.
   - The suite proves privacy only against the sentinel in the paths it drives. It cannot show that the real failure surfaces a useful phase.

# Final static review

Actual tool-free Sonnet5.5 subscription review; not native protected proof or execution evidence.

# Review: queue diagnostics repair

This is a static review only. I ran nothing and did not see the other test files or `factory-git-state.py`. Line numbers are approximate, taken from the diff hunk offsets in the new file.

## Verdict

**No blockers found in the diff.** The invariants hold on the paths I could trace.

- **Fixed allowlisted output:** `phase` can only be a value from the `phases` dict, `'entry'`, or the literal fallback. `category` can only be `guard-failed`, `unexpected`, `metadata-unknown`, or a member of `safe`. The reason check uses `type(reason) is str` and set membership, so exception text and `str` subclasses cannot get through.
- **Original ValueError text:** `_QueueBlocked` keeps the exact message and subclasses `ValueError`. The reason is carried on a side attribute. I found no `except ValueError` between `run_queue` and `__main__` that distinguishes the type. `emit`'s `except Exception` wraps only `send()`, and the raise happens before it.
- **No new effects:** the change only swaps `require(...)` for `raise`, at the same point in `run_queue`. The raise comes after the pre-existing `worker()`, `store.read()` and `initialize` checkpoint, so nothing new is written ahead of it.
- **Allowlist coverage:** every category literal passed to `_observed` is in `safe`. The only other reason `observe_queue` can set is `observation-unavailable-or-invalid`, and that is in `safe` too.
- **Checkpoint context:** the `checkpoint |=` accumulator plus the final override means a `checkpoint` or `persist` frame anywhere in the traceback wins, including when the failure is in a nested `_load`.

## Remaining defects

**1. Low–medium, not a blocker, untested: exit 2 can still become 120 on a broken stderr.**
`__main__` block, ≈ lines 717–721.

- The inner `try/except Exception: pass` stops `print` from raising. It does not stop the interpreter's shutdown flush of `sys.stderr`.
- If stderr is a pipe whose reader has gone away, the `print` flush fails and the data stays buffered. Finalization then flushes again and fails, and CPython reports exit status 120 instead of the `sys.exit(2)` code.
- The test only patches `builtins.print`, which never reaches this path.
- A cheap fix is to use a final `os._exit(2)` after a best-effort `sys.stderr.flush()` in its own `try`. The other option is to redirect fd 2 to `os.devnull` if the write fails.
- To test it, spawn the process with `stderr` as the write end of an `os.pipe()` whose read end is already closed, and assert returncode 2.

**2. Low, optional: nothing keeps `safe` in sync with the `_observed(..., '<code>')` literals.**
`failure_details`, ≈ lines 696–702.

- A new reason code that isn't added to `safe` silently degrades to `metadata-unknown`. That fails safe but loses diagnostic value.
- A small test that scans the source (or reads the codes from `ast`) for `_observed` category literals and asserts each is in the set would stop that drift.
- The test would need `safe` to be a module-level constant, so it is a small refactor.

**3. Low, optional: phase granularity is coarse.**
- A pre-write `_load` failure inside `checkpoint` is reported as `journal-checkpoint`, the same as a failure after `current.checkpoint(...)` ran. This is conservative. An operator can't tell "no write attempted" from "write possibly uncertain", though the retained `queue write uncertain` text is still hidden by design.
- `_QueueBlocked` is raised from `run_queue`, so it reports `queue-reconcile`, not `queue-observation`. The category still identifies the cause.
- `lookup()` and `send()` run outside the `notice` frame, so they never get `notification-context`.
- `json.JSONDecodeError` and `UnicodeError` are `ValueError` subclasses, so they report `guard-failed` rather than `unexpected`.
- Your deferral note already covers finer exception classes. I agree it can wait.

**4. Info: test coupling.**
`factory-reporting-queue-diagnostics.sh` builds its fixture by slicing `factory-reporting-queue-delivery.sh` on `"python3 - <<'PY'\n"` and `'count=0\n'`, then `exec`s the result.

- If the delivery test is reformatted, this one breaks or runs against the wrong content. It will probably fail loudly rather than pass silently.
- The unknown-observation test mocks `observe_queue` and does not drive a real `observe_queue` through `_QueueBlocked` to the final stderr line. That is acceptable, since the real reason codes are covered by item 2.

## Not a defect, for context

- `argparse` errors raise `SystemExit` (exit 2) and bypass this handler. They echo the unrecognized argument text to stderr. Workflow-controlled, so I treat it as out of scope.
- `_QueueBlocked` takes a required `reason` argument, so `copy`/`pickle` of it would fail. Nothing in the file does that.
- With `initialize=True`, the empty-journal checkpoint still happens before the unknown-observation block. That is pre-existing behaviour and unchanged by this diff.

Full local acceptance is still unproven. Someone needs to run the diagnostics script and the existing queue suites to confirm.
