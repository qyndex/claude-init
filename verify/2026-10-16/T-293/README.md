# T-293 — authenticated bounded origin windows

Actual first RED ran the new acceptance script against the preimplementation
archive and failed for the missing advance_origin behavior. GREEN runs the same
command against the new scanner. Source/test byte hashes and base commit are in
inputs.json; no test or source-history mutation manufactured a failure.

The real Git fixture builds300commits above the reviewed bootstrap and runs each
16-commit window in a fresh Python process. No in-memory cursor survives. The
301checked commits include bootstrap; completion covers that frozen snapshot only.
Newer suffixes, including checkpoint publications, remain explicitly pending, and
a later call can advance using the prior checked prefix. coverage_complete is
always false: this foundation grants no delivery, engineering or projection proof.

Protected resume origin is independently established by exact repository/privacy,
settled exclusive App writer and no-rewrite/deletion policies, reviewed bootstrap,
immutable comparison metadata and actual fixed-path publication history. The
publication must have one recorded observed parent and an immutable tree delta
changing checkpoint only. The checkpoint must be absent at bootstrap, have exact
approval/head/tree bindings, and come from that actual protected branch. A JSON
hash, caller cursor or copied bootstrap is insufficient. Protected App compromise
remains the existing approved writer trust risk; no portable signature is claimed.

The acceptance exercises actual concurrent reporter/nonforceCAS conflict and lost
acknowledgement reconciliation while preserving old encrypted bytes; tampered
bindings/publication deltas, copied bootstrap, merge parents and an executable
introduced then removed all reject. Partial tree cursors resume without counting
unchecked commits. Global32MiB response and argument bounds reject explicitly.
All per-call observations share2048APIcalls/32MiB across up to3CAS attempts; no
older256commit lifetime cutoff is used by this separate scanner. Compare files or
partial commit arrays never establish full content validation.

Actual regressions: bootstrap15, CAS11, discovery11, reruns20, retained-proof20,
archive31, state-paths35 and coordinator63 passed. Two-module Python compile and
structural check passed (four existing warnings). TDD ledger passed with0failures,
0warnings and70pre-enforcementlegacyincomplete. One initial fixture-script
indentation error while constructing its child runner was corrected before final
GREEN; it did not indicate a production behavior change. A mistyped state-path
suite filename was corrected; the actual existing35-case suite passed.

Existing append/project still use strict verify_bootstrap and its bounded full
walk. T294/T295/T286–288 must integrate source partitioning, complete origin and
retained-projection windows before any unattended capacity claim. Shared tree
frontier/object bounds still produce explicit capacity gaps, never silent complete
coverage or pruning. No workflow, live bootstrap, credential, flag, permission or
state change occurred; all Git writes are disposable fixture objects/ref updates.
The actual archive Administration-read actor-visibility/capability cutover remains
unsupported/pending reviewed integration; main-policy empty-actor observations
cannot authorize an archive App actor list. PR110 source was not imported here.
