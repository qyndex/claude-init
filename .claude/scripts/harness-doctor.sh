#!/usr/bin/env bash
# Harness health check — AC-35.
# Runs the same structural checks as validate.sh but outputs machine-readable JSON.
# Used by harness-validate.yml to upload a structured artifact and by T-109.
#
# Usage:
#   bash .claude/scripts/harness-doctor.sh          # human-readable summary
#   bash .claude/scripts/harness-doctor.sh --json   # JSON array of check results

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

JSON_MODE=0
[ "${1:-}" = "--json" ] && JSON_MODE=1

result_file=$(mktemp)
trap 'rm -f "$result_file"' EXIT
printf '[\n' > "$result_file"
first_result=1

add_result() {
  local check="$1" status="$2" detail="$3"
  local entry
  entry=$(jq -nc --arg c "$check" --arg s "$status" --arg d "$detail" \
    '{check:$c,status:$s,detail:$d}')
  if [ "$first_result" -eq 1 ]; then
    first_result=0
    printf '%s\n' "$entry" >> "$result_file"
  else
    printf ',%s\n' "$entry" >> "$result_file"
  fi
  if [ "$JSON_MODE" -eq 0 ]; then
    [ "$status" = "pass" ] && printf '  ✓ %s\n' "$check" || printf '  ✗ %s: %s\n' "$check" "$detail"
  fi
}

[ "$JSON_MODE" -eq 0 ] && printf '\nHarness Doctor\n──────────────\n'

# Core files present
for f in .claude/CLAUDE.md .claude/settings.json .mcp.json tasks/TASKS.md; do
  if [ -f "$f" ]; then
    add_result "$f exists" "pass" ""
  else
    add_result "$f exists" "fail" "missing required file"
  fi
done

# JSON validity
for f in .claude/settings.json .mcp.json; do
  if [ -f "$f" ]; then
    if jq -e . "$f" > /dev/null 2>&1; then
      add_result "$f valid JSON" "pass" ""
    else
      add_result "$f valid JSON" "fail" "jq parse error"
    fi
  fi
done

# disableBypassPermissionsMode (nested under .permissions in this harness)
if [ -f .claude/settings.json ]; then
  val=$(jq -r '(.permissions.disableBypassPermissionsMode // .disableBypassPermissionsMode) // ""' .claude/settings.json 2>/dev/null)
  if [ "$val" = "disable" ]; then
    add_result "disableBypassPermissionsMode=disable" "pass" ""
  else
    add_result "disableBypassPermissionsMode=disable" "fail" "got: $val"
  fi
fi

# Hook executables
hook_fails=0
while IFS= read -r sh; do
  if [ ! -x "$sh" ]; then
    add_result "hook executable: $sh" "fail" "not executable"
    hook_fails=$((hook_fails + 1))
  fi
done < <(find .claude/hooks -name '*.sh' -type f 2>/dev/null)
[ "$hook_fails" -eq 0 ] && add_result "hooks executable" "pass" ""

# Constitution size
if [ -f .claude/CLAUDE.md ]; then
  lines=$(wc -l < .claude/CLAUDE.md | tr -d ' ')
  if [ "$lines" -le 300 ]; then
    add_result "constitution ≤300 lines" "pass" "${lines} lines"
  else
    add_result "constitution ≤300 lines" "fail" "${lines} lines (cap 300)"
  fi
fi

# @latest pins
if [ -f .mcp.json ] && command -v jq >/dev/null 2>&1; then
  unpinned=$(jq -r '.mcpServers[]?.args[]? // empty' .mcp.json 2>/dev/null | grep -E '@latest' || true)
  if [ -z "$unpinned" ]; then
    add_result "no @latest MCP pins" "pass" ""
  else
    add_result "no @latest MCP pins" "fail" "found: $unpinned"
  fi
fi

# Swarm templates
if [ -f .swarms/templates/handoff.yaml ]; then
  if grep -q 'tdd_state' .swarms/templates/handoff.yaml 2>/dev/null; then
    add_result "handoff.yaml has tdd_state" "pass" ""
  else
    add_result "handoff.yaml has tdd_state" "fail" "missing tdd_state block"
  fi
fi

# ─── Memory-plane health (memory-system review §7.6: failures must be loud) ──

