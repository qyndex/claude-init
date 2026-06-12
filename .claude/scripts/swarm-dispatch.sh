#!/usr/bin/env bash
# Backs /swarm:dispatch — actually parses args and spawns native --bg sessions.
# Idempotent: skips streams already marked `running` in fleet.json.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=lib/atomic-write.sh
. "$ROOT/.claude/scripts/lib/atomic-write.sh"

DRY_RUN=0
ONLY=""
BUDGET=5
MAX_TURNS=200
MAX_STREAMS="${CLAUDE_SWARM_MAX_STREAMS:-10}"   # Round 5 D8: hard ceiling

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --max-streams) MAX_STREAMS="$2"; shift 2 ;;
    --) shift; break ;;
    *)
      echo "swarm-dispatch: unknown arg '$1'" >&2
      exit 2
      ;;
  esac
done

# Round 5 D8: bound total spend = $BUDGET × $MAX_STREAMS against monthly cap.
# Reads cost-summary.json; refuses if projected swarm spend would push over cap.
SUMMARY_FILE="$ROOT/.claude/hooks/.log/cost-summary.json"
if [ -f "$SUMMARY_FILE" ] && command -v jq >/dev/null; then
  total=$(jq -r '.total_usd // 0' "$SUMMARY_FILE")
  cap=$(jq -r '.monthly_cap_usd // 500' "$SUMMARY_FILE")
  remaining=$(awk "BEGIN{print ($cap - $total)}")
  worst_case=$(awk "BEGIN{print ($BUDGET * $MAX_STREAMS)}")
  if awk "BEGIN{exit !($worst_case > $remaining)}"; then
    echo "swarm-dispatch: refusing — worst-case swarm spend \$${worst_case} > remaining \$${remaining} (cap \$${cap}, current \$${total})"
    echo "  Reduce --budget or --max-streams, or raise CLAUDE_MONTHLY_CAP_USD"
    exit 1
  fi
fi

# Pre-flight
if ! command -v claude >/dev/null 2>&1; then
  echo "claude CLI not found"; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq required"; exit 1
fi
if ! bash .claude/scripts/validate.sh >/dev/null 2>&1; then
  echo "validate.sh failed — fix harness state before dispatching"; exit 1
fi
# JUSTIFIED: git stderr suppressed — outside a repo status yields empty, treated as "nothing to commit" and dispatch proceeds
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "git status not clean — commit or stash before dispatching"
  exit 1
fi
if [ ! -s .swarms/coordinator/fleet.json ]; then
  replace_atomic .swarms/coordinator/fleet.json \
    '{"_doc":"reset on first dispatch","_schema_version":1,"last_updated":null,"fleet":{}}'
fi

