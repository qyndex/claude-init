# T310 — authenticated completed origin in shared core readers

Base829be3632d48a7fc056c9990111cd8758e0e5761. The initial fixture-extraction
IndexError happened before production behavior and is retained as an invalid
attempt. Corrected fixture composition completed an actual300-commit frozen
history scan through separate fresh Python interpreters and protected checkpoint
publications. Actual append then failed the old256-ancestor bootstrap limit.
initial-core-red.log is that genuine pre-implementation failure; only then was
the shared completed-origin integration implemented. initial-append-green.log
retains its first positive result.

The expanded test initially expected a byte-identical no-op publication to count
as a copied-path update. Git correctly left the original genuine path publication
latest; rejecting that valid no-op would weaken correctness. The failed expansion
is retained as attempt-1/noop-copy-fixture-failure.log. The corrected negative
actually removes/re-adds the path before copying old capsule bytes, making its
new immutable publication parent demonstrably disagree with the stored parent.
No enforcement was changed to accommodate the bad fixture assumption.

Final source review identified a new premature commit-GET boundary: malformed
head metadata could reach a selector before the old loop's40SHA check. The final
canonical RED proves this actual invalid request, then the minimal exact-hash
check was restored before the new helper's first commit GET. Final GREEN reruns
both this early boundary and all completed-origin/core-consumer cases. No fake
RED, numeric guard raise or source-history mocking was used.

The shared verify_bootstrap now checks completed capsule schema/typed binding,
absence at reviewed bootstrap, current exclusive App-writer and no-rewrite/
no-delete rules, actual path-history publication identity/single parent, exact
checkpoint-only tree delta/blob/frozen commit/tree and reviewed ancestry. This
protected writer origin is the previously approved trust assumption, not native
attestation or cryptographic attribution. A caller-supplied capsule/hash or
compare response alone supplies no checked-prefix authority. Every fresh suffix
intermediate tree and single-parent edge is still checked; incomplete origin
cannot bypass the original256 bound.2048-call/32MiB limits remain unchanged.
Current ref and effective policies are freshly checked before returning an anchor.

Actual core append/idempotent re-entry, protected discovery, projection checkpoint,
retained SQLite reconstruction/current revocation and another fresh-process origin
reader are exercised above256 historical commits. Negative cases cover partial,
wrong typed schema, copy/re-add, non-checkpoint delta, bootstrap import, merged or
transient-executable suffix, mutable policy, missing App-writer capability,
malformed head selector, and a257-commit unscanned suffix. Opaque encrypted worker
bytes remain unchanged. Test ref rewinds are confined to disposable Git negatives;
no live state or actual API was modified.

This is only the shared origin foundation. Other per-operation discovery and
projection bounds, source pagination/large-delivery acceptance(T286/T287), final
T288 loaders/configuration, actual archive App capability and live cutover remain
pending. It grants no runtime completion, global delivery coverage, permissions,
credentials or activation. No source push or new task decomposition occurred.

Final verification: completed-origin acceptance passed, including real300-history
scanner/fresh-process and core-consumer/negative checks. Scoped regressions passed:
bootstrap15, origin-window actual300history, CAS11, discovery11, projection
checkpoint20 and retained-proof20. Compile passed. Structural/ledger results are
retained alongside the actual chronological RED/GREEN logs. The final extra hash
guard is covered by the full acceptance rerun; already-passing valid-input broad
regressions were not redundantly repeated afterward.

Ledger final result:0fail/0warn,70 pre-enforcement legacy-incomplete entries.
Structural final result:PASS with four existing warnings. All owned command
sessions terminated; only the preserved local analyze014 marker remains untracked
after committing this scoped task.
