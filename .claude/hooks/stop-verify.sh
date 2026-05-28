#!/usr/bin/env bash
# Stop hook. Reminds Claude to verify before claiming done, when the session
# has produced uncommitted changes touching production code.

set -uo pipefail

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$dirty" -eq 0 ]; then
  exit 0
fi

# Check if any production files changed
prod_changed=$(git diff --name-only HEAD 2>/dev/null | grep -Ev '^(specs/|plans/|tasks/|docs/|.claude/|.github/|verify/|README|CHANGELOG)' | head -5 || true)

if [ -z "$prod_changed" ]; then
  exit 0
fi

# Check if a recent verify report exists
recent_verify=""
if [ -d verify ]; then
  recent_verify=$(find verify -name 'REPORT.md' -mtime -1 -print 2>/dev/null | head -1 || true)
fi

if [ -z "$recent_verify" ]; then
  cat <<EOF
{
  "decision": "block",
  "reason": "Production files changed but no recent verification report (verify/*/REPORT.md from the last 24h). Run /verify before ending. To override: re-send your last message; Claude Code Stop-hook protocol allows resubmission to bypass a block. (Sending the word 'continue' is not a special token — it just resubmits.)"
}
EOF
  exit 0
fi

exit 0
