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

INPUT_DIR="${1:-/tmp}"
[ -d "$INPUT_DIR" ] || { echo "Artifact directory unavailable: $INPUT_DIR" >&2; exit 1; }
while IFS= read -r f; do
  jq -e '
    (.stack | type == "string" and length > 0) and
    all(.shipped, .mediated, .escalated; type == "number" and . >= 0 and . == floor)
  ' "$f" >/dev/null || { echo "Malformed dependency summary: $f" >&2; exit 1; }
  stack=$(jq -r .stack "$f")
  shipped=$(jq -r .shipped "$f")
  mediated=$(jq -r .mediated "$f")
  escalated=$(jq -r .escalated "$f")
  shipped_total=$((shipped_total + shipped))
  mediated_total=$((mediated_total + mediated))
  escalated_total=$((escalated_total + escalated))
  stacks+=("$stack: $shipped shipped, $mediated mediated, $escalated escalated")
done < <(if [ "$INPUT_DIR" = "/tmp" ]; then
  find "$INPUT_DIR" -maxdepth 3 -path '*/bump-results-*/summary.json' -type f
else
  find "$INPUT_DIR" -type f -name summary.json
fi)

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

if [ "${#stacks[@]}" -eq 0 ]; then
  echo "No applicable stack artifacts; no dependency changes were evaluated." >> "$report"
fi
for line in "${stacks[@]+"${stacks[@]}"}"; do
  echo "- $line" >> "$report"
done

# JUSTIFIED: gh may be unavailable/unauthenticated — the muted call plus the fallback embeds a "gh unavailable" note in the report rather than aborting the rollup
open_prs="$(gh pr list --label 'auto-bump' --limit 20 2>/dev/null || echo 'gh unavailable')"
# JUSTIFIED: same — a muted gh call with a fallback keeps the report generating when gh is absent
open_issues="$(gh issue list --label 'auto-bump:escalated' --limit 10 2>/dev/null || echo 'gh unavailable')"

cat >> "$report" <<EOF

## Open PRs

\`\`\`
$open_prs
\`\`\`

## Open issues (escalations)

\`\`\`
$open_issues
\`\`\`

## Next steps

- Review + merge \`auto-bump:patch\` PRs (or let auto-merge handle them)
- Hand-review \`auto-bump:major\` + \`auto-bump:vuln-fix\` PRs
- Triage escalation issues during next standup
EOF

echo "✓ Wrote $report"
echo "  shipped=$shipped_total mediated=$mediated_total escalated=$escalated_total"
