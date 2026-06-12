#!/usr/bin/env bash
# UserPromptSubmit hook — mid-session context-fill + output-growth monitor.
# Gap-audit G9: nothing measured context fill on the model side; the harness
# rode silently from healthy to the 400K auto-compact cliff. This estimates
# fill from transcript size and injects a nudge at 60% / 80% (once each).
# Gap-audit G7: nothing accounted for Claude's own output verbosity mid-session.
# This measures per-turn transcript growth and warns when one turn exceeded
# CONTEXT_MONITOR_DELTA_WARN bytes (default 120000 ≈ 30K tokens).
#
# Estimation is deliberately rough (bytes/4 ≈ tokens; JSONL overhead inflates
# it, summarized history deflates it). It is a nudge, not a gate — exact fill
# lives in the statusline (ctx:%) for the human.

set -uo pipefail

payload=$(cat 2>/dev/null || true)
[ -z "$payload" ] && exit 0

transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
session=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
state_dir="$ROOT/.claude/state/context-monitor"
mkdir -p "$state_dir" 2>/dev/null || exit 0
state_file="$state_dir/${session}.state"

size=$(wc -c < "$transcript" 2>/dev/null | tr -d ' ')
[ -n "$size" ] || exit 0

window="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-400000}"
est_tokens=$(( size / 4 ))
pct=$(( est_tokens * 100 / window ))

last_size=0
last_threshold=0
if [ -f "$state_file" ]; then
  # state format: <last_size> <last_threshold_warned>
  read -r last_size last_threshold < "$state_file" 2>/dev/null || true
fi
last_size=${last_size:-0}; last_threshold=${last_threshold:-0}
printf '%s %s\n' "$size" "$last_threshold" > "$state_file" 2>/dev/null || true

warnings=""

# G9: fill thresholds — warn once per threshold per session
threshold=0
[ "$pct" -ge 60 ] && threshold=60
[ "$pct" -ge 80 ] && threshold=80
if [ "$threshold" -gt "$last_threshold" ]; then
  printf '%s %s\n' "$size" "$threshold" > "$state_file" 2>/dev/null || true
  if [ "$threshold" -ge 80 ]; then
    warnings="[context] est. fill ~${pct}% of ${window}-token auto-compact window. Compaction is close: persist in-flight state now (commit WIP, update tasks/notes), prefer /compact <hint> at a clean boundary over hitting the cliff, delegate any remaining heavy reads to Explore."
  else
    warnings="[context] est. fill ~${pct}% of ${window}-token auto-compact window. Consider /compact <hint> at the next task boundary, delegating heavy reads to Explore, or /context-budget to prune."
  fi
fi

# G7: per-turn output growth — verbose narration/file-echoing accumulates unchecked
delta_warn="${CONTEXT_MONITOR_DELTA_WARN:-120000}"
if [ "$last_size" -gt 0 ]; then
  delta=$(( size - last_size ))
  if [ "$delta" -gt "$delta_warn" ]; then
    growth_note="[output] last turn grew the transcript by ~$(( delta / 4 )) tokens (cap nudge: $(( delta_warn / 4 ))). Don't echo files back — cite path:line; state results, don't narrate (§IX)."
    if [ -n "$warnings" ]; then warnings="$warnings $growth_note"; else warnings="$growth_note"; fi
  fi
fi

[ -z "$warnings" ] && exit 0

jq -nc --arg ctx "$warnings" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
exit 0
