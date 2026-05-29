#!/usr/bin/env bash
# Session heartbeat — UserPromptSubmit hook (Round 6 B).
#
# Writes .claude/memory/.cache/current-session.json every turn so that if the
# session is killed (SIGKILL, terminal close, network drop), the NEXT session-start
# can detect "previous session crashed" and recover.
#
# session-end.sh is the GRACEFUL counterpart — it deletes this file at clean exit.
# So the file's PRESENCE at session-start = "previous session was killed".
#
# Cost: ~5ms per turn. Free heartbeat.

set -uo pipefail

mkdir -p .claude/memory/.cache
state_file=".claude/memory/.cache/current-session.json"
tmp="${state_file}.tmp"

# CLAUDE_SESSION_ID is set by Claude Code in hook env (if available).
# Fall back to PPID-based marker for older versions.
session_id="${CLAUDE_SESSION_ID:-pid-$PPID}"

# ─── Spec 001 AC-18: workspace-fingerprinted session namespace ───────────
# Two parallel worktree sessions share .claude/memory/.cache/ — their session
# files collide. Derive a stable 16-char fingerprint from the resolved cwd and
# namespace per-workspace writes under .claude/sessions/<fp>/ so concurrent
# worktrees never clobber each other. Portable: prefer md5sum (GNU), fall back
# to md5 (BSD/macOS).
workspace_path="$(pwd -P)"
if command -v md5sum >/dev/null 2>&1; then
  WORKSPACE_FP="$(printf '%s' "$workspace_path" | md5sum | cut -c1-16)"
elif command -v md5 >/dev/null 2>&1; then
  WORKSPACE_FP="$(printf '%s' "$workspace_path" | md5 | cut -c1-16)"
else
  # Last-resort fallback: cksum is in POSIX. Not cryptographic, but a stable
  # per-path token is all we need for namespacing.
  WORKSPACE_FP="$(printf '%s' "$workspace_path" | cksum | cut -d' ' -f1)"
fi
session_dir=".claude/sessions/${WORKSPACE_FP}"
mkdir -p "$session_dir"

# Read previous state to compute turn count
prev_turn=0
prev_started_at=""
if [ -f "$state_file" ]; then
  # JUSTIFIED: jq error muted + fallback — a partially-written heartbeat file yields 0, correctly restarting the turn counter rather than crashing the per-turn hook
  prev_turn=$(jq -r '.turn_count // 0' "$state_file" 2>/dev/null || echo 0)
  # JUSTIFIED: jq error muted + empty fallback — a corrupt file yields empty start time, recomputed fresh below; never fatal to the hook
  prev_started_at=$(jq -r '.started_at // ""' "$state_file" 2>/dev/null || echo "")
  # JUSTIFIED: jq error muted + empty fallback — empty session id forces the "new session" branch below, the safe default on a corrupt file
  prev_session=$(jq -r '.session_id // ""' "$state_file" 2>/dev/null || echo "")
  # If session_id changed, treat as new session
  if [ "$prev_session" != "$session_id" ]; then
    prev_turn=0
    prev_started_at=""
  fi
fi

turn=$((prev_turn + 1))
now_iso=$(date -Iseconds)
started_at="${prev_started_at:-$now_iso}"

branch="unknown"
cwd_val="$(pwd)"
uncommitted=0
if git rev-parse --git-dir >/dev/null 2>&1; then
  # JUSTIFIED: git error muted — a detached HEAD has no symbolic ref; "detached" is the intended recorded value
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  # JUSTIFIED: git error muted — inside the rev-parse success branch; any residual noise just yields a 0 uncommitted count for the heartbeat
  uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
fi

# Atomic write
heartbeat_json=$(jq -nc \
  --arg session_id "$session_id" \
  --arg pid "$PPID" \
  --arg started_at "$started_at" \
  --arg last_heartbeat_at "$now_iso" \
  --arg branch "$branch" \
  --arg cwd "$cwd_val" \
  --argjson turn_count "$turn" \
  --argjson uncommitted "$uncommitted" \
  '{
    session_id: $session_id,
    pid: ($pid | tonumber),
    started_at: $started_at,
    last_heartbeat_at: $last_heartbeat_at,
    branch: $branch,
    cwd: $cwd,
    turn_count: $turn_count,
    uncommitted: $uncommitted
  }')
# JUSTIFIED: write + mv errors muted — the heartbeat is a per-turn side effect; a transient write failure must never block the prompt, and the next turn simply re-writes it
printf '%s\n' "$heartbeat_json" > "$tmp" 2>/dev/null && mv "$tmp" "$state_file" 2>/dev/null

# Workspace-namespaced mirror — concurrent worktree sessions write here without
# colliding (AC-18). The legacy current-session.json above is retained for the
# session-start/session-end crash-recovery contract.
# JUSTIFIED: cp error muted — the fingerprinted mirror is best-effort; a write failure must never block the user's prompt
cp "$state_file" "${session_dir}/current-session.json" 2>/dev/null || true

