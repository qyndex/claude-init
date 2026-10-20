# Spec029 bounded queue clock repair

T-348 corrects a reproducible entry-clock false rejection: legitimate active-run
metadata can advance during API reads. Validate future metadata against actual
read-time UTC while preserving the captured entry clock for due/grace calculations.
No tolerance, grace, resource budget, retry, identity or snapshot guard increases.

A controlled-clock RED/GREEN fixture proves the repair, rejects actual-future
timestamps by one microsecond and retains run chronology checks. Existing queue
observation, retry and diagnostics suites remain required. The live fixed category
was metadata-clock-invalid; this fixture does not establish its unique live cause.
Publication, protected replay, merge and activation require separate authorization.

Canonical implementation plan: `plans/active/029-github-reporting-alerts.md`.
