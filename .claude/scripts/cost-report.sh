#!/usr/bin/env bash
# Aggregate cost report across rolling windows + per-agent attribution.
# Read by /cost-report command, pre-spawn-cost-gate hook, and Cloud Routine
# pre_flight check.
#
# Sources: ccusage (per-session JSONL), .claude/hooks/.log/usage.jsonl

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

LOG_DIR=".claude/hooks/.log"
SUMMARY_FILE="$LOG_DIR/cost-summary.json"
mkdir -p "$LOG_DIR"

WINDOW="month"     # day | week | month
INITIATIVE=""
MONTHLY_CAP_USD="${CLAUDE_MONTHLY_CAP_USD:-500}"

# Round 7 E: --by-initiative flag for sunk-cost reports
while [ $# -gt 0 ]; do
  case "$1" in
    --by-initiative) INITIATIVE="$2"; shift 2 ;;
    day|week|month) WINDOW="$1"; shift ;;
    *) shift ;;
  esac
done

# Date thresholds
case "$WINDOW" in
  # JUSTIFIED: GNU `date -d` stderr suppressed so BSD/macOS falls through to the `date -v` form; one of the two always succeeds
  day)   since=$(date -d '1 day ago' -Iseconds 2>/dev/null || date -v -1d -Iseconds) ;;
  week)  since=$(date -d '7 days ago' -Iseconds 2>/dev/null || date -v -7d -Iseconds) ;;
  month) since=$(date -d '30 days ago' -Iseconds 2>/dev/null || date -v -30d -Iseconds) ;;
  *) echo "Window must be day|week|month"; exit 1 ;;
esac

# ─── Aggregate from ccusage ─────────────────────────────────────────────
total=0
by_agent_json='{}'
if command -v ccusage >/dev/null 2>&1 || command -v npx >/dev/null 2>&1; then
  # JUSTIFIED: ccusage/npx stderr suppressed — when the tool is absent or errors, the chain falls through to the empty-array literal
  blocks=$(ccusage blocks --json --since "$since" 2>/dev/null || \
           npx --no-install ccusage blocks --json --since "$since" 2>/dev/null || echo '[]')
  total=$(printf '%s' "$blocks" | jq '[.[].total_cost_usd] | add // 0')
fi

# ─── Aggregate from local usage.jsonl (fallback + agent attribution) ────
if [ -f "$LOG_DIR/usage.jsonl" ]; then
  if [ "$total" = "0" ]; then
    total=$(awk -v since="$since" '
      {
        if (match($0, /"timestamp":"([^"]+)"/, ts) && ts[1] >= since) {
          if (match($0, /"total_cost_usd":([0-9.]+)/, c)) sum += c[1]
        }
      }
      END { print sum + 0 }
    ' "$LOG_DIR/usage.jsonl")
  fi

  # Round 5 D11: per-agent attribution. Reads agent field from usage.jsonl
  # (written by hooks when present). Falls back to "main" for un-tagged lines.
  by_agent_json=$(awk -v since="$since" '
    {
      if (match($0, /"timestamp":"([^"]+)"/, ts) && ts[1] >= since) {
        agent = "main"
        if (match($0, /"agent":"([^"]+)"/, a)) agent = a[1]
        if (match($0, /"total_cost_usd":([0-9.]+)/, c)) byagent[agent] += c[1]
      }
    }
    END {
      printf "{"; first = 1
      for (k in byagent) {
        if (!first) printf ","
        printf "\"%s\":%.4f", k, byagent[k]
        first = 0
      }
      printf "}"
    }
  ' "$LOG_DIR/usage.jsonl")
  [ -z "$by_agent_json" ] && by_agent_json='{}'
fi

# ─── Write summary for downstream consumers ─────────────────────────────
cat > "$SUMMARY_FILE" <<EOF
{
  "window": "$WINDOW",
  "since": "$since",
  "as_of": "$(date -Iseconds)",
  "total_usd": $total,
  "monthly_cap_usd": $MONTHLY_CAP_USD,
  "remaining_usd": $(awk "BEGIN { print $MONTHLY_CAP_USD - $total }"),
  "pct_used": $(awk "BEGIN { print ($total / $MONTHLY_CAP_USD) * 100 }"),
  "by_agent": $by_agent_json
}
EOF

# ─── Output ─────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  echo "=== Cost report ($WINDOW) ==="
  jq -r '
    "Period: \(.window)",
    "Since:  \(.since)",
    "As of:  \(.as_of)",
    "",
    "Spent:  $\(.total_usd | tostring)",
    "Cap:    $\(.monthly_cap_usd)",
    "Left:   $\(.remaining_usd | tostring)",
    "Used:   \(.pct_used | tostring)%"
  ' "$SUMMARY_FILE"

  echo
  echo "=== By agent ==="
  # JUSTIFIED: jq stderr suppressed — an empty by_agent map prints nothing, which is the correct display for a no-attribution window
  jq -r '.by_agent | to_entries | sort_by(-.value) | .[] | "  $\(.value | . * 100 | floor / 100): \(.key)"' "$SUMMARY_FILE" 2>/dev/null

  pct=$(jq -r .pct_used "$SUMMARY_FILE" | cut -d. -f1)
  if [ "$pct" -gt 80 ]; then
    echo
    echo "⚠ Over 80% of monthly cap. Consider:"
    echo "  - Pausing autopilot routines"
    echo "  - Switching scheduled tasks to Sonnet/Haiku"
    echo "  - /cleanup to reduce backlog"
  fi
fi

