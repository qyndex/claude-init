#!/usr/bin/env bash
# SessionStart additional context. Augments session-start.sh with deeper state:
# - in-flight brief from the previous session-end (if any)
# - witness brief from the previous compaction (if any)
# - active instincts that match current branch/files
# - top 3 unblocked tasks

set -uo pipefail

ctx_parts=()

# ─── Round 6 B: killed-session detector ─────────────────────────────────
# session-end.sh deletes .claude/memory/.cache/current-session.json on graceful
# exit. If it exists at SessionStart, the previous session was KILLED.
if [ -f .claude/memory/.cache/current-session.json ]; then
  killed_id=$(jq -r '.session_id // "unknown"' .claude/memory/.cache/current-session.json 2>/dev/null)
  killed_branch=$(jq -r '.branch // "unknown"' .claude/memory/.cache/current-session.json 2>/dev/null)
  killed_turns=$(jq -r '.turn_count // 0' .claude/memory/.cache/current-session.json 2>/dev/null)
  killed_uncommitted=$(jq -r '.uncommitted // 0' .claude/memory/.cache/current-session.json 2>/dev/null)
  ctx_parts+=("⚠ KILLED-SESSION: previous session ($killed_id) on $killed_branch was terminated abnormally after $killed_turns turns with $killed_uncommitted uncommitted files. Run \`bash .claude/scripts/resume-or-restart.sh\` to triage.")
fi

# ─── Round 6 B: subscription-switch / home-dir drift detector ──────────
# If our project hash directory is missing from ~/.claude/ but we have a mirror,
# the user likely wiped home dir, cloned on a new machine, or switched
# subscriptions in a way that orphaned state.
project_slug=$(pwd | sed 's|/|-|g')
user_state_dir="$HOME/.claude/projects/${project_slug}"
mirror_archive=".claude/.user-state-mirror/${project_slug}.tar.gz"
if [ ! -d "$user_state_dir" ] && [ -f "$mirror_archive" ]; then
  ctx_parts+=("⚠ USER-STATE-MISSING: \$HOME/.claude/projects/ has no entry for this project, but mirror exists at $mirror_archive. Restore with \`bash .claude/scripts/restore-user-state.sh\` (likely home-dir wipe, new machine, or subscription switch).")
fi

# ─── In-flight brief from prior session-end (highest priority) ──────────
# Round 6 B: hard cap at 7d age — older briefs are stale and misleading.
if [ -f .claude/memory/in-flight.md ]; then
  age_mins=$(( ( $(date +%s) - $(stat -f %m .claude/memory/in-flight.md 2>/dev/null || stat -c %Y .claude/memory/in-flight.md 2>/dev/null || echo 0) ) / 60 ))
  age_days=$(( age_mins / 1440 ))
  if [ "$age_days" -gt 7 ]; then
    # Rename so we don't keep injecting stale content
    mv .claude/memory/in-flight.md ".claude/memory/in-flight.stale-$(date +%Y%m%d).md" 2>/dev/null || true
    ctx_parts+=("⚠ STALE-INFLIGHT: previous in-flight brief was ${age_days}d old; renamed to .claude/memory/in-flight.stale-*.md. Review manually before trusting.")
  else
    ctx_parts+=("In-flight brief (${age_mins}m old): .claude/memory/in-flight.md — read it FIRST to resume.")
  fi
fi

