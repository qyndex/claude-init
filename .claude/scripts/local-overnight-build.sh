#!/usr/bin/env bash
# Local-machine fallback for when Cloud Routines is unavailable
# (Anthropic outage, expired auth, plan downgrade).
#
# Triggers the same overnight build flow that overnight-build.yml describes,
# but via `claude --bg` on the local machine. Logs go to .claude/hooks/.log/.
#
# Designed for nightly cron:
#   0 23 * * *  bash /path/to/repo/.claude/scripts/local-overnight-build.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

LOG_DIR=".claude/hooks/.log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/local-overnight-$(date +%Y%m%d-%H%M%S).log"

step() { printf '%s → %s\n' "$(date -Iseconds)" "$*" | tee -a "$LOG_FILE" ; }

step "Local overnight build starting"

# ─── Double-run guard (Round 13 Fix 2) ──────────────────────────────────
# The old guard only checked OVERNIGHT_REPORT.md mtime, but the report is written at
# the END of a run — so a backstop firing at 23:30 while the Cloud Routine is mid-run
# saw a ~24h-old report and started a SECOND concurrent build on the same branch.
# Three independent signals now, cheapest first:
#   (1) a fresh LOCAL run-lock  — a manual run + cron, or a cron re-fire (same host)
#   (2) the dated REMOTE branch — the Cloud Routine already running (cross-host signal)
#   (3) a <60-min OVERNIGHT_REPORT.md — a cloud run that just finished
today=$(date +%Y-%m-%d)
branch="claude/overnight-$today"
RUN_LOCK=".claude/state/overnight-$today.run"
mkdir -p .claude/state

_age_min() {  # whole minutes since file $1 was modified; 999999 if absent
  local m
  [ -f "$1" ] || { echo 999999; return; }
  # JUSTIFIED: BSD/GNU stat portability — BSD form tried first, GNU form is the fallback; the trailing 0 sentinel only triggers if both fail, yielding a huge age that reads as "stale"
  m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)
  echo $(( ($(date +%s) - m) / 60 ))
}

# (1) Local run-lock — fresh (<6h) + holder alive means a local build is underway.
if [ -f "$RUN_LOCK" ]; then
  # JUSTIFIED: reading the pid out of the lock guarded by the enclosing [ -f ]; the redirect tolerates a malformed lock — an empty pid falls through to the liveness check below
  lock_pid=$(awk -F= '/^pid=/{print $2}' "$RUN_LOCK" 2>/dev/null)
  # JUSTIFIED: kill -0 is a liveness probe, not a signal; the redirect hides "no such process" — a dead holder means non-zero, so we reclaim the stale lock rather than exit
  if [ "$(_age_min "$RUN_LOCK")" -lt 360 ] && { [ -z "$lock_pid" ] || kill -0 "$lock_pid" 2>/dev/null; }; then
    step "A local overnight run is already active tonight (lock $RUN_LOCK, pid ${lock_pid:-?}). Backstop exits."
    exit 0
  fi
  step "Stale overnight run-lock (age $(_age_min "$RUN_LOCK")m, pid ${lock_pid:-?} gone) — reclaiming."
fi

# (2) Remote branch — the Cloud Routine drops a run-start marker branch and pushes
# per-task branches, all prefixed claude/overnight-<date>. A prefix match (not exact)
# detects either. --exit-code returns non-zero when nothing matches.
if git ls-remote --exit-code --heads origin "claude/overnight-${today}*" >/dev/null 2>&1; then
  step "Cloud Routine already created a 'claude/overnight-${today}*' branch tonight. Backstop exits silently."
  exit 0
fi

# (3) Fresh report — a cloud run that finished within the last hour.
if [ "$(_age_min OVERNIGHT_REPORT.md)" -lt 60 ]; then
  step "OVERNIGHT_REPORT.md is $(_age_min OVERNIGHT_REPORT.md)m old — cloud run just finished. Backstop exits silently."
  exit 0
fi


# Pre-flight
if ! command -v claude >/dev/null 2>&1; then
  step "claude CLI not found — abort"; exit 1
fi
# JUSTIFIED: cleanliness probe — the redirect tolerates running outside a git repo; empty output there reads as "clean" and the build proceeds, matching the dirty-tree guard's intent
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  step "git tree dirty — abort (commit/stash before nightly)"; exit 1
fi

# Claim tonight's run now that pre-flight passed; release the lock on ANY exit so a
# crash doesn't wedge future nights ($branch/$RUN_LOCK were computed in the guard).
printf 'pid=%s\nstarted=%s\n' "$$" "$(date -Iseconds)" > "$RUN_LOCK"
trap 'rm -f "'"$RUN_LOCK"'"' EXIT

# Create a dated branch we can push to
step "Creating branch $branch"
# JUSTIFIED: create-or-checkout idiom — the redirect hides the "branch already exists" error so the `||` switches to the existing dated branch on a re-fire
git switch -c "$branch" 2>/dev/null || git switch "$branch"

# Prompt body — same intent as routines/overnight-build.yml
PROMPT=$(cat <<'BUILDPROMPT'
You are running an unattended LOCAL overnight build (Cloud Routine fallback).

Same process as the Cloud Routine:
1. Read tasks/TASKS.md. Identify unblocked tasks.
2. Invoke .claude/skills/verify-loop/SKILL.md.
3. Execute autopilot 5-phase per task with strict TDD.
4. After each task, commit and continue.
5. Stop at 04:30 wall clock OR no unblocked tasks OR 3 consecutive ESCALATIONs.
6. At end: invoke /dream, then bash .claude/scripts/render-overnight-report.sh.

EVIDENCE GATE per task: accept: exits 0, verify.sh exits 0, UI screenshots (if applicable), semgrep + codeql clean (if applicable).

CHECKPOINT: use .claude/skills/wip-checkpoint every 5-15 min.

PERMISSION MODE: Auto Mode (this CLI was invoked with --auto). Hooks still fire first.

BRANCH: only push to claude/overnight-* branches.

END: write OVERNIGHT_REPORT.md, exit cleanly.
BUILDPROMPT
)

# Spawn background session with Auto Mode and explicit budgets
step "Spawning background session..."
sid=$(claude --bg \
     -n "local-overnight-$(date +%Y%m%d)" \
     --auto \
     --max-turns 600 \
     --max-budget-usd 30 \
     --output-format stream-json \
     -p "$PROMPT" 2>>"$LOG_FILE" | jq -r '.session_id // empty' | head -1)

if [ -z "$sid" ]; then
  step "Failed to spawn — see $LOG_FILE"; exit 1
fi

step "Spawned: session $sid (background)"
step "Monitor with: claude attach $sid   OR   claude logs $sid --follow"
step "Log: $LOG_FILE"

exit 0
