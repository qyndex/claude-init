#!/usr/bin/env bash
# Mechanical flag kill — e2e-audit release-deploy-4.
#
# The fastest rollback in a flagged world is a flag flip. This script is the
# EXECUTABLE half of /rollback-flag (which was prose-only): provider adapters
# that flip a flag to 0%/OFF in seconds, callable from
#   • the canary SLO-breach path (canary-deploy.yml, before exit 1)
#   • hotfix-ingest.yml (first responder when the alert maps to a flag-gated spec)
#   • /rollback-flag and the flag-rollout/ramp-check drivers
#
# Provider selection: FLAG_PROVIDER env (launchdarkly|posthog|unleash|webhook).
# Unwired (unset/none) is a LOUD exit 2 — callers decide whether that is fatal.
#
# Usage:
#   rollback-flag.sh <flag-name> [--reason <text>] [--dry-run]
#   rollback-flag.sh --service <svc> [--reason <text>]   # resolve flag via specs/REGISTRY
#
# Exit: 0 killed · 2 provider unwired/kill failed · 3 no flag resolved for --service

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"

FLAG=""; SERVICE=""; REASON="manual"; DRY=0
while [ $# -gt 0 ]; do case "$1" in
  --service) SERVICE="${2:-}"; shift 2 ;;
  --reason)  REASON="${2:-manual}"; shift 2 ;;
  --dry-run) DRY=1; shift ;;
  -*) shift ;;
  *) FLAG="$1"; shift ;;
esac; done

REGISTRY=".claude/memory/flags/REGISTRY.md"
KILL_LOG=".claude/memory/playbooks/flag-kill-log.md"

