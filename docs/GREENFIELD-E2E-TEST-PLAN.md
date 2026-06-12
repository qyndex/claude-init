# Greenfield Live E2E Test Plan

Proves the harness works **as a product** on a live GitHub repo — covering everything
local testing (`validate.sh`, `harness-doctor.sh`, the campaign rig) cannot reach:
ruleset enforcement, LLM review workflows, evidence-gate as a *blocking* check,
auto-merge, actor guards, release tagging, deploy lifecycle, and the Cloud Routine.

**Philosophy:** judge by artifacts, not assertions. Every phase has explicit pass
criteria; a gate you have never seen *block* is untested. Phase 1 deliberately
submits bad work to prove the gates say no.

**Sandbox:** a private throwaway repo (suggested: `<org>/harness-e2e-sandbox`).
Delete it when done; nothing here touches production.

**Operator-only items** (cannot be automated from a Claude session):
1. `ANTHROPIC_API_KEY` secret value (Phase 0.3)
2. A second GitHub account that is NOT a collaborator (Phase 4.1)
3. Cloud Routine creation + "Run now" at claude.ai/code/routines (Phase 5.2)
4. Reviewing what Phase 1 blocks

---

## Phase 0 — Sandbox bring-up (~30 min)

| # | Step | Command / action | Pass criteria |
|---|------|------------------|---------------|
| 0.1 | Create repo | `gh repo create <org>/harness-e2e-sandbox --private --clone` | repo exists, cloned |
| 0.2 | Scaffold harness | `git -C <claude-init> archive HEAD | tar -x -C .` (git-aware: complete tracked set, no gitignored leakage), then `bash .claude/scripts/setup.sh` | setup completes; release-please config seeded for the detected stack (no `@your-org/your-repo` placeholder); API-key preflight warns until 0.3 |
| 0.3 | Set secret | `gh secret set ANTHROPIC_API_KEY` **(operator)** | `gh secret list` shows it; setup preflight / doctor check green |
| 0.4 | Apply + activate ruleset | `gh api repos/<org>/harness-e2e-sandbox/rulesets --method POST --input .github/rulesets/main-protection.json` | doctor "live branch ruleset" check flips green |
| 0.5 | First push | `git push -u origin main` | `harness-validate` workflow runs green in Actions |
| 0.6 | Local baseline | `bash .claude/scripts/validate.sh && bash .claude/scripts/harness-doctor.sh` | validate 0 failures; doctor flags only known unwired items (deploy stub, routines, feedback) |

## Phase 1 — Prove the gates can say NO (negative testing)

Open ONE deliberately bad PR containing all of the following, then verify each
named check goes red and **GitHub refuses the merge button**:

| # | Sabotage | Check that must go red |
|---|----------|------------------------|
| 1.1 | Task flipped `[x]` with no `verify/<date>/T-<id>/red.log`+`green.log` | `evidence-gate` (TDD-ledger arm) |
| 1.2 | No evidence bundle in PR body / an AC left UNPROVEN | `evidence-gate` |
| 1.3 | Non-conventional commit subject, missing trailers | `commitlint` |
| 1.4 | A failing unit test | `lint-test` |
| 1.5 | `eslint-disable` without `JUSTIFICATION:`+`ISSUE:` | `lint-exception-audit` |
| 1.6 | `gh issue view` added in a state-consuming script | `no-issue-authority` workflow |

Also verify: with checks red, `gh pr merge` is rejected by GitHub at the API layer
(ruleset live, not advisory). Close the PR unmerged; delete the branch.

## Phase 2 — Real feature, eight phases, auto mode

Build something small but real so the Playwright evidence rig runs (e.g. TODO API
+ one web page, SQLite).

| # | Step | Pass criteria |
|---|------|---------------|
| 2.1 | `/specify "TODO list: add/complete, SQLite, web UI"` | spec in `specs/active/` with testable ACs |
| 2.2 | `/clarify` → `/plan` → `/tasks` | plan + 2–5 min atomic tasks in `tasks/TASKS.md`, dep-ordered |
| 2.3 | `/implement next` (repeat; or `/loop` for auto mode) | per task: `red.log` shows a GENUINE failure before `green.log`; commits carry trailers + `Task: T-<id>` |
| 2.4 | `/verify` | Playwright evidence in `verify/<date>-<feature>/`: video, trace, per-AC screenshots; `spec-match.sh` maps every AC to a passing tagged test |
| 2.5 | `/ship` | PR body embeds the evidence bundle; ALL required checks green, including `review` + `security-review` (confirm in logs the reviewer model ≠ implementer model — cross-model review) |
| 2.6 | Issue projection | one spec issue with task checklist; board card TODO→DOING; hand-editing the issue checklist gets re-asserted from TASKS.md (write-only projection) |

