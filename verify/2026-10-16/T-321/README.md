# T321 — local aggregate and queue setup

Actual fail-first RED asserted the approved aggregate script was absent before
writing it. The identical GREEN command asserts existence and executes that
actual script. The wrapper avoids treating a missing shell runner (exit 127) as
behavioral RED. Raw ledger timestamps and commands are retained unchanged.

GREEN runs queue journal (60), real Git CAS/restart (20), observation (33),
delivery (39), workflow/config/credentials (64), and offline evidence CLI (11),
source observer (35), and real Git journal/publication (12) cases. The evidence
shell already runs the last three suites; this aggregate does not duplicate
them. It also runs full workflow baseline/actionlint, ordinary reporting alerts,
watchdog, hosted digest, attachment, and policy-observation regressions.
Negative receipt-comparison diagnostics in output are expected fixture checks.
All transports are local fixtures; subprocess cleanup required process
inspection outside the restricted sandbox. No live GitHub or Slack calls occur.

These are local contract contributions toward Spec029 AC1–8. Full AC8 requires
actual reviewed rollout and remains PENDING in T318. Neither this aggregate nor
the default evidence-shell self-tests grant live credit. Administrative live
correlation is not native attestation or independent local Slack verification.

Docs explain job-if repository/organization variables versus step-only protected
environment variables, existing separated credentials, reviewed initialization
and drift, uncertain-send reconciliation, and bounded pilot limits. The existing
parent clarification of three disabled auxiliary workflows is intentionally
included: the factory plan remains active, with no verification credit from
those disabled workflows. No settings or workflow activation changed.

After this source commit, the parent may collect a final source-bound Spec029
bundle using actual AC-tagged commands and smoke output with the committed source
as ancestor. Required artifacts are fresh results.json/raw AC logs, summary.json,
summary.md, and actual smoke/verify output from the approved collector. Its scope
must explicitly identify local contributions and pending live AC8; no full AC8
PASS may be inferred from fixtures. This task does not manufacture that final
published bundle before its source commit exists. T317 aggregate verification
and T318 actual rollout remain pending.
