#!/usr/bin/env bash
# One-shot: land the spec-004 corrected workflows + tasks onto a branch and open
# a PR for claude-init main. RUN THIS YOURSELF (operator) — it does the
# constitution-class writes the agent is blocked from (workflows + tasks/TASKS.md)
# and opens a PR so the change still gets human review before it merges.
#
#   bash verify/2026-06-14-e2e-final/land-spec004.sh
#
# Idempotent: re-running on an existing branch just re-applies + amends.
# It does NOT merge — you review the PR and squash-merge.

set -euo pipefail

repo="/Volumes/M/sourcecode/qyndex/claude-init"
cd "$repo"

# Source branch that carries the agent-committed corrected staged files + evidence.
SRC_BRANCH="${SRC_BRANCH:-fix/t157-accept-precise}"
WORK_BRANCH="${WORK_BRANCH:-fix/spec004-land-workflows}"
STAGED="verify/2026-06-13-spec004-tasks/staged"
TASKS_APPEND="$STAGED/TASKS-append-3.md"

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

say "0. pre-flight: clean tree on a known base"
git fetch origin --quiet
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: working tree is dirty. Commit/stash first, then re-run." >&2
  exit 1
fi

say "1. branch off origin/main"
git checkout -B "$WORK_BRANCH" origin/main

say "2. pull corrected staged files + evidence + install.sh from $SRC_BRANCH"
git checkout "$SRC_BRANCH" -- verify/2026-06-13-spec004-tasks/ verify/2026-06-14-e2e-final/

say "3. apply staged workflows + hooks (sanctioned operator cp)"
APPLY=1 bash "$STAGED/install.sh"

say "4. append T-140..T-157 to tasks/TASKS.md (if absent)"
if grep -qE '^- \[.\] T-14[0-9]' tasks/TASKS.md; then
  echo "T-14x lines already present — skipping append"
else
  # append only the task-state lines (the '- [ ] T-1NN | ...' rows), preserving order
  grep -E '^- \[.\] T-1[45][0-9]' "$TASKS_APPEND" >> tasks/TASKS.md
  echo "appended $(grep -cE '^- \[.\] T-1[45][0-9]' "$TASKS_APPEND") task lines"
fi

say "5. local verification BEFORE pushing"
fail=0
git add -A
# T-154: corrected osv on main-to-be
if git show ":.github/workflows/daily-batch.yml" | grep -q 'No package sources found'; then
  echo "  T-154 ✓ (osv no-lockfile branch present)"
else echo "  T-154 ✗"; fail=1; fi
# T-152: env-injection fix
git show ":.github/workflows/adr-gate.yml" | grep -qE '^\s+BASE_REF:\s*\$\{\{ github.base_ref' \
  && echo "  T-152 ✓ (adr-gate BASE_REF via env)" || { echo "  T-152 ✗"; fail=1; }
# T-155: dependabot skip
for f in claude-security claude-review pr-review; do
  git show ":.github/workflows/$f.yml" | grep -q "github.actor != 'dependabot\[bot\]'" \
    || { echo "  T-155 ✗ ($f)"; fail=1; }
done; [ "$fail" -eq 0 ] && echo "  T-155 ✓ (dependabot skip on all 3)"
# structural lint
bash .claude/scripts/validate.sh >/dev/null 2>&1 && echo "  validate.sh ✓" || { echo "  validate.sh ✗"; fail=1; }
# actionlint errors (not pre-existing style warnings)
if command -v actionlint >/dev/null 2>&1; then
  errs="$(actionlint .github/workflows/daily-batch.yml .github/workflows/adr-gate.yml \
            .github/workflows/quarterly-archive.yml 2>&1 | grep -E 'expression|syntax|is not defined' || true)"
  [ -z "$errs" ] && echo "  actionlint ✓ (no errors)" || { echo "  actionlint ✗: $errs"; fail=1; }
fi
[ "$fail" -ne 0 ] && { echo "PRE-PUSH VERIFY FAILED — not committing." >&2; exit 1; }

say "6. commit"
git commit -m "fix(004): land spec-004 CI-gate corrections on main (T-140..T-157)

Applies the corrected, e2e-verified workflows that were staged under
verify/2026-06-13-spec004-tasks/staged/ (constitution-class — agent-write-blocked,
so applied via operator install.sh):

  daily-batch.yml      T-154/T-151 — osv-scanner CLI 'scan source --recursive .'
                       + no-lockfile warning (was '-r --no-ignore ./' false-green)
  adr-gate.yml         T-152 — github.base_ref via env: not inline run: interpolation
  quarterly-archive.yml T-152 — inputs.quarter via env; id: archive + correct outputs ref
  claude.yml           T-153 — OAuth token + claude_args/trigger_phrase
  claude-review.yml    T-155 — skip LLM gate on dependabot[bot] PRs
  pr-review.yml        T-155 — same
  + hooks (T-132), commitlint/merge-gate (T-134/135), claude-security/gitleaks
    (T-142/143/153), harness-validate (T-140), license-check/perf-budget (T-156)

Proven live on harness-e2e-sandbox: good PR merged green, gauntlet PR blocked,
osv scanned 265 packages, daily-batch green both repos, security-review SUCCESS
@ max-turns 40. Evidence: verify/2026-06-14-e2e-final/EVIDENCE.md.

Constraint:    .github/workflows/* + tasks/TASKS.md are constitution-class; landed via operator script + PR review
Rejected:      agent direct-write | blocked by SEV1 constitution guard (by design)
Directive:     'finish all gaps T-140..T-155, no gap at all'
Confidence:    high
Scope-risk:    localized
Not-tested:    quarterly-archive runtime (no quarter-boundary trigger locally)

Spec: specs/active/004-ci-gate-remediation.md
Task: T-152, T-153, T-154, T-155, T-156, T-157

Co-Authored-By: Claude <noreply@anthropic.com>"

say "7. push + open PR (does NOT merge — you review & squash-merge)"
git push -u origin "$WORK_BRANCH"
gh pr create --fill --base main --head "$WORK_BRANCH" 2>/dev/null \
  || echo "PR may already exist: gh pr view $WORK_BRANCH --web"

say "DONE — review the PR, then: gh pr merge $WORK_BRANCH --squash --admin"
echo "After merge, confirm zero-gap:"
echo "  git show origin/main:.github/workflows/daily-batch.yml | grep -q 'No package sources found' && echo 'T-154 ✓ on main — no gap'"