# ─── Round 7 E: --by-initiative sunk-cost report ──────────────────────
if [ -n "$INITIATIVE" ]; then
  AUDIT_DIR=".claude/memory/audits"
  mkdir -p "$AUDIT_DIR"
  out="$AUDIT_DIR/sunk-cost-${INITIATIVE}-$(date +%Y-%m-%d).md"

  # Tokens / $ from usage.jsonl tagged with initiative
  init_total=0
  init_sessions=0
  if [ -f "$LOG_DIR/usage.jsonl" ] && command -v jq >/dev/null; then
    # JUSTIFIED: jq stderr suppressed — a malformed/empty usage.jsonl yields the default-0 init_total seeded above
    init_total=$(jq -s --arg id "$INITIATIVE" \
      '[.[] | select(.initiative == $id) | .total_cost_usd // 0] | add // 0' \
      "$LOG_DIR/usage.jsonl" 2>/dev/null)
    # JUSTIFIED: jq stderr suppressed — a malformed/empty usage.jsonl yields the default-0 init_sessions seeded above
    init_sessions=$(jq -s --arg id "$INITIATIVE" \
      '[.[] | select(.initiative == $id)] | length' \
      "$LOG_DIR/usage.jsonl" 2>/dev/null)
  fi

  # Commits with Initiative: trailer or Spec: trailer pointing at this initiative's specs
  init_commits=0
  init_authors=""
  if git rev-parse --git-dir >/dev/null 2>&1; then
    # JUSTIFIED: git log stderr suppressed — a repo with no matching commits emits nothing, yielding a count of 0
    init_commits=$(git log --all --grep="Initiative: $INITIATIVE\|Initiative:$INITIATIVE" --oneline 2>/dev/null | wc -l | tr -d ' ')
    # JUSTIFIED: git log stderr suppressed — no matching commits yields an empty author list, rendered as "unknown" downstream
    init_authors=$(git log --all --grep="Initiative: $INITIATIVE\|Initiative:$INITIATIVE" --format='%an' 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
  fi

  # Specs under this initiative
  specs_shipped=0
  specs_dropped=0
  specs_paused=0
  specs_active=0
  for spec in specs/active/*.md specs/archive/*.md specs/archive/*/*.md; do
    [ -f "$spec" ] || continue
    # JUSTIFIED: grep stderr suppressed — a spec lacking an initiative front-matter line is a non-match, correctly excluded from the tally
    if grep -qE "^initiative:[[:space:]]*${INITIATIVE}\\b" "$spec" 2>/dev/null; then
      status=$(grep -E '^status:' "$spec" | head -1 | sed 's/status:[[:space:]]*//' | sed 's/[[:space:]]*#.*$//' | tr -d ' "')
      case "$status" in
        shipped) specs_shipped=$((specs_shipped + 1)) ;;
        dropped|abandoned) specs_dropped=$((specs_dropped + 1)) ;;
        paused) specs_paused=$((specs_paused + 1)) ;;
        *) specs_active=$((specs_active + 1)) ;;
      esac
    fi
  done

  # Days active: from initiative file mtime range
  days_active="?"
  # JUSTIFIED: ls stderr suppressed — unmatched globs are not errors here; an empty result means no initiative file, handled by the -n test below
  init_file=$(ls initiatives/active/${INITIATIVE}*.md initiatives/archive/${INITIATIVE}*.md 2>/dev/null | head -1)
  if [ -n "$init_file" ]; then
    created=$(grep -E '^created:' "$init_file" | head -1 | sed 's/created:[[:space:]]*//' | tr -d '"')
    if [ -n "$created" ]; then
      # JUSTIFIED: date stderr suppressed both ways — GNU then BSD parse attempts; an unparseable date falls through to the 0 literal, handled by the -gt 0 guard
      created_epoch=$(date -d "$created" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$created" +%s 2>/dev/null || echo 0)
      [ "$created_epoch" -gt 0 ] && days_active=$(( ($(date +%s) - created_epoch) / 86400 ))
    fi
  fi

  cat > "$out" <<EOF
# Sunk-cost report — initiative $INITIATIVE — $(date -Iseconds)

## Resource accounting

| Dimension | Value |
|---|---|
| Wall-clock days active | $days_active |
| Tokens \$ spent | \$${init_total} |
| Sessions tagged | $init_sessions |
| Commits | $init_commits |
| Engineer authors | ${init_authors:-unknown} |

## Specs under this initiative

| Status | Count |
|---|---|
| shipped | $specs_shipped |
| dropped/abandoned | $specs_dropped |
| paused | $specs_paused |
| active | $specs_active |

## Value vs cost ratio

- Value: $specs_shipped specs shipped
- Sunk: \$${init_total} + $init_commits engineer-commits over $days_active days

## Linked artifacts

- Initiative: $init_file
- Pivot manifests: \`grep -rl "$INITIATIVE" pivots/active/ pivots/archive/\`
- Post-mortem (if abandoned): \`.claude/memory/post-mortems/${INITIATIVE}-*.md\`
- Decisions log entries: \`grep "$INITIATIVE" .swarms/coordinator/decisions.log\`

## Caveats

- Token attribution requires Round 7 E \`current-initiative\` state file to be populated DURING the work. Historical sessions without the tag fall back to wall-clock + commit proxies.
- Engineer-commits is a proxy for person-time, not a measure of effort or outcome.
EOF

  echo
  echo "✓ Sunk-cost report: $out"
  echo "  \$${init_total} · $init_sessions sessions · $init_commits commits · $days_active days · ships=$specs_shipped drops=$specs_dropped"
fi
