---
id: 006
slug: trustworthy-candidate-verification
spec: specs/active/006-trustworthy-candidate-verification.md
status: approved
owner: "@codex"
created: 2026-10-09
updated: 2026-10-09
---

# Plan 006: Trustworthy candidate verification

Use explicit `--root` arguments for verification scripts, keeping default script-root behavior for current callers. Trusted coordinator scripts remain the gate implementation; candidate filesystem is explicit. Rerun the entire integration gate sequence after mediation.

Split tool availability checks from execution; selected unavailable tools fail rather than claiming a clean scan. Give evidence runs unique temporary runner output and only publish validated results; reject zero-AC and runner errors. Preserve documented check-only usage for prepared results while validating inputs.

Move IaC detection to checkout-backed steps; keep scan failures gating. Add an independently testable SARIF validator, remove scanner error swallowing, and block in-progress daily batches. Resolve calendar-day aging using UTC parsing of date-only values. Empty dependency rollups are explicit outcomes, while failed upstream jobs remain failures.

Replace old patch reapplication in regression suites with direct installed-behavior checks. Fix quoted destructive SQL guard coverage without claiming the regex guard is a sandbox.

## Task and AC mapping

- T-165: AC-1 candidate root and complete mediation rechecks.
- T-166: AC-2, AC-4 local scanners and contracts.
- T-167: AC-3 evidence finalization/freshness.
- T-168: AC-5 workflow/SARIF repairs.
- T-169: AC-6 calendar aging/dependency rollup.
- T-170: AC-7 frontmatter/current-behavior/security regressions.
- T-171: AC-8 GitHub CI verification and readiness status.
- T-172: AC-8 Linux awk date parsing and exact ISO-week backfill, discovered by the container baseline.

Record red/green evidence under verify/2026-10-09-006/T-<id>/. Run focused tests after each repair, then all suites once in a disposable copy. Report remaining factory gaps and actual Linux CI status accurately.