# ── Resolve flag from service (canary calls with --service "$SERVICE") ─────
if [ -z "$FLAG" ] && [ -n "$SERVICE" ]; then
  # SERVICE can arrive from a repository_dispatch client_payload (untrusted) —
  # constrain to identifier chars so it can't smuggle regex into the greps below.
  case "$SERVICE" in
    *[!A-Za-z0-9._-]*) echo "rollback-flag: invalid service name '$SERVICE' (identifier chars only)" >&2; exit 1 ;;
  esac
  # 1) a spec that names the service and carries a ## Rollout flag
  for spec in specs/active/*.md; do
    [ -f "$spec" ] || continue
    grep -qE "^service: *${SERVICE}\b" "$spec" || continue
    FLAG=$(awk '/^## Rollout/{r=1} r && /^  name:/{print $2; exit}' "$spec" | tr -d '"')
    [ -n "$FLAG" ] && break
  done
  # 2) registry row mentioning the service
  if [ -z "$FLAG" ] && [ -f "$REGISTRY" ]; then
    # JUSTIFIED: grep miss = service not in the registry — falls through to exit 3 below
    FLAG=$(grep -E "\b${SERVICE}\b" "$REGISTRY" 2>/dev/null | grep -oE '[a-z0-9_.-]+_enabled|flag[._-][a-z0-9_.-]+' | head -1 || true)
  fi
  if [ -z "$FLAG" ]; then
    echo "rollback-flag: no flag mapped to service '$SERVICE' (no spec with service: $SERVICE + ## Rollout, no registry row) — nothing to kill" >&2
    exit 3
  fi
fi
[ -z "$FLAG" ] && { echo "usage: rollback-flag.sh <flag-name>|--service <svc> [--reason <text>] [--dry-run]"; exit 1; }
# Flag names go into provider URLs/JSON — same identifier constraint.
case "$FLAG" in
  *[!A-Za-z0-9._-]*) echo "rollback-flag: invalid flag name '$FLAG' (identifier chars only)" >&2; exit 1 ;;
esac

provider="${FLAG_PROVIDER:-}"
if [ -z "$provider" ] || [ "$provider" = "none" ]; then
  echo "rollback-flag: FLAG_PROVIDER is unwired — CANNOT kill '$FLAG' mechanically." >&2
  echo "Set FLAG_PROVIDER=launchdarkly|posthog|unleash|webhook (+ its credentials) or kill the flag manually NOW." >&2
  exit 2
fi

if [ "$DRY" = 1 ]; then
  echo "[dry-run] would kill flag '$FLAG' via $provider (reason: $REASON)"
  exit 0
fi

kill_rc=1
case "$provider" in
  launchdarkly)
    : "${LD_API_KEY:?rollback-flag: LD_API_KEY required}"
    curl -fsS -X PATCH "https://app.launchdarkly.com/api/v2/flags/${LD_PROJECT:-default}/$FLAG" \
      -H "Authorization: $LD_API_KEY" -H 'Content-Type: application/json' \
      -d "[{\"op\":\"replace\",\"path\":\"/environments/${LD_ENV:-production}/on\",\"value\":false}]" >/dev/null
    kill_rc=$?
    ;;
  posthog)
    : "${POSTHOG_API_KEY:?rollback-flag: POSTHOG_API_KEY required}"
    fid=$(curl -fsS "https://app.posthog.com/api/projects/${POSTHOG_PROJECT_ID:-@current}/feature_flags/?search=$FLAG" \
      -H "Authorization: Bearer $POSTHOG_API_KEY" | jq -r --arg k "$FLAG" '.results[] | select(.key==$k) | .id' | head -1)
    if [ -n "$fid" ]; then
      curl -fsS -X PATCH "https://app.posthog.com/api/projects/${POSTHOG_PROJECT_ID:-@current}/feature_flags/$fid/" \
        -H "Authorization: Bearer $POSTHOG_API_KEY" -H 'Content-Type: application/json' \
        -d '{"active": false}' >/dev/null
      kill_rc=$?
    else
      echo "rollback-flag: flag '$FLAG' not found in PostHog project" >&2
    fi
    ;;
  unleash)
    : "${UNLEASH_URL:?rollback-flag: UNLEASH_URL required}" "${UNLEASH_API_TOKEN:?rollback-flag: UNLEASH_API_TOKEN required}"
    curl -fsS -X POST "$UNLEASH_URL/api/admin/projects/${UNLEASH_PROJECT:-default}/features/$FLAG/environments/${UNLEASH_ENV:-production}/off" \
      -H "Authorization: $UNLEASH_API_TOKEN" >/dev/null
    kill_rc=$?
    ;;
  webhook)
    : "${FLAG_KILL_WEBHOOK:?rollback-flag: FLAG_KILL_WEBHOOK required}"
    curl -fsS -X POST "$FLAG_KILL_WEBHOOK" -H 'Content-Type: application/json' \
      -d "{\"flag\":\"$FLAG\",\"action\":\"kill\",\"reason\":\"$REASON\"}" >/dev/null
    kill_rc=$?
    ;;
  *)
    echo "rollback-flag: unknown FLAG_PROVIDER '$provider'" >&2
    exit 2
    ;;
esac

if [ "$kill_rc" -ne 0 ]; then
  echo "rollback-flag: provider call FAILED (rc=$kill_rc) — flag '$FLAG' may still be live. Kill it manually NOW." >&2
  exit 2
fi

# ── Audit trail (always, after a successful kill) ──────────────────────────
mkdir -p "$(dirname "$KILL_LOG")" "$(dirname "$REGISTRY")"
printf '%s  rollback-flag %s  provider=%s  reason: %s\n' "$(date -Iseconds)" "$FLAG" "$provider" "$REASON" >> "$KILL_LOG"
[ -f "$REGISTRY" ] || printf '# Flag registry\n\n' > "$REGISTRY"
printf '| %s | KILLED (0%%) | %s | rollback-flag: %s |\n' "$FLAG" "$(date -Iseconds)" "$REASON" >> "$REGISTRY"
echo "✓ flag '$FLAG' killed via $provider (reason: $REASON) — logged to $KILL_LOG"
echo "  Next: /incident-start if not already open; spec status shipping → paused."