# Build the candidate list — all stream dirs with a brief.md
candidates=()
for dir in .swarms/streams/*/; do
  [ -d "$dir" ] || continue
  stream=$(basename "$dir")
  [ -s "$dir/brief.md" ] || continue
  candidates+=( "$stream" )
done

# Apply --only filter
if [ -n "$ONLY" ]; then
  IFS=',' read -r -a filter <<< "$ONLY"
  filtered=()
  for c in "${candidates[@]}"; do
    for f in "${filter[@]}"; do
      if [ "$c" = "$f" ]; then filtered+=( "$c" ); break; fi
    done
  done
  candidates=( "${filtered[@]}" )
fi

# Skip already-running streams
to_dispatch=()
for c in "${candidates[@]}"; do
  status=$(jq -r --arg id "$c" '.fleet[$id].status // "none"' .swarms/coordinator/fleet.json)
  if [ "$status" = "running" ] || [ "$status" = "respawned" ]; then
    echo "  • skip $c (already $status)"
    continue
  fi
  to_dispatch+=( "$c" )
done

if [ ${#to_dispatch[@]} -eq 0 ]; then
  echo "Nothing to dispatch."
  exit 0
fi

# Round 5 D8: hard ceiling on stream count
if [ "${#to_dispatch[@]}" -gt "$MAX_STREAMS" ]; then
  echo "swarm-dispatch: ${#to_dispatch[@]} candidates exceed MAX_STREAMS=$MAX_STREAMS"
  echo "  Either: --max-streams N (raise ceiling) or --only stream1,stream2 (subset)"
  exit 1
fi

# Dry-run mode
if [ "$DRY_RUN" = "1" ]; then
  printf 'Dry-run: would dispatch %d streams (budget=$%s, max-turns=%s):\n' \
    "${#to_dispatch[@]}" "$BUDGET" "$MAX_TURNS"
  for s in "${to_dispatch[@]}"; do
    printf '  - %s  (brief: .swarms/streams/%s/brief.md)\n' "$s" "$s"
  done
  exit 0
fi

# Actually dispatch
printf 'Dispatching %d streams (budget=$%s, max-turns=%s)...\n\n' \
  "${#to_dispatch[@]}" "$BUDGET" "$MAX_TURNS"

# Round 6 F: rate-limit-aware stagger between spawns. A tight loop of 10
# `claude --bg` invocations slams the org's per-minute API quota and produces
# 429 storms. Stagger ladder: 0s (first), 5s, 15s, 45s, 90s ... cap at 90s.
stagger_delay() {
  local idx="$1"
  case "$idx" in
    0|1) echo 0 ;;
    2) echo 5 ;;
    3) echo 15 ;;
    4|5) echo 45 ;;
    *) echo 90 ;;
  esac
}

idx=0
for s in "${to_dispatch[@]}"; do
  delay=$(stagger_delay "$idx")
  idx=$((idx + 1))
  if [ "$delay" -gt 0 ]; then
    printf '  ⏸  waiting %ds (rate-limit stagger) ... ' "$delay"
    sleep "$delay"
    printf 'go\n'
  fi
  printf '  → %s ... ' "$s"

  # Round 6 A: propagate OTEL trace context so swarm streams nest under the
  # coordinator's Langfuse trace. The coordinator writes its current traceparent
  # to .swarms/coordinator/.traceparent before invoking dispatch.
  traceparent=""
  if [ -f .swarms/coordinator/.traceparent ]; then
    traceparent=$(cat .swarms/coordinator/.traceparent)
  fi

  sid=$(TRACEPARENT="$traceparent" claude --bg \
       -n "$s" \
       -w "$s" \
       --agent feature-stream \
       --append-system-prompt-file ".swarms/streams/$s/brief.md" \
       --max-turns "$MAX_TURNS" \
       --max-budget-usd "$BUDGET" \
       --output-format stream-json \
       `# JUSTIFIED: claude --bg stderr suppressed — a failed spawn yields empty session_id, caught by the [ -z "$sid" ] guard below` \
       -p "Begin stream $s. Read .swarms/streams/$s/brief.md and execute." 2>/dev/null | jq -r '.session_id // empty' | head -1)

  if [ -z "$sid" ]; then
    printf 'FAILED\n'
    continue
  fi

  # e2e-audit swarm-1: the stream session runs INSIDE the worktree, where the
  # main checkout's .swarms/streams/<s>/ files don't exist. Copy the briefing
  # artifacts in (the prompt cites them by relative path). The worktree is
  # created by `claude --bg -w` above — wait briefly for it to appear.
  wt=".claude/worktrees/$s"
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    [ -d "$wt" ] && break
    sleep 0.5
  done
  if [ -d "$wt" ]; then
    mkdir -p "$wt/.swarms/streams/$s"
    for art in brief.md analysis.md task.json; do
      [ -f ".swarms/streams/$s/$art" ] && cp ".swarms/streams/$s/$art" "$wt/.swarms/streams/$s/$art"
    done
  else
    echo "$(date -Iseconds) $s     WARN worktree $wt not found — briefing artifacts not copied" >> .swarms/coordinator/decisions.log
  fi

  # Update fleet.json atomically
  jq --arg id "$s" --arg sid "$sid" \
     '.fleet[$id] = {sessionId: $sid, status: "running", spawned: (now|todate), worktree: (".claude/worktrees/" + $id), branch: $id}
      | .last_updated = (now|todate)' \
     .swarms/coordinator/fleet.json > .swarms/coordinator/fleet.json.tmp \
     && mv .swarms/coordinator/fleet.json.tmp .swarms/coordinator/fleet.json

  printf 'session %s\n' "${sid:0:12}"
  echo "$(date -Iseconds) $s     Dispatched (session $sid)" >> .swarms/coordinator/decisions.log
done

echo
echo "Done. Monitor with: /swarm:status   (or: claude agents --json)"
