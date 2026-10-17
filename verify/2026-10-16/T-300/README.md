# T300 bounded protected retained windows

Actual RED calls the proposed window API against a real disposable Git archive;
preimplementation lacks that behavior. GREEN passes17 frozen-window scenarios.
Fixtures include actual protected bootstrap/App-writer origin, three appended
receipts, partial ranges, exact frozen revision, out-of-range/type/cap rejection,
per-window conflicting facts, bounded reads, missing origin, current revocation,
encrypted-byte preservation and no SQLite/ref writes. A concurrent reporter
appearing during final origin recheck rejects the entire result. Initial fixture
race scheduling triggered the existing bootstrap's earlier recheck; scheduling
was corrected to exercise the intended final window recheck. No stale result is
accepted in either case.

The reader independently authenticates the protected view. Requested head/range
and returned references/hashes are not portable origin proof. Aggregate API
observations are bounded2048calls/32MiB; the full256commit bootstrap is still an
explicit integration gap. All checked source/material/origin protections remain.
Current protected trust and approval are rechecked before returning facts.

interval_end is a validated/bound campaign label, not a timestamp fact filter.
T302/T288 must apply authenticated interval semantics and global cross-window
conflict/dedup checks before reporting completeness. coverage_complete is always
false; all_segments_checked describes only traversal of this frozen snapshot.
No publication/cursor paths or archive writes are implemented here. Existing
all-at-once SQLite projection reuses validation and rejects a partial window.

Retained20, runtime compatibility17 and reruns20 regressions passed; their actual
outputs are retained separately. Compile, ledger and structural checks follow.
No T301/T302 implementation, task lifecycle grant, hosted proof, live state,
credentials, flags, policy or protection changes. T295/T286 remain pending.
