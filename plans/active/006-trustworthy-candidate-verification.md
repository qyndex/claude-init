---
id: 006
slug: trustworthy-candidate-verification
spec: specs/active/006-trustworthy-candidate-verification.md
status: approved
owner: "@codex"
created: 2026-10-09
updated: 2026-10-16
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
- T-327: AC-9 weekly manual-input transfer through environment and quoted argv; dependency-free parallel corrective baseline repair, integrated sequentially after verification.

Record red/green evidence under verify/2026-10-09-006/T-<id>/. Run focused tests after each repair, then all suites once in a disposable copy. Report remaining factory gaps and actual Linux CI status accurately.

## SARIF effective severity corrective task — T-326

Clarify existing AC5 and repair check-sarif.sh's inherited-rule error severity gap. Preserve explicit result precedence, numeric failure thresholds, warning/clean inputs and malformed-output rejection. Resolve inline driver ruleID/index identities; reject ambiguous, inconsistent or unsupported resolution instead of claiming clean. Apply kind defaults before inherited levels. Portable behavioral RED/GREEN tests invoke the production gate, including invalid metadata. Re-evaluate the frozen actual Semgrep report and triage source findings separately; do not suppress them to obtain GREEN. This independent task is parallel-safe in its own clone under the operator's2026-10-16 authorization; integration remains sequential under parent control after T287. No live credentials/policy/authority cutover or external model use.

## Weekly dispatch input corrective task — T-327

Repair the demonstrated active workflow shell interpolation using environment transfer and quoted argv. Preserve the existing script validation, explicit-week/current-week behavior, workflow triggers, permissions and secret access. Exercise actual extracted step behavior with isolated rollup/git fixtures and literal command-substitution/quote payloads, then validate the real rollup script in a disposable root. No live workflow execution is authorized by this repair.

## Supported staged ADR input corrective task — T-328

Implement AC10 for the supported historical staged installer payload. Mirror environment transfer and quoted argv already used by the current ADR workflow, preserving branch filters, permissions and actor/job behavior. Record original payload identity in non-installable evidence, then exercise actual staged and installed run bodies against disposable Git fixtures for literal shell payloads and G40 ADR acceptance/rejection. Keep scanner scope over installable assets. This is independent parallel corrective support work; integrate sequentially after review, without live workflow or policy changes.

## Exact-source audit policy corrective task — T-329

Implement AC11 under the operator-approved design A. Keep jq as the single severity/identity validator, then apply a small stdlib exact-source policy verifier only when all explicit policy/hash/root inputs are provided. Authenticate registry bytes before consuming strict records; bind each accepted error to one exact location and current regular no-symlink source bytes; numeric-high findings remain unwaivable. Preserve full raw SARIF and report accepted audit count separately. Use mutually exclusive default scanner and fixed-environment main-only audit producer jobs, with no empty dynamic environment or protected-hash transport to an untrusted job. Default mode remains usable without environment provisioning. Initial records are proposed and require concrete live approval; protected expected hash must be environment-scoped with no repo/org fallback. Add mutation, missing-auth, duplicates, extra-error, suppression, numeric and workflow ingress controls before code. Existing88 SARIF semantics remain covered. This independent parallel support task does not replace original factory tasks or activate authority.

## References

- [ADR-0010: Authenticated exact-source scanner audit policy](../../.claude/memory/decisions/0010-authenticated-exact-source-scanner-audit-policy.md) records T329 design A, default-off behavior and the separate concrete live approval boundary. It does not activate either proposed audit record.