Run 2.3–2.5 once interactively, then reset and repeat the same backlog via `/loop`
in auto mode — auto mode is where silent failures hide.

## Phase 3 — Merge + release mile

| # | Step | Pass criteria |
|---|------|---------------|
| 3.1 | Add `auto-merge-ok` label to the green PR | `auto-merge` workflow arms native `gh pr merge --auto --squash`; merge happens only once checks pass |
| 3.2 | Post-merge lifecycle | `issue-lifecycle` moves the spec issue to DONE |
| 3.3 | release-please | a release PR appears from the conventional commits; merging IT creates the tag — confirm no other tag source exists |

## Phase 4 — Live security tripwires

| # | Test | Pass criteria |
|---|------|---------------|
| 4.1 | **(operator)** From a non-collaborator account, comment `@claude run something` on an issue | `claude` workflow does NOT start a privileged run (author_association guard); a collaborator comment DOES |
| 4.2 | `gh api .../dispatches` with a hostile `client_payload.service` (shell metacharacters) | `hotfix-ingest` rejects at the identifier-char check; no command runs with the tainted value |
| 4.3 | Fork PR (if forks enabled) | secrets unavailable to fork-triggered runs; gates still report |

## Phase 5 — Deploy + autopilot

| # | Step | Pass criteria |
|---|------|---------------|
| 5.1 | Trigger `canary-deploy` with `DEPLOY_WIRED` unset | refuses loudly at step 1 (fail-closed stub) — by design |
| 5.2 | Wire a dummy deploy (echo + healthcheck stub per [DEPLOY-INTEGRATION.md](DEPLOY-INTEGRATION.md)), set `DEPLOY_WIRED=true`, remove STUB marker | run creates a GitHub Deployment; success posts `deployment_status` → `issue-lifecycle` moves issue toward SHIPPED |
| 5.3 | **(operator)** Cloud Routine from `.claude/routines/overnight-build.yml` at claude.ai/code/routines; seed 2–3 unblocked tasks; click "Run now" | `claude/overnight-<date>` PR + `OVERNIGHT_REPORT.md`; routine never merges (morning review is yours) |
| 5.4 | Local routine layer | `bash .claude/scripts/install-overnight-tasks.sh` from an authenticated terminal | 10 `✓ registered`; doctor's routine check leaves only cloud/opt-in items |

## Phase 6 — Failure injection (loud-failure audit)

Each must fail LOUDLY — a silent skip is a finding:

| # | Sabotage | Expected loud failure |
|---|----------|----------------------|
| 6.1 | Delete the coverage script from package.json | `verify.sh` FAILS (polarity-inverted gate), does not skip |
| 6.2 | Task with `accept: echo ok` | `validate.sh` rejects the no-op accept |
| 6.3 | Write a dummy AWS key into a file | `pre-write-secret-scan.sh` blocks the Write |
| 6.4 | Ask the agent to `rm -rf` / force-push main / pipe curl to sh | `pre-bash-guard.sh` exit-2 hard block, including chained-command evasion |
| 6.5 | Make a task fail 3 self-heal attempts | lands as `[!]`; visible in `requeue-failed.sh`; requeue is explicit-only |
| 6.6 | Stop a session mid-task | `[~]` orphan surfaced by `requeue-failed.sh` stale listing / orphan-reconcile |

## Results ledger

Copy this table into `verify/<date>-live-e2e/RESULTS.md` in the sandbox and fill
it as you go; attach run URLs as evidence.

```
| Phase | Item | Verdict (PASS/FAIL/SKIP) | Evidence (URL / path) |
|-------|------|--------------------------|------------------------|
| 0.1–0.6 | ... | | |
```

**Exit criteria:** every non-SKIP row PASS, with Phase 1 and Phase 6 rows proving
blocks (not just green runs). Findings become tasks in claude-init's
`tasks/TASKS.md`, not fixes in the sandbox.

## Related

- [ONBOARDING.md](ONBOARDING.md) — greenfield setup details
- [AUTOPILOT.md](AUTOPILOT.md) — Cloud Routine setup + Routine Installation Matrix
- [DEPLOY-INTEGRATION.md](DEPLOY-INTEGRATION.md) — wiring a real deploy
- [ADOPTION.md](ADOPTION.md) — the brownfield counterpart of this plan
