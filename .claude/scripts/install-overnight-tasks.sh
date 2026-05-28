#!/usr/bin/env bash
# Installs the local Desktop scheduled tasks (dream-cron + optional overnight-build-local fallback).
# For Cloud Routines, configure manually at claude.ai/code/routines using .claude/routines/overnight-build.yml as a template.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

step() { printf '\n→ %s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; }

if ! command -v claude >/dev/null 2>&1; then
  echo "Claude Code CLI not found."
  exit 1
fi

step "Installing dream-cron (local, daily 03:00)"
# The trigger script lives at .claude/skills/dream-trigger.sh and is invoked by
# the local scheduled task. We pass the full bash path so the task fires the
# script even if the user's shell doesn't auto-detect the project root.
DREAM_SCRIPT="$ROOT/.claude/skills/dream-trigger.sh"
if [ ! -x "$DREAM_SCRIPT" ]; then
  warn "dream-trigger.sh missing or not executable at $DREAM_SCRIPT — fix before relying on the cron"
fi

claude -p --bare "Create a scheduled task named 'dream-cron' with cron '0 3 * * *' timezone 'local' that runs: bash $DREAM_SCRIPT. Use the prompt from .claude/routines/dream-cron.yml." 2>/dev/null \
  && ok "dream-cron registered" \
  || warn "dream-cron registration may have failed — verify via 'claude' then '/tasks list'"

step "Installing local-overnight-build (fallback for Cloud Routine outage)"
# The Round 4 audit caught that local-overnight-build.sh existed but was never wired.
# Wire it as a backstop scheduled task at 23:30 (30 min AFTER Cloud Routine to avoid duplicate runs).
LOCAL_BUILD_SCRIPT="$ROOT/.claude/scripts/local-overnight-build.sh"
if [ ! -x "$LOCAL_BUILD_SCRIPT" ]; then
  warn "local-overnight-build.sh missing or not executable at $LOCAL_BUILD_SCRIPT"
fi

# Only fire if the Cloud Routine missed (check OVERNIGHT_REPORT.md mtime > 25h before running)
# The local script itself checks and exits silently if Cloud ran first.

if [ "${INSTALL_LOCAL_BUILD_BACKSTOP:-yes}" = "yes" ]; then
  claude -p --bare "Create a scheduled task named 'overnight-build-backstop' with cron '30 23 * * *' timezone 'local' that runs: bash $LOCAL_BUILD_SCRIPT. The script self-checks if Cloud Routine already ran and exits silently if so." 2>/dev/null \
    && ok "overnight-build-backstop registered (fires 23:30 only if Cloud routine missed)" \
    || warn "backstop registration may have failed — verify via 'claude' then '/tasks list'"
else
  warn "INSTALL_LOCAL_BUILD_BACKSTOP=no — skipping local backstop. Cloud Routine outage = silent overnight skip."
fi

step "Installing cost-report (daily aggregator)"
COST_SCRIPT="$ROOT/.claude/scripts/cost-report.sh"
claude -p --bare "Create a scheduled task named 'cost-report' with cron '0 6 * * *' timezone 'local' that runs: bash $COST_SCRIPT month. Writes to .claude/hooks/.log/cost-summary.json. Read by pre-spawn-cost-gate hook." 2>/dev/null \
  && ok "cost-report registered" \
  || warn "cost-report registration may have failed"

step "Cloud Routine setup (manual)"
cat <<EOF
The 11 PM overnight-build routine MUST be configured manually because Cloud Routines
require a Claude.ai login (not API key) and must be created at:

  https://claude.ai/code/routines

Use .claude/routines/overnight-build.yml as the template — paste each field into the
routine creation form. Confirm:
  - schedule: 0 23 * * * UTC (or your TZ)
  - repo: this repo's GitHub URL
  - permission_mode: auto   (Sonnet 4.6 classifier; no user prompts; hooks fire first)
  - branch_permission: claude/overnight-*
  - connectors: GitHub + Slack (minimum)

After creating, click "Run now" once to verify the run completes successfully.
EOF

step "Done"
