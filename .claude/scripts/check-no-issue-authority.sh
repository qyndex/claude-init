#!/usr/bin/env bash
# Authority-inversion guard — Round 11 E.
#
# TASKS.md is the SOLE source of truth for task state. This script fails if any
# agent prompt or script under .claude/ READS task state back from GitHub Issues.
# Run by no-issue-authority.yml on every PR touching .claude/.
#
# Allowlist: tasks-to-issues.sh (write-only projector) + this guard itself +
# the lifecycle workflow (moves project status, doesn't read task state).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Patterns that indicate READING task/issue STATE from GitHub (the forbidden direction)
read_patterns='gh issue view|gh issue list|gh api [^|]*issues[^|]*--jq|gh project item-list|gh issue status'

# Files allowed to reference the issue API: the write-only projector, this guard,
# the lifecycle workflow (moves project status, not task state), the /issues
# command + docs (which legitimately DOCUMENT the prohibition in prose).
# Note: rollup.sh lists `auto-bump`-labelled dependency issues for a report — a
# disjoint domain from spec/task state, so it's allowlisted (it never reads the
# projected spec issues to drive task decisions).
# Round 14: import-issues-once.sh is a ONE-TIME adoption migration — it reads issues
# only to SEED tasks/TASKS.md at t=0, self-terminates via a committed sentinel, and is
# never called from a routine/hook/inner loop. Allowlisted by exact basename + ADOPTION.md.
allowlist='tasks-to-issues.sh|check-no-issue-authority.sh|issue-lifecycle.yml|no-issue-authority.yml|ISSUE-LIFECYCLE.md|issues.md|CLAUDE.md|feedback|rollup.sh|daily-failure-autofix.yml|hotfix-ingest.yml|hotfix-to-task.sh|hotfix-sentry-poll.yml|PROD-OBSERVABILITY.md|import-issues-once.sh|ADOPTION.md|adopt.md'

# Prohibition/prose markers — a line that NEGATES the pattern is documentation, not code
prohibition='[Nn]ever|[Ff]orbid|do(n.t| not)|NOT |no \`gh|must never|allowlist|read.state|authority'

violations=0
while IFS= read -r f; do
  base=$(basename "$f")
  echo "$base" | grep -qE "$allowlist" && continue

  # Find read-state patterns, excluding prose/prohibition + markdown bullet/quote lines
  # JUSTIFIED: grep stderr suppressed + `|| true` — a clean file (no forbidden pattern) makes the pipeline exit 1; empty $hits is the pass case, verified by the [ -n "$hits" ] check
  hits=$(grep -nE "$read_patterns" "$f" 2>/dev/null | grep -vE "$prohibition" | grep -vE '^[0-9]+:[[:space:]]*(>|#|-|\*|//)' || true)
  if [ -n "$hits" ]; then
    echo "✗ $f reads task/issue state from GitHub (authority inversion):"
    echo "$hits" | sed 's/^/    /'
    violations=$((violations + 1))
  fi
# JUSTIFIED: find stderr suppressed — a scanned dir (e.g. .github/workflows) may be absent in a partial checkout; missing dirs simply contribute no files to scan
done < <(find .claude/scripts .claude/hooks .claude/agents .github/workflows -type f \( -name '*.sh' -o -name '*.md' -o -name '*.yml' \) 2>/dev/null)

if [ "$violations" -gt 0 ]; then
  echo
  echo "✗ $violations authority-inversion violation(s)."
  echo "  TASKS.md is the sole source of truth for task state. Issues are write-only."
  echo "  If you need spec/task state, read tasks/TASKS.md — never the GitHub API."
  exit 1
fi
echo "✓ No issue-authority inversion: task state is read only from TASKS.md"
