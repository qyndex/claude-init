# CI cost optimization

Round 5 Batch B. How heavy CI checks are scheduled, and how local pre-PR mirroring keeps the feedback loop tight.

## The split

| Workflow | Trigger | Why |
|---|---|---|
| `ci.yml` (lint/typecheck/test) | per-PR + push to main | fast (<2 min); developer feedback loop |
| `commitlint.yml` | per-PR | <100ms; trivial |
| `harness-validate.yml` | per-PR + push | <30s; harness integrity |
| `claude-review.yml` | per-PR (on @mention) | opt-in; doesn't fire unless asked |
| `claude-security.yml` | per-PR (on @mention) | opt-in |
| `claude.yml` | manual @mention | opt-in |
| `auto-merge-dependabot.yml` | dependabot PR | scoped to dependabot |
| `release-please.yml` | push to main | release infra |
| `e2e-preview.yml` | manual | expensive, on-demand |
| `canary-deploy.yml` | manual | operator-driven |
| `sbom.yml` | manual | quarterly cadence |
| **`codeql.yml`** | **daily 8 am** | reusable; heavy |
| **`semgrep.yml`** | **daily 8 am** | reusable; medium |
| **`lighthouse.yml`** | **daily 8 am** + deployment | reusable; needs browser |
| **`perf-budget.yml`** | **daily 8 am** | reusable; needs build |
| **`license-check.yml`** | **daily 8 am** | reusable; weekly cadence is plenty |

## The daily batch

`.github/workflows/daily-batch.yml` runs at `cron: "0 8 * * *"` (8am UTC) and invokes the heavy workflows via `workflow_call`. Single rollup job `daily-batch-result` signals overall pass/fail.

```
08:00 UTC → daily-batch.yml
              ├── codeql.yml         (workflow_call)
              ├── semgrep.yml        (workflow_call)
              ├── lighthouse.yml     (workflow_call)
              ├── perf-budget.yml    (workflow_call)
              └── license-check.yml  (workflow_call)
                       ↓
              daily-batch-result (rollup)
```

## Failure → autofix → merge gate

When `daily-batch` concludes failure, `.github/workflows/daily-failure-autofix.yml` fires (on `workflow_run` event):

1. Downloads the failed run's logs to `/tmp/daily-logs/`
2. Spawns `claude --bg` with `max_budget_usd: 5, max_turns: 80`
3. Claude investigates, applies minimal fixes, commits with Conventional Commits, opens a PR `claude/daily-autofix-<date>`
4. An issue is opened tagging `ci,daily-autofix`

While the autofix is pending, `.github/workflows/merge-gate.yml` (required check on all PRs to main) refuses to merge:

```
PR → merge-gate.yml
       └── gh run list --workflow daily-batch.yml --limit 1
                            ↓
              ✓ green AND <30h old → pass (merge allowed)
              ✗ failed             → block ("most recent daily failed; see autofix PR")
              ✗ >30h old           → block ("trigger manual workflow_dispatch")
```

## Local mirror — keep the feedback loop tight

The lost per-PR feedback is restored locally for free via `.claude/scripts/local-pr-check.sh`. It runs the **exact same suite** as the daily batch:

```bash
# Quick (<2min) — recommended pre-push
bash .claude/scripts/local-pr-check.sh --quick

# Full (~5-15min) — recommended before opening a non-trivial PR
bash .claude/scripts/local-pr-check.sh

# Just the heavy ones (codeql / semgrep / lighthouse / perf-budget)
bash .claude/scripts/local-pr-check.sh --heavy

# Specific checks
bash .claude/scripts/local-pr-check.sh --only=semgrep,gitleaks
```

Install as pre-push hook (optional but strongly recommended):

```bash
# Soft pre-push: quick checks before every push
cat > .git/hooks/pre-push <<'EOF'
#!/usr/bin/env bash
exec bash .claude/scripts/local-pr-check.sh --quick
EOF
chmod +x .git/hooks/pre-push
```

## Branch protection (one-time setup)

In GitHub → Settings → Branches → Branch protection rules for `main`:

- Require status check: **`Merge gate / check-daily-batch`**
- Require status check: **`CI / build-and-test`**
- Require status check: **`Harness validate / validate`**
- Require status check: **`Commitlint / lint-pr`**
- Optional: require linear history, require code review

Do **not** require `Daily batch / *` checks per-PR — they don't run per-PR (that's the point).

## Cost outcome (typical mid-size repo, 20 PRs/day)

Before Batch B:
- Heavy CI per PR: 20 × ~15 min × 5 workflows = ~1500 minutes/day
- Monthly: ~45,000 min ≈ way over free tier

After Batch B:
- Daily-batch: 1 × ~25 min = 25 min/day
- Lightweight per-PR: 20 × ~3 min × 3 workflows = 180 min/day
- Local pre-push absorbs per-PR feedback (zero cost)
- Monthly: ~6,000 min — fits free tier comfortably

## Trade-offs accepted

- A failing PR ships against unchecked code IF the developer skips the local pre-push hook AND the change introduces a new issue that didn't exist at 8am. Merge-gate blocks merge if daily-batch is failing, but doesn't catch "fresh damage" between 8am and now.
- Mitigation: keep `merge-gate` failure-mode hard (block, don't warn). The autofix loop closes within ~1 hour usually.
- `e2e-preview` still per-PR-trigger via manual `gh workflow run`; deploy-status-driven workflows (lighthouse on deployment) still fire as needed.

## Live-E2E learnings (2026-06, spec 004)

Findings from running the harness end-to-end against a private Team-plan repo with a real app. Each is fixed in the workflows; recorded here so future repos aren't surprised.

- **Dependabot PRs don't get your Actions secrets.** GitHub runs dependabot-triggered workflows in a restricted context that withholds regular org/repo Actions secrets (only the separate *Dependabot secrets* scope is exposed). A gating LLM check (`claude-security`/`claude-review`) therefore reads `HAS_TOKEN=false` and hard-fails on every Dependabot PR. The harness skips those jobs on `github.actor == 'dependabot[bot]'` — dependency-only PRs change no app code, so semgrep/codeql/dependency-review still gate them (T-155).
- **GHAS-gated uploads degrade, they don't block.** Code Scanning (SARIF upload) needs GitHub Advanced Security, unavailable on private Team-plan repos. semgrep/codeql make the *upload* advisory (the jq/analysis stays the gate); osv-scanner runs as a **CLI** gating on its exit code instead of the reusable workflow's SARIF upload (T-151).
- **A workflow that edits an OIDC review workflow can't pass its own review.** `claude-code-action`'s OIDC app-token exchange requires the workflow file to match the default branch, so a PR editing `claude-security.yml` always fails its own `security-review` ("Workflow validation failed… this is normal"). Merge it; the next PR validates clean.
- **Scanners are silent until there's something to scan.** license-check (exclude the project's own `name@version`, not the bare name), perf-budget (gate on a `build` script, not just `package.json`), and osv-scanner (needs a committed lockfile) all looked green on an empty repo and only exercised real logic once the app landed. Test gates against a repo that actually has the artifact (T-156).
- **Bound the review turn budget, but not too tight.** `--max-turns 15` exhausted the security agent's multi-pass review and hard-failed the gate on a non-finding; 40 lets it finish while still capping runaway spend (T-157).
