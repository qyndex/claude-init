#!/usr/bin/env bash
# codify-rule backstop — Round 13 Fix 3.
#
# Nightly safety net for the "recurring incident → semgrep rule" loop. A subagent can't
# invoke a slash command, so even when the reviewer/security agents note recurred_at >= 2
# the rule may never get drafted. This scans for recurred incidents that have NO matching
# .semgrep/learned/<id>.yml and queues a `priority: security` task to run /codify-rule.
#
# Reuses memory-index.sh --recurred — the SAME query /codify-rule lists candidates from —
# so there is one definition of "recurred". Idempotent: findings-to-tasks.sh dedups by summary.
#
# Invoked nightly by dream-cron.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"

command -v jq >/dev/null 2>&1 || { echo "codify-backstop: jq required — skipping"; exit 0; }
[ -x .claude/scripts/memory-index.sh ] || { echo "codify-backstop: memory-index.sh missing — skipping"; exit 0; }

findings="$(mktemp)"; count=0
while IFS= read -r id; do
  [ -z "$id" ] && continue
  [ -f ".semgrep/learned/${id}.yml" ] && continue   # rule already drafted — loop closed
  echo "- [ ] Run /codify-rule ${id} — incident recurred >=2x with no .semgrep/learned rule yet (owner: @security-team)" >> "$findings"
  count=$((count + 1))
done < <(bash .claude/scripts/memory-index.sh query --type incident --recurred 2>/dev/null | jq -r '.id // empty' 2>/dev/null)

if [ "$count" -gt 0 ]; then
  bash .claude/scripts/findings-to-tasks.sh "$findings" --priority security --source codify-rule-backstop
fi
rm -f "$findings"
echo "codify-rule-backstop: queued $count codify task(s)"