# Witness briefs stuck in "(pending)" — the async witness died without anyone noticing
stuck_witness=$(find .claude/memory/.cache/checkpoints -name '*.md' -mtime +2 -exec grep -l '(pending)' {} \; 2>/dev/null | head -3 || true)
if [ -z "$stuck_witness" ]; then
  add_result "no witness briefs stuck pending >2d" "pass" ""
else
  add_result "no witness briefs stuck pending >2d" "fail" "async witness died: $(echo "$stuck_witness" | tr '\n' ' ')"
fi

# Initiative pointers — session-end.sh reads these for token attribution
if [ -s .claude/state/current-initiative ] && [ -s .claude/state/current-spec ]; then
  add_result "initiative/spec pointers present" "pass" ""
else
  add_result "initiative/spec pointers present" "fail" "run: bash .claude/scripts/initiative-state.sh sync"
fi

# Initiative STATE.md freshness (the always-current state answer; 7d budget)
state_md=$(ls -t initiatives/active/*.STATE.md 2>/dev/null | head -1 || true)
if [ -n "$state_md" ]; then
  state_age_d=$(( ( $(date +%s) - $(stat -f %m "$state_md" 2>/dev/null || stat -c %Y "$state_md" 2>/dev/null || echo 0) ) / 86400 ))
  if [ "$state_age_d" -le 7 ]; then
    add_result "initiative STATE.md fresh (≤7d)" "pass" "${state_age_d}d old"
  else
    add_result "initiative STATE.md fresh (≤7d)" "fail" "${state_age_d}d old — run initiative-state.sh sync"
  fi
else
  add_result "initiative STATE.md fresh (≤7d)" "fail" "no STATE.md — run: bash .claude/scripts/initiative-state.sh sync"
fi

# Index lifecycle population — unknown-status entries can't promote or decay
if [ -s .claude/memory/index.jsonl ] && command -v jq >/dev/null 2>&1; then
  idx_total=$(wc -l < .claude/memory/index.jsonl | tr -d ' ')
  idx_unknown=$(jq -rs '[.[] | select(.status == "unknown" or .status == null)] | length' .claude/memory/index.jsonl 2>/dev/null || echo 0)
  if [ "$idx_total" -gt 0 ] && [ $(( idx_unknown * 2 )) -le "$idx_total" ]; then
    add_result "memory index lifecycle ≥50% populated" "pass" "$((idx_total - idx_unknown))/$idx_total"
  else
    add_result "memory index lifecycle ≥50% populated" "fail" "$idx_unknown/$idx_total unknown — backfill frontmatter + rebuild"
  fi
fi

# Skill-use telemetry (gap-audit G17) — never-used skills + adherence signal
if [ -s .claude/hooks/.log/skill-use.jsonl ]; then
  used=$(jq -r '.skill' .claude/hooks/.log/skill-use.jsonl 2>/dev/null | sort -u | wc -l | tr -d ' ')
  total_sk=$(find .claude/skills -name 'SKILL.md' -type f 2>/dev/null | wc -l | tr -d ' ')
  add_result "skill-use telemetry" "pass" "$used of $total_sk skills invoked at least once (log: .claude/hooks/.log/skill-use.jsonl)"
else
  add_result "skill-use telemetry" "warn" "no skill-use.jsonl yet — skill-use-log.sh hook records Skill invocations once installed"
fi

# Cache hit-rate (gap-audit G1) — warn when measured and below threshold
CACHE_HIT_MIN="${CACHE_HIT_MIN:-40}"
summary=.claude/hooks/.log/cost-summary.json
if [ -f "$summary" ]; then
  age_s=$(( $(date +%s) - $(stat -f %m "$summary" 2>/dev/null || stat -c %Y "$summary" 2>/dev/null || echo 0) ))
  hr=$(jq -r '.cache_hit_rate // -1' "$summary" 2>/dev/null || echo -1)
  hr_int=${hr%.*}; hr_int=${hr_int:-0}
  if [ "$age_s" -gt 86400 ] || [ "$hr_int" -lt 0 ]; then
    add_result "cache hit-rate measured" "pass" "no fresh data — run cost-report.sh to refresh"
  elif [ "$hr_int" -lt "$CACHE_HIT_MIN" ]; then
    add_result "cache hit-rate ≥${CACHE_HIT_MIN}%" "warn" "${hr}% — prefix churn? check CLAUDE.md/agents/skill-frontmatter stability (§IX)"
  else
    add_result "cache hit-rate ≥${CACHE_HIT_MIN}%" "pass" "${hr}%"
  fi
else
  add_result "cache hit-rate measured" "pass" "no cost-summary.json yet — run cost-report.sh"
fi

# Stop-verify bypass surface (gap-audit G48) — blocks logged in the last 7 days
blog=.claude/state/stop-verify-blocks.log
if [ -s "$blog" ]; then
  week_ago=$(date -v-7d -Iseconds 2>/dev/null || date -d '7 days ago' -Iseconds 2>/dev/null)
  recent_blocks=$(awk -F'\t' -v c="$week_ago" 'BEGIN{n=0} $1 >= c {n++} END{print n}' "$blog" 2>/dev/null || echo 0)
  if [ "${recent_blocks:-0}" -gt 0 ]; then
    add_result "stop-verify blocks (7d)" "warn" "$recent_blocks block(s) in the last week — each was either fixed or bypassed by resubmission; review $blog"
  else
    add_result "stop-verify blocks (7d)" "pass" "none recent"
  fi
else
  add_result "stop-verify blocks (7d)" "pass" "no block log yet"
fi

# Feedback intake wiring (gap-audit G60) — connectors ship with empty-default
# env expansion (${KEY:-}), so a "configured" source can still be dead. Check
# the actual env keys; say UNWIRED instead of letting intake look operational.
if [ -f .claude/routines/feedback-poll.yml ]; then
  fb_servers=$(jq -r '.mcpServers | keys[]' .mcp.json 2>/dev/null | grep -iE 'fireflies|intercom|pendo|slack' || true)
  if [ -z "$fb_servers" ]; then
    add_result "feedback intake wiring" "warn" "feedback-poll.yml exists but no feedback-source MCP (fireflies/intercom/pendo/slack) in .mcp.json — copy a catalogue block from _disabled_examples (docs/ADOPTION.md)"
  else
    wired=0
    for s in $fb_servers; do
      # env var names referenced as ${VAR:-} in the server's env block
      vars=$(jq -r --arg s "$s" '.mcpServers[$s].env // {} | to_entries[].value' .mcp.json 2>/dev/null | grep -oE '[A-Z][A-Z0-9_]+' || true)
      for v in $vars; do
        [ -n "$(eval "printf '%s' \"\${$v:-}\"")" ] && wired=$((wired + 1))
      done
    done
    if [ "$wired" -eq 0 ]; then
      add_result "feedback intake wiring" "warn" "feedback-source MCPs present but every auth env key is EMPTY — intake is configured but UNWIRED; export the API keys (docs/ADOPTION.md §feedback)"
    else
      add_result "feedback intake wiring" "pass" "$wired feedback-source credential(s) set"
    fi
  fi
fi

# Anti-slop ramp expiry (gap-audit G50) — advisory pass must flip to gating after 30 days
wirein=.claude/state/anti-slop-wirein.date
if [ -f "$wirein" ] && [ -f .github/workflows/pr-review.yml ]; then
  wd=$(head -1 "$wirein" | tr -d ' ')
  cutoff30=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d 2>/dev/null)
  if [ -n "$wd" ] && [ "$wd" \< "$cutoff30" ]; then
    if grep -q 'continue-on-error: true' .github/workflows/pr-review.yml; then
      add_result "anti-slop ramp (30d)" "warn" "wired in $wd (>30d ago) but pr-review.yml is still advisory — remove continue-on-error to make it gating, and add the job to the ruleset"
    else
      add_result "anti-slop ramp (30d)" "pass" "ramp complete; pass is gating"
    fi
  else
    add_result "anti-slop ramp (30d)" "pass" "within 30-day calibration window (since $wd)"
  fi
else
  add_result "anti-slop ramp (30d)" "warn" "no .claude/state/anti-slop-wirein.date — ramp clock unrecorded (gap-audit G50)"
fi

printf ']\n' >> "$result_file"

if [ "$JSON_MODE" -eq 1 ]; then
  cat "$result_file"
else
  fail_count=$(jq '[.[] | select(.status=="fail")] | length' "$result_file" 2>/dev/null || echo 0)
  total=$(jq 'length' "$result_file" 2>/dev/null || echo 0)
  printf '\n%s check(s), %s failure(s)\n' "$total" "$fail_count"
  [ "${fail_count:-0}" -gt 0 ] && exit 1
fi
