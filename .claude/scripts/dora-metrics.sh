#!/usr/bin/env bash
# DORA metrics — Round 8 F.
#
# The 4 numbers every exec asks for, computed from git + GitHub API:
#   1. Deployment frequency  — pushes to main per day
#   2. Lead time for changes — PR open → merge median
#   3. Change failure rate   — % of deploys that caused rollback/hotfix
#   4. Time to restore       — incident open → close median
#
# Emits .claude/memory/dora/YYYY-MM.json + a rolling 90-day rollup.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

PERIOD="${1:-month}"   # day | week | month | quarter
OUT_DIR=".claude/memory/dora"
mkdir -p "$OUT_DIR"

case "$PERIOD" in
  # JUSTIFIED: GNU/BSD date portability — 2>/dev/null suppresses the GNU-form failure on macOS so the `||` BSD-form (-v) runs; one of the two always succeeds
  day)     since=$(date -d '1 day ago' -Iseconds 2>/dev/null || date -v -1d -Iseconds); label="day" ;;
  # JUSTIFIED: GNU/BSD date portability — GNU form tried first, BSD `-v` form is the fallback on macOS
  week)    since=$(date -d '7 days ago' -Iseconds 2>/dev/null || date -v -7d -Iseconds); label="week" ;;
  # JUSTIFIED: GNU/BSD date portability — GNU form tried first, BSD `-v` form is the fallback on macOS
  month)   since=$(date -d '30 days ago' -Iseconds 2>/dev/null || date -v -30d -Iseconds); label="month" ;;
  # JUSTIFIED: GNU/BSD date portability — GNU form tried first, BSD `-v` form is the fallback on macOS
  quarter) since=$(date -d '90 days ago' -Iseconds 2>/dev/null || date -v -90d -Iseconds); label="quarter" ;;
  *) echo "PERIOD must be day|week|month|quarter"; exit 1 ;;
esac

# ─── 1. Deployment frequency — pushes to main per day ───────────────────
# JUSTIFIED: git log — 2>/dev/null hides "unknown revision main" on repos without a main branch; wc then yields 0 deploys, the correct baseline
deploys=$(git log main --since="$since" --oneline 2>/dev/null | wc -l | tr -d ' ')
case "$PERIOD" in
  day)     days_in_period=1 ;;
  week)    days_in_period=7 ;;
  month)   days_in_period=30 ;;
  quarter) days_in_period=90 ;;
esac
deploys_per_day=$(awk "BEGIN { printf \"%.2f\", $deploys / $days_in_period }")

