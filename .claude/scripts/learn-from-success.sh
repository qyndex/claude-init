#!/usr/bin/env bash
# Negative outcome learning (Round 5 E10).
#
# The audit found we record pain (incidents, failed verifies) but ignore
# cheap successes — sessions where an Opus agent solved a problem in 2 turns
# that Sonnet could have done. This script analyzes 30-day cost-summary +
# usage logs and emits routing suggestions.
#
# Output: .claude/memory/audits/cost-trend-<date>.md
#
# Insights it surfaces:
#   - "debugger agent invoked 40× this quarter, avg 2.3 turns → consider Sonnet"
#   - "architect spent $X on Opus across 30 days — vs Sonnet budget would be $Y"
#   - "skill X invoked 200× but only 3 unique result-shapes → consider caching"
#   - "feature-stream consistently times out at maxTurns — too low, raise to N"

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

USAGE_LOG=".claude/hooks/.log/usage.jsonl"
SUMMARY=".claude/hooks/.log/cost-summary.json"
AUDIT_DIR=".claude/memory/audits"
mkdir -p "$AUDIT_DIR"

OUT="$AUDIT_DIR/cost-trend-$(date +%Y-%m-%d).md"

if [ ! -f "$USAGE_LOG" ]; then
  echo "No usage log yet ($USAGE_LOG). Skipping trend analysis." > "$OUT"
  echo "✓ Wrote $OUT (no data)"
  exit 0
fi

# Run cost report to refresh summary
bash .claude/scripts/cost-report.sh month >/dev/null 2>&1

{
  echo "# Cost trend — 30-day routing insights"
  echo
  echo "Generated: $(date -Iseconds) by .claude/scripts/learn-from-success.sh"
  echo
  echo "## Headline"
  if [ -f "$SUMMARY" ]; then
    jq -r '"- Spent: $\(.total_usd | tostring) of $\(.monthly_cap_usd) (\(.pct_used | tostring)%)"' "$SUMMARY"
    echo
    echo "## By agent (sorted by spend)"
    echo
    jq -r '.by_agent | to_entries | sort_by(-.value) | .[] | "- $\(.value | . * 100 | floor / 100): \(.key)"' "$SUMMARY"
  fi
  echo

  # Top agents by invocation count.
  # Gap-audit G30: usage.jsonl has no agent field writer — the real per-agent
  # invocation record is subagent.jsonl (written by subagent-stop.sh on every
  # SubagentStop). Read that; keep usage.jsonl as a secondary source if a
  # future writer tags it.
  echo "## Invocation frequency (top 10)"
  echo
  if command -v jq >/dev/null; then
    SUBAGENT_LOG=".claude/hooks/.log/subagent.jsonl"
    if [ -s "$SUBAGENT_LOG" ]; then
      # JUSTIFIED: jq error output discarded — malformed digest lines are skipped; this is an advisory report
      jq -r '.agent_type // empty' "$SUBAGENT_LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -10 | \
        awk '{printf "- %s: %d invocations\n", $2, $1}'
    else
      # JUSTIFIED: jq error output discarded — a malformed/partial usage log yields no agent lines, so the frequency table is simply empty for this advisory report
      jq -r 'select(.agent) | .agent' "$USAGE_LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -10 | \
        awk '{printf "- %s: %d invocations\n", $2, $1}'
    fi
  fi
  echo

  # Routing suggestions
  echo "## Routing suggestions"
  echo
  echo "These are HEURISTIC — review before acting. The goal is to surface candidates for downgrade, not auto-route."
  echo

  # Agents that spent >$20 on Opus where avg turns < 5
  if command -v jq >/dev/null && [ -s "$USAGE_LOG" ]; then
    # JUSTIFIED: jq error output discarded — a malformed usage line is skipped; the empty case is caught by the fallback literal at the end of this pipeline
    jq -r '
      select((.model // "" | startswith("claude-opus")) and .agent != null) |
      {agent, cost: .total_cost_usd, turns: (.turn_count // 1)}
    # JUSTIFIED: the redirect drops jq stderr on a malformed usage line so it is skipped; the empty case is caught by the fallback literal at the end of this pipeline
    ' "$USAGE_LOG" 2>/dev/null | jq -s '
      group_by(.agent) |
      map({
        agent: .[0].agent,
        total_cost: (map(.cost) | add),
        invocations: length,
        avg_turns: ((map(.turns) | add) / length)
      }) |
      map(select(.total_cost > 20 and .avg_turns < 5)) |
      sort_by(-.total_cost) | .[] |
      "- **\(.agent)**: spent $\(.total_cost) over \(.invocations) invocations, avg \(.avg_turns) turns — consider Sonnet (short interactions don'\''t need Opus reasoning depth)"
      # JUSTIFIED: jq error output discarded and the fallback echo covers it — no agent-tagged data is the expected fresh-repo case, rendered as the no-data note
    ' 2>/dev/null || echo "_(no data yet — need >30d of agent-tagged usage)_"
  fi
  echo

  echo "## Cheap-but-frequent skills"
  echo
  echo "Skills invoked frequently with low per-invocation cost are caching candidates:"
  echo
  if command -v jq >/dev/null && [ -s "$USAGE_LOG" ]; then
    # JUSTIFIED: jq error output discarded — malformed usage lines are skipped; the empty case is caught by the fallback literal at the end of this pipeline
    jq -r '
      select(.skill != null) |
      {skill, cost: .total_cost_usd}
    # JUSTIFIED: the redirect drops jq stderr on a malformed usage line so it is skipped; the empty case is caught by the fallback literal at the end of this pipeline
    ' "$USAGE_LOG" 2>/dev/null | jq -s '
      group_by(.skill) | map({
        skill: .[0].skill,
        invocations: length,
        total_cost: (map(.cost) | add)
      }) | map(select(.invocations >= 20)) | sort_by(-.invocations) | .[] |
      "- \(.skill): \(.invocations) invocations, $\(.total_cost) total"
      # JUSTIFIED: jq error output discarded and the fallback echo covers it — too little skill-usage data is the expected fresh-repo case, rendered as the insufficient-data note
    ' 2>/dev/null || echo "_(insufficient data)_"
  fi
  echo

  echo "## Actions (for human review)"
  echo
  echo "1. Demote candidates above to \`model: sonnet\` in their frontmatter."
  echo "2. For high-frequency skills, consider:"
  echo "   - \`disable-model-invocation: true\` (operator must explicitly invoke)"
  echo "   - Adding a result-cache layer in the skill body"
  echo "3. Investigate feature-stream timeouts (\`grep -c 'max turns reached' .claude/hooks/.log/\`)."
  echo
  echo "---"
  echo
  echo "Suggestions are seeded into \`tasks/TASKS.md\` with priority \`cleanup\` via findings-to-tasks.sh."
} > "$OUT"

# Seed top 3 suggestions as cleanup tasks
suggestions=$(grep -E '^- \*\*[a-z-]+\*\*:.*consider Sonnet' "$OUT" | head -3)
if [ -n "$suggestions" ]; then
  tmp=$(mktemp)
  echo "$suggestions" | sed 's/^- \*\*\([a-z-]*\)\*\*: .*/- [ ] Demote \1 agent to model: sonnet per cost-trend audit/' > "$tmp"
  bash .claude/scripts/findings-to-tasks.sh "$tmp" \
    --priority cleanup \
    --source "cost-trend-$(date +%Y-%m-%d)" \
    --default-owner "@cost-watch" >/dev/null 2>&1
  rm -f "$tmp"
fi

echo "✓ Wrote $OUT"