# ─── Last compaction witness brief ──────────────────────────────────────
# Show whenever it exists. No 24h filter — a longer-gap project still benefits from
# knowing the last decision context. Stale briefs are flagged with an age hint.
last_brief=$(ls -t .claude/memory/.cache/checkpoints/*.md 2>/dev/null | head -1 || echo "")
if [ -n "$last_brief" ]; then
  age_days=$(( ( $(date +%s) - $(stat -f %m "$last_brief" 2>/dev/null || stat -c %Y "$last_brief" 2>/dev/null || echo 0) ) / 86400 ))
  if [ "$age_days" -le 1 ]; then
    ctx_parts+=("Last witness brief (${age_days}d): $last_brief — read if context is unclear.")
  else
    ctx_parts+=("Last witness brief (${age_days}d old, possibly stale): $last_brief — read with skepticism.")
  fi
fi

# ─── Active instincts ───────────────────────────────────────────────────
if [ -f .claude/memory/instincts/active.yml ]; then
  instinct_count=$(grep -c '^- id:' .claude/memory/instincts/active.yml 2>/dev/null || echo 0)
  if [ "$instinct_count" -gt 0 ]; then
    ctx_parts+=("Active instincts: $instinct_count (see .claude/memory/instincts/active.yml).")
  fi
fi

# ─── Top 3 unblocked tasks ──────────────────────────────────────────────
if [ -f tasks/TASKS.md ]; then
  next_tasks=$(grep -m3 '^- \[ \]' tasks/TASKS.md 2>/dev/null | sed 's/^- \[ \] *//' | head -3 | tr '\n' '|' || echo "")
  if [ -n "$next_tasks" ]; then
    ctx_parts+=("Next tasks: $next_tasks")
  fi
fi

# ─── Dream state ────────────────────────────────────────────────────────
if [ -f .claude/memory/.cache/.dream-state.json ]; then
  last_dream=$(jq -r '.last_run // "never"' .claude/memory/.cache/.dream-state.json 2>/dev/null)
  ctx_parts+=("Last dream: $last_dream")
fi

# ─── Memory pressure ────────────────────────────────────────────────────
if [ -f .claude/memory/MEMORY.md ]; then
  mem_lines=$(wc -l < .claude/memory/MEMORY.md 2>/dev/null || echo 0)
  if [ "$mem_lines" -gt 200 ]; then
    ctx_parts+=("⚠ MEMORY.md is ${mem_lines} lines (cap=200) — run \`.claude/scripts/memory-gc.sh enforce\`.")
  fi
fi

# ─── Round 8 C: Repo Atlas pointer ──────────────────────────────────────
# Inject a 1-line atlas summary so agents know the stack without re-discovering.
if [ -f .claude/memory/atlas/manifest.json ] && command -v jq >/dev/null 2>&1; then
  atlas_updated=$(jq -r .updated_at .claude/memory/atlas/manifest.json 2>/dev/null)
  atlas_sha=$(jq -r .git_sha .claude/memory/atlas/manifest.json 2>/dev/null)
  atlas_web=$(jq -r .frameworks.web .claude/memory/atlas/manifest.json 2>/dev/null)
  atlas_api=$(jq -r .frameworks.api .claude/memory/atlas/manifest.json 2>/dev/null)
  atlas_orm=$(jq -r .frameworks.orm .claude/memory/atlas/manifest.json 2>/dev/null)

  # Compute age
  if [ -n "$atlas_updated" ]; then
    age_days=$(( ( $(date +%s) - $(date -d "$atlas_updated" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%S%z' "${atlas_updated%%+*}" +%s 2>/dev/null || echo 0) ) / 86400 ))
  else
    age_days=99
  fi

  # Check stale vs current
  current_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
  stale_reason=""
  [ "$age_days" -gt 7 ] && stale_reason="atlas >7d old"
  [ -f .claude/memory/atlas/.dirty ] && stale_reason="watched files changed since refresh"

  if [ -n "$stale_reason" ]; then
    ctx_parts+=("⚠ ATLAS STALE ($stale_reason) — run \`bash .claude/scripts/atlas-refresh.sh\` or \`/atlas refresh\`.")
  else
    ctx_parts+=("[atlas] Web: $atlas_web | API: $atlas_api | ORM: $atlas_orm | Updated: ${atlas_updated%%T*}. Read .claude/memory/atlas/{STACK,STRUCTURE,KNOWN_ENTRIES}.md for full details.")

    # Round 9 F: stack-aware skill suggestions (once per day via cache)
    mkdir -p .claude/memory/.cache
    cache=".claude/memory/.cache/stack-skills-shown-$(date +%Y%m%d)"
    if [ ! -f "$cache" ]; then
      stack_skills=""
      case "$atlas_web" in
        *"Vite"*) stack_skills="react-vite" ;;
        *"Next.js"*) stack_skills="nextjs" ;;
      esac
      case "$atlas_api" in
        *FastAPI*) stack_skills="${stack_skills:+$stack_skills, }fastapi" ;;
        *Flask*) stack_skills="${stack_skills:+$stack_skills, }flask-realtime" ;;
        *tRPC*|*Express*|*Fastify*|*Hono*) stack_skills="${stack_skills:+$stack_skills, }react-node" ;;
      esac
      case "$atlas_web" in
        unknown|"") ;;
        *) stack_skills="${stack_skills:+$stack_skills, }front-end-design, tailwind-discipline" ;;
      esac
      if [ -n "$stack_skills" ]; then
        ctx_parts+=("[stack-skills] Recommended for this stack: $stack_skills")
        touch "$cache"
      fi
    fi
  fi
fi

# ─── ADR re-verification backlog ────────────────────────────────────────
if [ -d .claude/memory/decisions ]; then
  # Count ADRs >12mo with no last_verified
  stale_adrs=$(find .claude/memory/decisions -name '*.md' -mtime +365 2>/dev/null | \
    xargs grep -L '^- \*\*last_verified\*\*:' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$stale_adrs" -gt 0 ]; then
    ctx_parts+=("$stale_adrs ADR(s) need re-verification — run \`/adr-walk\`.")
  fi
fi

# ─── Round 6 F: recent rate-limit events ────────────────────────────────
# If we've hit rate-limit in the last hour, surface a warning so the operator
# knows the slowness isn't us — and considers throttling concurrency.
if [ -f .claude/hooks/.log/ratelimit.jsonl ]; then
  recent_limits=$(awk -v cutoff="$(date -u -d '1 hour ago' -Iseconds 2>/dev/null || date -u -v -1H -Iseconds)" \
    '$0 ~ /"kind":"rate_limit"/ && $0 ~ /"ts":"/ {
      if (match($0, /"ts":"([^"]+)"/, m) && m[1] >= cutoff) c++
    } END { print c+0 }' .claude/hooks/.log/ratelimit.jsonl)
  if [ "${recent_limits:-0}" -gt 0 ]; then
    ctx_parts+=("⚠ ${recent_limits} rate-limit hits in last 1h — see .claude/hooks/.log/ratelimit.jsonl. Consider lower swarm concurrency or Sonnet fallback.")
  fi
fi

# ─── Round 6 F: background daemon status ────────────────────────────────
# claude --bg sessions can die silently on network outage. Surface a hint
# if fleet.json claims running streams but their process IDs are gone.
if [ -f .swarms/coordinator/fleet.json ] && command -v jq >/dev/null 2>&1; then
  running_count=$(jq -r '[.fleet[] | select(.status == "running")] | length' .swarms/coordinator/fleet.json 2>/dev/null)
  if [ "${running_count:-0}" -gt 0 ]; then
    ctx_parts+=("${running_count} swarm stream(s) marked running in fleet.json. Verify with \`claude agents --json\`; if stale, run /swarm:status.")
  fi
fi

# Output
if [ ${#ctx_parts[@]} -gt 0 ]; then
  ctx=$(IFS=' '; echo "${ctx_parts[*]}")
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "[session-start-context] $ctx"
  }
}
EOF
fi

exit 0
