# T-323 — isolated protected journal and publication proof

Actual RED at 13:59:23 Sydney on 2026-10-16 reached missing `observe_journal`
after creating real Git state objects and the complete typed drill/recovery
sequence. Source implementation followed that failure. The first actual GREEN
passed nine real Git cases; three additional already-supported negative cases
bring the final acceptance to twelve. The original RED and refreshed GREEN are
retained. No fixture is a claim of actual GitHub/Slack issuance.

The helper independently invokes the T322 run/source observer, never accepting a
caller run-proof JSON as authenticated facts. Existing QueueStore guards read an
already-present protected role; even an initialize=true configuration cannot
initialize or write from this helper. Exact selected drill run/attempt, one
matching confirmed recovery and absence of extra/unresolved effects are required.

The fixture reuses the existing real Git CAS adapter, creates a separate real
clean source checkout and synthesizes API run/log metadata explicitly. Actual
Git commit dates are set within those fixture windows. It writes empty
initialization, unrelated opaque worker updates, pending/confirmed drill and
pending/confirmed recovery. The observer checks each queue-path publication's
single parent, actual strict journal transition and equality of all other leaf
paths/modes/blob hashes. It never downloads or decodes other worker content.
Initialization may precede the drill and unrelated worker commits may occur
between queue publications. The exact reviewed bootstrap must lack the role.

Negative real Git fixtures reject simultaneous queue/worker changes, merge
parents, a copied role-containing bootstrap, unresolved effects, changed selected
attempt, extra effects, out-of-window pending publication, final changed role
bytes and exhausted 24-commit history. Final unrelated head movement passes when
role bytes remain identical. The 24-commit/1024-entry bounds are explicit isolated
pilot capacity refusals, not claims of lifetime or all-history coverage. Existing
README/reports-only state guards remain; later archive-path integration is outside
this task.

Final acceptance: `bash .claude/scripts/test/factory-reporting-queue-evidence-journal.sh`.
The T322 35-case source/run/log regression also passes with process inspection
permission for its existing fake-gh cleanup checks; it makes no network calls.
Raw job logs and private feedback are not persisted. Only administrative IDs,
source/state revisions, keys, hashes, windows and counts are returned.

Recovery attribution remains administrative correlation of verified protected
source/job results, ordered nonoverlapping run windows and publication history.
This is not a native attestation, independent local Slack verification or
exclusive-writer provenance. No CLI/live mode, settings, tokens, source push or
T324/T318 credit are added. The parent's existing plan clarification is preserved
and excluded from this implementation commit.