# ─── Spec 001 AC-16: worker state machine for swarm streams ──────────────
# Inside a swarm stream (worktree branch feat-<N>) advance the stream's
# state file at .swarms/streams/<id>/state.json. The full lifecycle is:
#   spawning → trust_required → ready_for_prompt → prompt_accepted →
#   running → finished | failed
# The coordinator sets the early states at spawn and gates prompt dispatch on
# ready_for_prompt; once prompts are flowing the heartbeat marks `running`.
# JUSTIFIED: grep || true — a non-feat branch yields an empty stream_id, which the guard below treats as "not a swarm stream" and skips emission (grep exit 1 is expected, not an error)
stream_id="$(printf '%s' "$branch" | grep -oE '^feat-[a-z0-9-]+' || true)"
if [ -n "$stream_id" ]; then
  stream_state_dir=".swarms/streams/${stream_id}"
  mkdir -p "$stream_state_dir"
  stream_state="${stream_state_dir}/state.json"
  stream_tmp="${stream_state}.tmp"
  # Don't regress an already-terminal stream; otherwise mark running.
  worker_state="running"
  if [ -f "$stream_state" ]; then
    # JUSTIFIED: jq error muted + fallback — a partial state.json yields empty, treated as non-terminal (running), the safe default
    prev_state="$(jq -r '.state // ""' "$stream_state" 2>/dev/null || echo "")"
    case "$prev_state" in
      finished|failed) worker_state="$prev_state" ;;
    esac
  fi
  stream_json=$(jq -nc \
    --arg stream_id "$stream_id" \
    --arg state "$worker_state" \
    --arg session_id "$session_id" \
    --arg updated "$now_iso" \
    '{
      stream_id: $stream_id,
      state: $state,
      session_id: $session_id,
      updated: $updated,
      states: ["spawning","trust_required","ready_for_prompt","prompt_accepted","running","finished","failed"]
    }')
  # JUSTIFIED: write + mv errors muted — stream state is a per-turn side effect; a transient write failure must never block the prompt, and the next turn re-writes it
  printf '%s\n' "$stream_json" > "$stream_tmp" 2>/dev/null && mv "$stream_tmp" "$stream_state" 2>/dev/null

  # ─── Spec 002 AC-12: harness-version drift detection ──────────────────────
  # An in-flight feature-stream may be running an OLD snapshot of .claude/ while
  # main has moved on. Compare the local .claude/ tree SHA against origin/main's
  # and, on drift beyond DRIFT_THRESHOLD commits, emit a harness.version.drift
  # lane event so the coordinator can decide whether to refresh the stream.
  # Cached 5 min per workspace so we don't re-fetch on every turn.
  drift_threshold="${HARNESS_DRIFT_THRESHOLD:-10}"
  drift_cache="${session_dir}/.harness-sha.cache"
  cache_fresh=0
  if [ -f "$drift_cache" ]; then
    # JUSTIFIED: stat error muted + 0 fallback — a missing/odd mtime forces a refresh, the safe default
    cache_mtime=$(stat -f %m "$drift_cache" 2>/dev/null || stat -c %Y "$drift_cache" 2>/dev/null || echo 0)
    if [ $(( $(date +%s) - cache_mtime )) -lt 300 ]; then
      cache_fresh=1
    fi
  fi
  if [ "$cache_fresh" -eq 0 ]; then
    # JUSTIFIED: git errors muted — drift detection is best-effort telemetry; a fetch failure (offline) must never block the prompt, we simply skip this turn's check
    git fetch --quiet origin main 2>/dev/null || true
    local_sha="$(git rev-parse HEAD:.claude 2>/dev/null || echo "")"
    main_sha="$(git rev-parse origin/main:.claude 2>/dev/null || echo "")"
    if [ -n "$local_sha" ] && [ -n "$main_sha" ] && [ "$local_sha" != "$main_sha" ]; then
      # Count commits on origin/main touching .claude/ since our merge-base.
      base="$(git merge-base HEAD origin/main 2>/dev/null || echo "")"
      drift_count=0
      if [ -n "$base" ]; then
        drift_count="$(git rev-list --count "${base}..origin/main" -- .claude 2>/dev/null || echo 0)"
      fi
      if [ "$drift_count" -gt "$drift_threshold" ]; then
        mkdir -p .swarms/events
        events_file=".swarms/events/${stream_id}.jsonl"
        drift_event=$(jq -nc \
          --arg ts "$now_iso" \
          --arg stream_id "$stream_id" \
          --arg local_sha "$local_sha" \
          --arg main_sha "$main_sha" \
          --argjson drift_count "$drift_count" \
          '{ts:$ts, stream_id:$stream_id, event:"harness.version.drift", payload:{local_sha:$local_sha, main_sha:$main_sha, drift_count:$drift_count}}')
        # JUSTIFIED: append error muted — lane events are append-only telemetry; a write failure must never block the prompt
        printf '%s\n' "$drift_event" >> "$events_file" 2>/dev/null || true
      fi
    fi
    # JUSTIFIED: touch error muted — the cache is a best-effort 5-min throttle; failure just means we re-check next turn
    : > "$drift_cache" 2>/dev/null || true
  fi
fi

# This hook does not emit additionalContext — it's purely a side effect.
exit 0
