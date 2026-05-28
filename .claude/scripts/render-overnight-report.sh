#!/usr/bin/env bash
# Render OVERNIGHT_REPORT.md from the template + run state. Called at the END
# of an autopilot run, OR manually if the agent crashed before writing the report.
#
# Hydrates {{ PLACEHOLDERS }} from:
#   - .swarms/coordinator/fleet.json (run metadata, shipped/escalated counts)
#   - tasks/TASKS.md (status of each task)
#   - .swarms/streams/*/handoff-final-*.md (per-stream summaries)
#   - .claude/memory/.cache/.dream-state.json (dream timestamp)
#   - .claude/hooks/.log/usage.jsonl (tokens/cost via ccusage if available)
#
# Usage:
#   bash .claude/scripts/render-overnight-report.sh [output-path]
#
# Default output: ./OVERNIGHT_REPORT.md

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OUTPUT="${1:-OVERNIGHT_REPORT.md}"
TEMPLATE=".claude/templates/overnight-report.md"
TS=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
DATE=$(date +%Y-%m-%d)
TZ_NAME=$(date +%Z)

if [ ! -f "$TEMPLATE" ]; then
  echo "Template missing: $TEMPLATE"
  exit 1
fi

# Run metadata from fleet.json if present
if [ -f .swarms/coordinator/fleet.json ]; then
  RUN_ID=$(jq -r '.last_updated // "manual-render"' .swarms/coordinator/fleet.json)
  shipped=$(jq -r '[.fleet[] | select(.status == "merged" or .status == "completed")] | length' .swarms/coordinator/fleet.json)
  escalated=$(jq -r '[.fleet[] | select(.status == "escalated" or .status == "stopped" or .status == "blocked")] | length' .swarms/coordinator/fleet.json)
  total_streams=$(jq -r '.fleet | length' .swarms/coordinator/fleet.json)
else
  RUN_ID="solo-$DATE"
  shipped=0; escalated=0; total_streams=0
fi

# Token cost via ccusage if installed
TOKENS="unknown"
USD="unknown"
if command -v npx >/dev/null 2>&1; then
  usage=$(npx --no-install ccusage blocks --json 2>/dev/null | tail -1)
  if [ -n "$usage" ]; then
    TOKENS=$(printf '%s' "$usage" | jq -r '.total_tokens // "unknown"' 2>/dev/null || echo "unknown")
    USD=$(printf '%s' "$usage" | jq -r '.total_cost_usd // "unknown"' 2>/dev/null || echo "unknown")
  fi
fi

# Dream state
DREAM_TIME="not run"
if [ -f .claude/memory/.cache/.dream-state.json ]; then
  DREAM_TIME=$(jq -r '.last_run_epoch // 0 | strftime("%Y-%m-%dT%H:%M:%SZ")' .claude/memory/.cache/.dream-state.json 2>/dev/null || echo "not run")
fi

ONE_LINER="$shipped feature(s) shipped, $escalated escalated, of $total_streams total stream(s). See PRs and per-stream handoffs below."

# Render the template with sed replacements. The template's {{ KEYS }} get
# replaced; unfilled placeholders are intentionally left for the agent to
# complete when running through autopilot Phase 5.
sed \
  -e "s|{{ DATE }}|$DATE|g" \
  -e "s|{{ START_TIME }}|see fleet.json|g" \
  -e "s|{{ END_TIME }}|$TS|g" \
  -e "s|{{ TIMEZONE }}|$TZ_NAME|g" \
  -e "s|{{ DURATION }}|see fleet.json|g" \
  -e "s|{{ TOKENS }}|$TOKENS|g" \
  -e "s|{{ USD }}|$USD|g" \
  -e "s|{{ MODEL }}|claude-opus-4-7|g" \
  -e "s|{{ FALLBACK }}|claude-sonnet-4-6|g" \
  -e "s|{{ RUN_ID }}|$RUN_ID|g" \
  -e "s|{{ ONE_LINER }}|$ONE_LINER|g" \
  -e "s|{{ DREAM_TIME }}|$DREAM_TIME|g" \
  "$TEMPLATE" > "$OUTPUT"

# Append per-stream sections from handoff-final-*.md if any
{
  echo
  echo "---"
  echo
  echo "## Per-stream handoffs (auto-appended)"
  echo
  for handoff in $(ls -t .swarms/streams/*/handoff-final-*.md 2>/dev/null); do
    echo "### $(basename "$(dirname "$handoff")")"
    echo
    cat "$handoff"
    echo
    echo "---"
    echo
  done
} >> "$OUTPUT"

echo "Rendered $OUTPUT"
echo "Note: remaining {{ }} placeholders should be filled by the autopilot agent during Phase 5."
echo "If running manually post-crash, hand-edit or run /lesson-learned to capture context."
