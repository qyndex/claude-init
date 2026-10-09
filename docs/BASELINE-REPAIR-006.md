# Spec 006 baseline repair — implementation record

Date: 2026-10-09. Status: implemented and locally verified; not merged or independently authorized for merge.

[Specification](../specs/active/006-trustworthy-candidate-verification.md) · [Component plan](../plans/active/006-trustworthy-candidate-verification.md) · [Factory plan](../plans/AI-SOFTWARE-FACTORY.md) · [Original audit](audits/2026-10-09-repository-audit.md)

## What changed

- Verification accepts an explicit candidate root. Verified merge uses it and repeats smoke, heavy and contract gates after mediation; missing gates and failed dry-run checks block.
- Scanner execution errors and unavailable selected tools fail instead of returning PASS. Empty/unknown check selections fail. Unsupported contracts fail.
- Evidence collection rejects zero AC identifiers, malformed complete runner output, runner errors and failed manifest emission. Normal runs write results to new attempt directories; Playwright config and capture helper honor that output directory. Check-only mode remains for explicitly prepared result files and is not a trusted attestation.
- Semgrep execution errors remain failures; SARIF validation rejects missing/invalid scan structures and checks numeric severity, including rule metadata. IaC conditions run after checkout at step level. An in-progress daily batch no longer satisfies the merge gate.
- Dependency rollup preserves multiple stacks' artifacts, reports empty applicability explicitly and rejects malformed data or upstream failure. Open-question aging uses calendar dates across Sydney DST.
- Historical patch regressions test installed behavior. All maintained suites, including security invariants, gate CI. The obsolete sandbox-settings assertion now checks absence of an unsupported key and explicitly does not attest runtime isolation. Quoted destructive database SQL is checked as executable content; the security test captures the hook's exit code and decision correctly.
- Linux testing exposed additional awk/date defects. Task-history date patterns work on older mawk; weekly backfill resolves exact ISO-week Mondays at UTC midnight and rejects invalid week 53.

These changes intentionally cause unavailable verification tools to block rather than fabricate a pass. Real scanner setup/applicability remains part of the next authority/check-matrix work.

## Evidence

| Criterion | Proof |
| --- | --- |
| AC-1 candidate root / mediation | [T-165](../verify/2026-10-09-006/T-165/green.log): 7 assertions; healthy coordinator cannot hide failing candidate; post-mediation contract failure prevents reaching merge |
| AC-2 / AC-4 scanner and contract failures | [T-166](../verify/2026-10-09-006/T-166/green.log): 12 assertions, including failing tools, unsupported contract and invalid selection |
| AC-3 evidence freshness / emission | [T-167](../verify/2026-10-09-006/T-167/green.log): 5 assertions, including a valid prepared bundle and malformed trailing JSON |
| AC-5 workflow / SARIF | [T-168](../verify/2026-10-09-006/T-168/green.log): 8 assertions; [workflow syntax/expression lint](../verify/2026-10-09-006/T-171/actionlint.log) |
| AC-6 calendar aging / dependency rollup | [aging](../verify/2026-10-09-006/T-169/green.log), [dependency fixtures](../verify/2026-10-09-006/T-169/dependency-green.log) |
| AC-7 validation / security | [validator](../verify/2026-10-09-006/T-171/validate.json), [security](../verify/2026-10-09-006/T-170/security-green.log), [15 bypass classes](../verify/2026-10-09-006/T-170/bypass-green.log) |
| AC-8 platform verification | [macOS: 58/58](../verify/2026-10-09-006/T-171/macos-tests.tsv), plus subsequent focused portability checks; [Linux: 58/58 after repairs](../verify/2026-10-09-006/T-171/linux-tests.tsv) |
| Linux discoveries | Initial [55/58](../verify/2026-10-09-006/T-171/linux-first-tests.tsv), then [57/58](../verify/2026-10-09-006/T-171/linux-second-tests.tsv); [final ISO-week checks](../verify/2026-10-09-006/T-172/rollup-envclock-linux-green.log) |

Red/green outputs are retained under `verify/2026-10-09-006/T-165` through `T-172`. Ledger headers on captured results record their capture timestamps and command/exit information; these are local evidence, not externally signed execution receipts. T-171 remains pending for actual GitHub Actions proof against a committed candidate.

Structural validation: **79 passed checks, zero failures, one existing warning** about historical T-111's acceptance command listing proof files rather than exercising behavior. The ledger check has zero failures but retains legacy-history exemptions; this change does not certify that historical ledger. Workflow syntax/expression lint used `actionlint -shellcheck=`; maintained changed shell code passed warning-level ShellCheck. Existing unrelated embedded-shell style warnings are not claimed resolved.

The Linux environment used a cached public `node:20-slim` image (Debian 12), ordinary Bash/mawk/date tools and `Australia/Sydney`. Test tools were installed inside disposable containers; Actionlint 1.7.12's archive checksum was verified against official release metadata. The source mount was a disposable read-only copy; the container tested its own writable copy without repository credentials or a Docker socket. No paid model, real merge, destructive SQL or deployment was invoked.

[Implementation manifest](../verify/2026-10-09-006/implementation-manifest.json) records the baseline Git HEAD and changed source hashes. It is produced by the implementing session and cannot authorize a merge. The final macOS full-suite run preceded the additional Linux portability edits; those changed components were subsequently rerun on macOS, and the final Linux full suite included them.

## Remaining factory readiness work

This is the first F-00 repair slice, not closure of the factory plan. Still required:

- A06: per-stack required checks, detached acceptance execution, fail-closed stack detection, and trusted waiver/equivalent-CI authority.
- A04/A05: complete approved AC/spec schema, exact-candidate binding, artifact integrity and separate structured verifier/reviewer decisions; current-head security review.
- A08–A10: one merge evaluator, trusted producer/live-policy checks, candidate-bound daily proof and exact protected rollback.
- A14–A18: transactional ownership, supervisor/recovery, archive identity, correct shipped attribution and a complete timezone-aware delivery cursor.
- F-08: real protected deployments, service-bound SLO evidence and tested rollback before autonomous production releases.

The operating decisions are recorded in the factory plan: 08:00 Australia/Sydney Slack digest to `qyndex` / `qyndex-alerts`; local implementation; trusted GitHub Actions verification/merge via a dedicated GitHub App; automated production releases only after additional gates. Changes to merge/security authority remain operator decisions.

The original checkout branch and five pre-existing initiative edits were preserved. No PR, merge, deployment, GitHub App or Slack schedule has been created by this repair slice.