# ─── 2. Lead time — PR open→merge median (via gh) ───────────────────────
lead_time_h="?"
if command -v gh >/dev/null 2>&1; then
  # JUSTIFIED: gh API call — 2>/dev/null + `|| echo '[]'` make an unauthed/offline gh degrade to an empty PR set, leaving lead time as "?" rather than crashing
  prs=$(gh pr list --state merged --search "merged:>$since" --json createdAt,mergedAt --limit 100 2>/dev/null || echo '[]')
  if [ "$prs" != "[]" ] && [ -n "$prs" ]; then
    lead_time_h=$(echo "$prs" | jq -r '
      [.[] | (
        (.mergedAt | sub("\\..*Z$"; "Z") | fromdateiso8601) -
        (.createdAt | sub("\\..*Z$"; "Z") | fromdateiso8601)
      ) / 3600]
      | sort | .[length / 2] // 0
      | floor
    # JUSTIFIED: jq median over PR timestamps — 2>/dev/null + `|| echo "?"` yield the documented unknown sentinel if any date fails to parse
    ' 2>/dev/null || echo "?")
  fi
fi

# ─── 3. Change failure rate — % of deploys that triggered a revert/hotfix ─
# JUSTIFIED: git log — 2>/dev/null hides "unknown revision main" on a repo without a main branch; wc then yields 0 reverts, the correct baseline
revert_count=$(git log main --since="$since" --oneline --grep='^Revert\|^revert:\|^fix.*revert\|^hotfix' 2>/dev/null | wc -l | tr -d ' ')
if [ "$deploys" -gt 0 ]; then
  cfr=$(awk "BEGIN { printf \"%.1f\", ($revert_count / $deploys) * 100 }")
else
  cfr="0.0"
fi

# ─── 4. Time to restore — incident open→close median (from incidents/) ──
ttr_h="?"
if [ -d .claude/memory/incidents ]; then
  # Heuristic: incidents have `opened:` and `closed:` ISO timestamps
  # JUSTIFIED: grep over the incidents glob — 2>/dev/null swallows "no match" when no incident has a closed: line; empty list yields ttr_h "?", the documented default
  ttr_h=$(grep -lE '^closed:' .claude/memory/incidents/*.md 2>/dev/null | head -20 | while read -r f; do
    opened=$(grep -E '^opened:' "$f" | head -1 | sed 's/opened:[[:space:]]*//')
    closed=$(grep -E '^closed:' "$f" | head -1 | sed 's/closed:[[:space:]]*//')
    if [ -n "$opened" ] && [ -n "$closed" ]; then
      # JUSTIFIED: GNU/BSD date portability — 2>/dev/null + `|| echo 0` turn an unparseable incident timestamp into a sentinel 0 that the guard below rejects
      o=$(date -d "$opened" +%s 2>/dev/null || echo 0)
      # JUSTIFIED: same as above — an unparseable `closed:` stamp becomes 0 and is filtered by the `[ "$c" -gt "$o" ]` check
      c=$(date -d "$closed" +%s 2>/dev/null || echo 0)
      [ "$o" -gt 0 ] && [ "$c" -gt "$o" ] && echo $(( (c - o) / 3600 ))
    fi
  done | sort -n | awk '{a[NR]=$1} END{ if (NR>0) print a[int((NR+1)/2)]; else print "?" }')
fi

# DORA classification (Google research):
# Elite: deploys multiple/day, lead < 1h, CFR 0-15%, TTR < 1h
# High:  deploys 1/day-1/week, lead 1d-1w, CFR 0-15%, TTR < 1d
# Medium: 1/week-1/mo, lead 1w-1mo, CFR 0-15%, TTR < 1d
# Low:   < 1/mo, lead 1-6mo, CFR 0-15%, TTR < 1w
band="unknown"
# JUSTIFIED: printf float→int round; 2>/dev/null + `|| echo 0` default a non-numeric/empty deploys_per_day to 0 so the -ge comparison stays valid
if [ "$(printf '%.0f' "$deploys_per_day" 2>/dev/null || echo 0)" -ge 3 ]; then
  band="elite"
# JUSTIFIED: printf float→int round; 2>/dev/null + `|| echo 0` default a non-numeric/empty deploys_per_day to 0 so the band comparison never errors
elif [ "$(printf '%.0f' "$deploys_per_day" 2>/dev/null || echo 0)" -ge 1 ]; then
  band="high"
elif [ "$deploys" -gt 0 ]; then
  band="medium"
else
  band="low"
fi

# Write JSON
ts_now=$(date -Iseconds)
out_file="$OUT_DIR/$(date +%Y-%m).json"

jq -nc \
  --arg period "$PERIOD" \
  --arg since "$since" \
  --arg now "$ts_now" \
  --argjson deploys "${deploys:-0}" \
  --arg deploys_per_day "$deploys_per_day" \
  --arg lead_time_h "$lead_time_h" \
  --arg cfr "$cfr" \
  --arg ttr_h "$ttr_h" \
  --arg band "$band" \
  '{
    period: $period,
    since: $since,
    computed_at: $now,
    deployment_frequency: { deploys: $deploys, per_day: $deploys_per_day },
    lead_time_for_changes_hours: ($lead_time_h | tonumber? // null),
    change_failure_rate_pct: ($cfr | tonumber? // null),
    time_to_restore_hours: ($ttr_h | tonumber? // null),
    dora_band: $band
  }' > "$out_file"

echo "✓ DORA metrics written to $out_file"
cat "$out_file" | jq .
