# T311 — preserve diagnostic availability

Independent Sonnet review of6229ceb found the coordinator overwrote the helper's
diagnostic-unavailable marker with validation rejection category. Planning7d4e121
was reviewed before implementation. red.log is the actual current coordinator
failure with oversized metadata; green.log uses the same acceptance command and
records49 cases after the one-line source repair. No historical/fabricated RED.

Oversized and cyclic metadata traverse actual protection, preserve the same
original validation exception object, retain unavailable reason, and publish a
separate fixed audit-entry rejection. Normal diagnostics retain generic reason;
unexpected validation exceptions still propagate. Existing actual CLI ValueError
eligibility invalidation remains tested. No claim of new outer RuntimeError
invalidation. Helper construction/schema/bounds and authority checks unchanged.

observation.txt:60 local cases; coordinator.txt:63 local cases.
policy.txt proves only two coordinator runtime hashes changed; all other policy
fields exact, merge disabled. Python compilation and diff whitespace check pass.
structural.txt and ledger.txt retain actual validation results. No live App,
configuration, permissions, credentials, native proof, settings or push changes.
Root handles final aggregate collector, independent review and normal rollout.
