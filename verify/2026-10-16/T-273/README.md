# T-273 reviewer model update — resumed verification

Base: f2e1411 (current main at start). This task resumes the previously prepared operator-selected Sonnet 5.5 implementation; original prior worktree is untouched.

The current spec/plan/tasks consistency review is PASS: AC-1/AC-2 isolation remains covered by completed T-219 and current runtime regressions; T-273 covers exact model usage AC-3 plus source/doc/workflow consistency AC-4. No new dependencies, open questions or dependency cycles. The active plan explicitly covers the new review skill override, parser and three hosted workflows. `.claude/state/analyze-045.json` was refreshed before verification.

Reconstructed RED: saved the full carried production patch outside the repository, restored tracked changed files to current HEAD while retaining the new acceptance script, ran the sanctioned RED ledger command, then reapplied the exact saved patch. RED failed the reviewer model assertion. The same acceptance command then passed GREEN. This is a rerun of the previous implementation transition, not a claim that the production changes were first authored in this session.

Acceptance includes actual local bounded fake-reviewer subprocesses, missing/old/foreign/mixed/invalid model usage rejection, local model routing, a major-5 routing drift fixture and full workflow baseline tests. Additional scoped runtime, producers (30 assertions), doc consistency, full actionlint, shell syntax, Python compilation and diff whitespace checks passed. No live provider request, capacity probe, hosted independent verdict, source-pin activation or merge authority activation occurred. Historical probe references in plan/documentation are not fresh availability or capacity proof.

The ledger runner reported missing timeout/gtimeout and ran acceptance without an outer timeout; the actual reviewer subprocess tests retain their own bounded timeout/output behavior. The task-status helper reconciled unrelated completed specs as a side effect; those unrelated metadata edits and runtime counter edits were restored. Only spec045's resulting shipped status is retained.

Parent continuation independently ran the existing bounded tool-free live subscription probe after these offline tests. Sanitized observation is live-capacity.json: exact Sonnet 5.5 available on CLI2.1.300; quota unknown, no spend claim, no hosted verdict or activation. This supersedes the earlier no-fresh-probe statement for the parent session only.

Collector integration initially failed because the fresh AC result mapping was absent, then the ledger required RED and GREEN timestamps to be strictly different seconds. The actual GREEN acceptance was rerun later (no timestamp edit), and the final collector proved 4/4 ACs with repository verification exit0. Current result mapping points to the completed runtime.log and its SHA256; historical baseline mappings were used only for unchanged AC descriptions.
