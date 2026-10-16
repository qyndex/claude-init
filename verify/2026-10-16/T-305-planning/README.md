# T305 observed timestamp-equivalence repair planning

Planning only,2026-10-16. observed-reproduction.json records an actual replay using
current committed helper685d68b against provided real public/operator response
files. It retains safe identities, raw response digests, actual semantic hashes
and timestamps only, not actors/raw policies/credentials. Exactly created_at and
updated_at differ, their instants agree, yet current validation rejects.

This new factual defect supersedes the earlier speculative App-audit-before-any-
fix guard only for these two timestamps. It is not actual App response evidence
or native attestation. Fresh actual App-shadow proof remains necessary after
reviewed rollout. No other metadata normalization or authority change is planned.

Plan lossless UTC canonical semantic timestamps plus exact updated instant
comparison, preserving raw diagnostics and every other field. Tests must replay
the full safe captured semantic snapshot and reject1microsecond drift, unsupported
submicrosecond precision, invalid offsets and fractional settle-bound violations.
No legacy lexical-hash fallback; actual full-GET recapture is required for deployed
observations. No live capture/variable update is performed by this local replay.

TASKS append used with_tasks_lock; analyze.txt records actual DAG/status checks.
structural.txt records actual validation. No TDD/implementation PASS is claimed.
Root untracked analyze/story coverage and receipt branch remain untouched.
