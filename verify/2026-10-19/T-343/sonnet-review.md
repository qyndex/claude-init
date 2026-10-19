# Tool-free Sonnet5.5 source review

This is local source review, not a native receipt or whole-spec acceptance.

**No blockers.** I found nothing in this source-only review that needs to change before merge.

**What I checked**
- **`attempt_dir` is always set before use.** Both the `--check-only` and normal branches run `mktemp -d` before `smoke_scratch="$attempt_dir/smoke.out"`, so `set -u` can't trip. The path is unique per invocation, which is the property the repair relies on.
- **The contamination mechanism is closed.** The old shared `/tmp/smoke.out` was truncated by B's `>` while A was paused, so A's `tail -5` read B's output. The per-attempt path removes that sharing, and the digest and canonical-copy logic never touches `smoke.out`.
- **AC count, verdict and runner-exit contracts are unchanged.** No edits to steps 4, 6 or 7 appear in the diff.
- **The regression is a genuine barrier-based interleaving, not a sleep race.**
  - The `smoke-ready` and `smoke-release` files are created in each fixture's own working directory.
  - The `wait_for` calls have deadlines and check that the collector is still alive.
  - The two cases (A=17/B=0 and A=0/B=23) cover both a failing and a passing holder.
  - The `finally` block kills and reaps the collectors, and it restores or removes `/tmp/smoke.out`.
- **The assertions are sufficient.** They check own marker present, other marker absent, exit code, `smoke_exit_max`, `ac_proven`, `runner_exit`, verdict and the raw attempt proof.

**Non-blocking nits**
1. **Midnight rollover in the test.** The fixture computes the date once with `date +%Y-%m-%d`, and the collector recomputes it. A run straddling midnight would put the bundle in a different directory and fail with a confusing `FileNotFoundError`. It is very unlikely and only a test-flake risk.
2. **Full smoke output now persists in the bundle.** `attempt-*/smoke.out` is listed in the `EVIDENCE.md` artifact index. The README already says it needs review before public upload, so this is documented, but the evidence-gate or CI upload step should not publish `attempt-*` blindly.
3. **Log handle in the test.** If `Popen` raises inside `fixture()`, the opened `collector.log` handle isn't registered for cleanup. This is harmless in a short-lived test.
4. **Concurrent runs of the same bundle are out of scope.** `smoke.log` is still written non-atomically to the shared `$date_dir`, as you stated. This repair doesn't make that worse.

I couldn't confirm the `red.log` and `green.log` results from source alone. That includes whether `spec-match.sh` works with only the three copied scripts. I'm taking the README's claim that green passed as given.

## Adjudication

No blocker. Date-boundary fixture flake, log-handle cleanup on process startup error and same-bundle concurrent writes remain scoped limitations. Full scratch stays in its private attempt directory; the publication package selects lightweight proof and does not include the full raw scratch file.
