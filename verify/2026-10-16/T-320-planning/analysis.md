# Spec029 T320 planning analysis — 2026-10-16

PASS. The existing approved AC8 scope is decomposed into practical run/log,
protected journal/history, and explicit-live composition contracts. No runtime,
workflow, permission, credential, source push or live-call change is implemented.

AC1–7 retain their existing task/aggregate coverage. AC8 local contracts are
T319, T322–324 and T321/T317; actual reviewed rollout remains T318 with --live.
The programmatically checked scoped DAG and exact pending-state assertions are
retained in dag.log. Declared future test paths are targets, not completed tests.
No new service, dependency or operator decision is introduced. The planned
bounded adapter uses existing authenticated GitHub access and no Slack token.

Source/current-main/run bindings, strict log-result matching, authenticated
journal and per-publication opaque preservation cover the design components.
Drift, unknown authorization, missing logs/history, capacity and ambiguity fail
closed. The accepted administrative-correlation limitation is explicit: recovery
journal rows lack producer run identity; isolated one-pair and nonoverlap controls
do not convert observations into cryptographic provenance or independent Slack
verification. Raw logs/private feedback may not be saved. All runtime tasks
T322–324, parent T320, readiness T321/T317 and live T318 remain pending.

The analyze029 marker is refreshed with the exact PASS schema. Structural and
whole-ledger outputs are separate checks; planning PASS grants no live credit.
