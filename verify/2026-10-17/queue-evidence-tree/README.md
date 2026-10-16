# Queue evidence opaque archive preservation

Isolated base eae78f9; preparation within Spec014/Spec029 reporting readiness,
not task335 completion or live activation. Production change is limited to
observe_journal's private tree reader in factory-reporting-queue-evidence.py.

Actual state-writer namespaces (factory-state-paths.py) permit root README.md,
reports, and receipt-archive. Only reports contains queue/worker report leaves.
Read root and reports nonrecursively, retaining the existing1024 entry bound for
each response. Keep receipt-archive as one opaque mode/SHA pair in the existing
non-role publication comparison: a queue publication changing that subtree rejects.
Do not traverse archive history, import its data, or grant receipt authority.
Strict root/report mode/path allowlists and all existing role/history/run source
checks, read-only behavior, and the intentional24-commit isolated pilot bound remain.

RED (exit1): actual real Git fixture with4501 legal archive leaves fails old
recursive reader with `queue evidence state tree incomplete or capacity exceeded`.
GREEN (exit0): same fixture passes13 journal/publication controls, including exact
archive-subtree identity preservation, no archive-subtree API traversal, and rejection
of an actual queue publication simultaneously changing an archive object.
Existing opaque-worker mutation, merge, altered role, run attempt, extra event,
out-of-window publication, head movement and24-commit exhaustion controls remain.
The fixture models GitHub trees via actual git ls-tree, honors recursive selection,
and uses one bounded local process per tree rather than one process per leaf.

Focused source/CLI suites use local gh stubs only. Initial sandboxed source/CLI
runs could not call /bin/ps at intentional oversized-output cleanup and failed;
unchanged suites were rerun with process-status permission. This was an environment
diagnostic, not RED proof or product failure. Source suite41 cases, CLI composition11
plus its embedded source suite. No native API calls, App keys, Slack sends, state
writes, root allowlist expansion, cap increase, or full producer rerun.

Compile, ShellCheck and diff checks passed. Structural validation and exact final
suite exits are retained alongside this record. Parent owns integration and review.
