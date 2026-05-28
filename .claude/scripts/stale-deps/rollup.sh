#!/usr/bin/env bash
# Stale-deps rollup — Round 8 B.
# Aggregates results from each stack's bump-loop summary into a single report.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

shipped_total=0
mediated_total=0
escalated_total=0
stacks=()

for f in /tmp/bump-results-*/summary.json; do
  [ -f "$f" ] || continue
  stack=$(jq -r .stack "$f")
  shipped=$(jq -r .shipped "$f")
  mediated=$(jq -r .mediated "$f")
  escalated=$(jq -r .escalated "$f")
  shipped_total=$((shipped_total + shipped))
  mediated_total=$((mediated_total + mediated))
  escalated_total=$((escalated_total + escalated))
  stacks+=("$stack: $shipped shipped, $mediated mediated, $escalated escalated")
done

mkdir -p .claude/memory/audits
report=".claude/memory/audits/stale-deps-$(date +%Y-%m-%d).md"

cat > "$report" <<EOF
# Stale-deps autofix — $(date -Iseconds)

## Summary

| Outcome | Count |
|---|---|
| Shipped (clean bump) | $shipped_total |
| Mediated (claude fixed breaking changes) | $mediated_total |
| Escalated (human needed) | $escalated_total |

## Per stack

EOF

for line in "${stacks[@]}"; do
  echo "- $line" >> "$report"
done

cat >> "$report" <<EOF

## Open PRs

\`\`\`
$(gh pr list --label 'auto-bump' --limit 20 2>/dev/null || echo 'gh unavailable')
\`\`\`

## Open issues (escalations)

\`\`\`
$(gh issue list --label 'auto-bump:escalated' --limit 10 2>/dev/null || echo 'gh unavailable')
\`\`\`

## Next steps

- Review + merge \`auto-bump:patch\` PRs (or let auto-merge handle them)
- Hand-review \`auto-bump:major\` + \`auto-bump:vuln-fix\` PRs
- Triage escalation issues during next standup
EOF

echo "✓ Wrote $report"
echo "  shipped=$shipped_total mediated=$mediated_total escalated=$escalated_total"
