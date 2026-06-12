#!/usr/bin/env bash
# Installs the local Desktop scheduled tasks (dream-cron + optional overnight-build-local fallback).
# For Cloud Routines, configure manually at claude.ai/code/routines using .claude/routines/overnight-build.yml as a template.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

step() { printf '\n→ %s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; }

# Install record (e2e-audit docs-truth-3): harness-doctor enumerates
# .claude/routines/*.yml against this file and warns per missing routine.
RECORD=".claude/state/routines-installed"
mkdir -p .claude/state
record() { grep -qx "$1" "$RECORD" 2>/dev/null || echo "$1" >> "$RECORD"; }

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

# JUSTIFIED: CLI error output discarded — the exit status still routes to ok/warn below, so a failure is surfaced to the operator, not hidden
claude -p --bare "Create a scheduled task named 'dream-cron' with cron '0 3 * * *' timezone 'local' that runs: bash $DREAM_SCRIPT. Use the prompt from .claude/routines/dream-cron.yml." 2>/dev/null \
  && { ok "dream-cron registered"; record dream-cron; } \
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
  # JUSTIFIED: CLI error output discarded — the exit status still routes to ok/warn below, so a failure is surfaced to the operator, not hidden
  claude -p --bare "Create a scheduled task named 'overnight-build-backstop' with cron '30 23 * * *' timezone 'local' that runs: bash $LOCAL_BUILD_SCRIPT. The script self-checks if Cloud Routine already ran and exits silently if so." 2>/dev/null \
    && { ok "overnight-build-backstop registered (fires 23:30 only if Cloud routine missed)"; record overnight-build-backstop; } \
    || warn "backstop registration may have failed — verify via 'claude' then '/tasks list'"
else
  warn "INSTALL_LOCAL_BUILD_BACKSTOP=no — skipping local backstop. Cloud Routine outage = silent overnight skip."
fi

step "Installing cost-report (daily aggregator)"
COST_SCRIPT="$ROOT/.claude/scripts/cost-report.sh"
# JUSTIFIED: CLI error output discarded — the exit status still routes to ok/warn below, so a failure is surfaced to the operator, not hidden
claude -p --bare "Create a scheduled task named 'cost-report' with cron '0 6 * * *' timezone 'local' that runs: bash $COST_SCRIPT month. Writes to .claude/hooks/.log/cost-summary.json. Read by pre-spawn-cost-gate hook." 2>/dev/null \
  && { ok "cost-report registered"; record cost-report; } \
  || warn "cost-report registration may have failed"

# e2e-audit docs-truth-3: the locally-eligible maintenance routines were authored
# but never installed by anything — the unattended layer (memory GC, OQ aging,
# quarterly archive) silently never fired. Install them here.
step "Installing gc-nightly (local, daily 02:30 — TASKS/verify/log/memory GC)"
# JUSTIFIED: CLI error output discarded — the exit status still routes to ok/warn below, so a failure is surfaced to the operator, not hidden
claude -p --bare "Create a scheduled task named 'gc-nightly' with cron '30 2 * * *' timezone 'local' that runs: cd $ROOT && bash .claude/scripts/gc-tasks.sh && bash .claude/scripts/gc-verify.sh && bash .claude/scripts/gc-logs.sh && bash .claude/scripts/memory-gc.sh enforce. Deterministic, idempotent maintenance per .claude/routines/gc-nightly.yml." 2>/dev/null \
  && { ok "gc-nightly registered"; record gc-nightly; } \
  || warn "gc-nightly registration may have failed — without it TASKS.md/verify/logs/MEMORY.md grow unbounded"

step "Installing oq-aging (local, daily 06:00 — stale [OQ] → RESOLVE tasks)"
# JUSTIFIED: CLI error output discarded — the exit status still routes to ok/warn below, so a failure is surfaced to the operator, not hidden
claude -p --bare "Create a scheduled task named 'oq-aging' with cron '0 6 * * *' timezone 'local' that runs: cd $ROOT && bash .claude/scripts/oq-aging.sh. Per .claude/routines/oq-aging.yml — idempotent, appends RESOLVE tasks for week-old open questions." 2>/dev/null \
  && { ok "oq-aging registered"; record oq-aging; } \
  || warn "oq-aging registration may have failed — OQ-blocked specs will rot silently"

step "Installing quarterly-archive (local, first Mon of Jan/Apr/Jul/Oct 02:00)"
# JUSTIFIED: CLI error output discarded — the exit status still routes to ok/warn below, so a failure is surfaced to the operator, not hidden
claude -p --bare "Create a scheduled task named 'quarterly-archive' with cron '0 2 1-7 1,4,7,10 1' timezone 'local' that runs the quarterly archive routine from .claude/routines/quarterly-archive.yml (spec/plan archival + ADR walk)." 2>/dev/null \
  && { ok "quarterly-archive registered"; record quarterly-archive; } \
  || warn "quarterly-archive registration may have failed"

# e2e-audit docs-truth-3 (continued): these routine YMLs say "Install via:
# install-overnight-tasks.sh" but had no install step — register them generically.
# Format: name|cron|one-line purpose (prompt body lives in the routine yml).
while IFS='|' read -r rname rcron rdesc; do
  step "Installing $rname (local, cron '$rcron')"
  # JUSTIFIED: CLI error output discarded — the exit status still routes to ok/warn below, so a failure is surfaced to the operator, not hidden
  claude -p --bare "Create a scheduled task named '$rname' with cron '$rcron' timezone 'local' that runs: cd $ROOT then follow the prompt in .claude/routines/$rname.yml. Purpose: $rdesc" 2>/dev/null \
    && { ok "$rname registered"; record "$rname"; } \
    || warn "$rname registration may have failed — verify via 'claude' then '/tasks list'"
done <<'ROUTINES'
appetite-circuit-breaker|0 9 * * *|surface initiatives at 50%/100% of declared appetite via appetite-check.sh
atlas-refresh|0 4 * * *|nightly codebase atlas refresh via atlas-refresh.sh
constitution-compact-cron|0 4 1 1,4,7,10 *|quarterly constitution size check; proposes compaction over 300 lines
feedback-triage|0 8 * * 1|weekly deterministic feedback scoring + ranked triage report
ROUTINES

# Network pollers need external credentials (feedback sources / Sentry DSN) —
# opt-in only, so a fresh install doesn't schedule tasks that fail every tick.
if [ "${INSTALL_FEEDBACK_POLL:-no}" = "yes" ]; then
  step "Installing feedback-poll (local, hourly)"
  # JUSTIFIED: CLI error output discarded — the exit status still routes to ok/warn below, so a failure is surfaced to the operator, not hidden
  claude -p --bare "Create a scheduled task named 'feedback-poll' with cron '0 * * * *' timezone 'local' that runs the prompt in .claude/routines/feedback-poll.yml (hourly customer-signal intake, read-only on sources)." 2>/dev/null \
    && { ok "feedback-poll registered"; record feedback-poll; } \
    || warn "feedback-poll registration may have failed"
else
  warn "feedback-poll skipped (set INSTALL_FEEDBACK_POLL=yes once feedback sources are configured) — customer-signal intake stays manual"
fi

if [ "${INSTALL_SENTRY_POLL:-no}" = "yes" ]; then
  step "Installing hotfix-sentry-poll (local, every 10 min)"
  # JUSTIFIED: CLI error output discarded — the exit status still routes to ok/warn below, so a failure is surfaced to the operator, not hidden
  claude -p --bare "Create a scheduled task named 'hotfix-sentry-poll' with cron '*/10 * * * *' timezone 'local' that runs the prompt in .claude/routines/hotfix-sentry-poll.yml (SEV1/SEV2 Sentry triage into hotfix tasks)." 2>/dev/null \
    && { ok "hotfix-sentry-poll registered"; record hotfix-sentry-poll; } \
    || warn "hotfix-sentry-poll registration may have failed"
else
  warn "hotfix-sentry-poll skipped (set INSTALL_SENTRY_POLL=yes once Sentry MCP is configured) — prod errors will NOT auto-create hotfix tasks"
fi

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
