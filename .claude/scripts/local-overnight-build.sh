#!/usr/bin/env bash
# Local-machine fallback for when Cloud Routines is unavailable
# (Anthropic outage, expired auth, plan downgrade).
#
# Triggers the same overnight build flow that overnight-build.yml describes,
# but via a supervised foreground Claude process on the local machine. Logs go to .claude/hooks/.log/.
#
# Designed for nightly cron:
#   0 23 * * *  bash /path/to/repo/.claude/scripts/local-overnight-build.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Hold one inherited OS lock across the complete read/modify/write operation.
STATE_LOCK="$ROOT/.claude/state/overnight-worker.lock"
if ! python3 "$ROOT/.claude/scripts/state-lock.py" --lock "$STATE_LOCK" --check; then
  exec python3 "$ROOT/.claude/scripts/state-lock.py" --lock "$STATE_LOCK" -- bash "$0" "$@"
fi
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
# Three independent signals, checked in this order:
#   (1) inherited OS lock held for the foreground worker lifetime (same host)
#   (2) the dated REMOTE branch — the Cloud Routine already running (cross-host signal)
#   (3) a <60-min OVERNIGHT_REPORT.md — a cloud run that just finished
today=$(date +%Y-%m-%d)
branch="claude/overnight-$today"
mkdir -p .claude/state

_age_min() {  # whole minutes since file $1 was modified; 999999 if absent
  local m
  [ -f "$1" ] || { echo 999999; return; }
  # JUSTIFIED: BSD/GNU stat portability — BSD form tried first, GNU form is the fallback; the trailing 0 sentinel only triggers if both fail, yielding a huge age that reads as "stale"
  m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)
  echo $(( ($(date +%s) - m) / 60 ))
}

# The inherited OS lock above owns the complete foreground worker lifetime.

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

# Keep the supervisor and its inherited OS lock alive until the worker exits.
step "Starting supervised foreground session..."
python3 "$ROOT/.claude/scripts/foreground-watchdog.py" \
  --timeout "${CLAUDE_OVERNIGHT_TIMEOUT_SECONDS:-19800}" -- \
  claude -n "local-overnight-$(date +%Y%m%d)" --auto \
  --max-turns 600 --max-budget-usd 30 --output-format stream-json \
  -p "$PROMPT" >> "$LOG_FILE" 2>&1
worker_rc=$?
step "Foreground worker finished with exit $worker_rc; log: $LOG_FILE"
exit "$worker_rc"
