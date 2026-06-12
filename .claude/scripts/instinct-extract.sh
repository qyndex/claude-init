#!/usr/bin/env bash
# Instinct extraction — gap-audit G25 (the dead middle stage of the
# continuous-learning pipeline). Observations accumulated for months with no
# consumer; this script is the consumer.
#
#   observations (.claude/memory/.cache/instincts/observations.jsonl, written
#   by instinct-observer.sh)  →  THIS SCRIPT (Haiku claude -p)  →
#   .claude/memory/instincts/active.yml  →  read by session-start-context.sh
#   + skill-router.sh (G31) + dream step 4 + skill-creator promotion.
#
# Triggers:
#   - auto-dream-check.sh (Stop hook) calls this on every fire; it self-gates
#     on ≥ INSTINCT_EXTRACT_MIN new observations (default 50)
#   - dream skill step 4a calls it with --force
#   - manual: bash .claude/scripts/instinct-extract.sh --force
#
# DRY_RUN=1 prints the spawn prompt instead of spawning (used by tests).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OBS=".claude/memory/.cache/instincts/observations.jsonl"
STATE=".claude/memory/.cache/.instinct-extract.state"
ACTIVE=".claude/memory/instincts/active.yml"
MIN="${INSTINCT_EXTRACT_MIN:-50}"
MODEL="${INSTINCT_MODEL:-claude-haiku-4-5}"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

[ -s "$OBS" ] || exit 0

total=$(wc -l < "$OBS" | tr -d ' ')
# JUSTIFIED: missing state file means nothing extracted yet — offset 0 is correct
last=$(cat "$STATE" 2>/dev/null || echo 0)
case "$last" in (*[!0-9]*|'') last=0 ;; esac
new=$(( total - last ))

if [ "$new" -lt "$MIN" ] && [ "$FORCE" -ne 1 ]; then
  exit 0
fi
[ "$new" -le 0 ] && exit 0

mkdir -p .claude/memory/instincts .claude/hooks/.log

# Slice the unprocessed observations (cap 2000 lines per pass)
slice=$(mktemp)
tail -n +"$(( last + 1 ))" "$OBS" | head -2000 > "$slice"
processed=$(wc -l < "$slice" | tr -d ' ')

prompt="You are the instinct extractor (deterministic background task, no conversation).
Read the observation lines in ${slice} (JSONL: tool/cmd/exit/err/file events from recent sessions).
Identify repeated patterns: the same kind of failure followed by the same kind of fix, recurring command sequences with consistent outcomes, repeated error classes.
Then merge into ${ACTIVE} (create it if absent), YAML list of entries with fields: id (kebab-slug), trigger (when this applies), action (what to do), confidence (0.3-0.9), domain, status: project, created (ISO date), reinforced (count), last_seen (ISO date).
Rules: max 5 NEW instincts per pass; if an observed pattern matches an existing entry, increment its reinforced and update last_seen instead of duplicating; keep the file under 50 entries (drop lowest-confidence first); confidence <0.5 means advisory. Write ONLY ${ACTIVE}. Do not touch any other file."

if [ "${DRY_RUN:-0}" = "1" ]; then
  printf '%s\n' "$prompt"
  echo "$total" > "$STATE"
  rm -f "$slice"
  exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
  rm -f "$slice"
  exit 0
fi

log=".claude/hooks/.log/instinct-extract-$(date +%Y%m%d-%H%M%S).log"
if claude -p --bare --model "$MODEL" "$prompt" > "$log" 2>&1; then
  echo "$total" > "$STATE"
  echo "[$(date -Iseconds)] extracted from $processed observations (offset $last → $total)" >> .claude/hooks/.log/instinct.log
else
  echo "[$(date -Iseconds)] EXTRACTION FAILED — see $log" >> .claude/hooks/.log/instinct.log
fi
rm -f "$slice"
exit 0
