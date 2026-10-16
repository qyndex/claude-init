# Protected maintenance boundary (T334 remains pending)

The initial missing-maintenance RED and first-transition proof cover only initial progress. The prepared broader scaffold was extended incrementally; its previously unasserted behavior is not claimed as original full-contract TDD. The fresh-driver argv setup error is retained separately.

The expanded actual test, `bash .claude/scripts/test/factory-reporting-maintenance.sh`, failed after 96 fresh Python invocations: a late source caused coverage to return a gap, but resetting the phase reused the already consumed completed source epoch. `late-source-epoch-red.log` preserves that terminal exit 1. A strict protected per-interval `source_epoch` watermark now requires a newer completed source round after gaps; a genuinely new cutoff resets only this scheduling watermark. Actual coverage remains authority.

The same command with the bundled Python runtime first on PATH then exited 0 (`late-source-epoch-green.log`, owner session 71736). It exercises two actual scoped source/backfill/coverage intervals, fresh subprocess restarts, real Git non-fast-forward CAS and lost acknowledgement, late actual append, unresolved rerun gap, and opaque worker preservation. No Slack, live activation, all-history coverage, or task credit is claimed. Public hosted loader integration remains pending under T334.
