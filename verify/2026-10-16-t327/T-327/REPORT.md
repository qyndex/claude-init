# T327: weekly workflow input remains data

The actual active weekly workflow previously interpolated the manual week directly into generated shell source. The exact acceptance test failed because a controlled command substitution created a marker in its disposable root. Moving the expression into step environment and quoting the rollup argv passes the same test. No triggers, permissions, secret access, rollup validation or PR-publication logic changed.

Six cases execute the actual extracted workflow step with isolated rollup/git fixtures: command substitution, backticks, quote injection, valid explicit week, empty input and newline input. They verify no injected command runs and argv retains the original value. A second disposable Git root executes the unchanged real rollup script, proving explicit/current week and invalid ISO-week behavior. The isolated fixtures make no network or GitHub writes. This is local behavioral evidence; no hosted workflow or Linux execution is claimed.

Exact RED/GREEN evidence is under verify/2026-10-16/T-327. Broader regressions: rollup-envclock10PASS; memory-plane-lock11PASS; full ledger check0fail/0warn, with70 pre-enforcement legacy-incomplete records; structural validation PASS with four existing warnings; actionlint, ShellCheck and diff whitespace checks PASS. The Mac has no timeout/gtimeout; ledger prints its existing unbounded warning and the test completes normally. No timeout behavior was modified.

T327 is additional corrective support work, separate from the original sixteen-task scope. Integration and independent review remain pending; factory readiness is not asserted.
