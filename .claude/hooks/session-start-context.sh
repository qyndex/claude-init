#!/usr/bin/env bash
# SessionStart additional context. Augments session-start.sh with deeper state:
# - in-flight brief from the previous session-end (if any)
# - witness brief from the previous compaction (if any)
# - initiative living STATE.md + memory recall (memory-system review §7.2/§7.3)
# - active instincts that match current branch/files
# - top 3 unblocked tasks

set -uo pipefail

ctx_parts=()

# ─── Gap-audit G16: keep skill discovery surfaces fresh ──────────────────
# REGISTRY.md + skill-triggers.tsv are regenerated idempotently (<100ms) so the
# router and any registry reader always see the current catalogue.
bash .claude/scripts/regen-skill-registry.sh >/dev/null 2>&1 || true

# ─── Gap-audit G23: pending dream proposal blocks future dreams ──────────
# auto-dream-check.sh refuses to dream while a proposal awaits review, but used
# to say so only in a log file. Surface it where the operator will see it.
if [ -d .claude/memory.proposed ] && [ "$(ls -A .claude/memory.proposed 2>/dev/null)" ]; then
  # JUSTIFIED: jq on a possibly-corrupt state file degrades to empty (not "true") — the banner only fires on a positively recorded awaiting_review
  awaiting=$(jq -r '.awaiting_review // false' .claude/memory/.cache/.dream-state.json 2>/dev/null)
  if [ "$awaiting" = "true" ]; then
    ctx_parts+=("⚠ DREAM-PENDING: .claude/memory.proposed/ awaits review — ask the user to run /dream-review (--approve | --revert). Memory consolidation is BLOCKED until cleared.")
  fi
fi

# ─── Round 6 B: killed-session detector ─────────────────────────────────
# session-end.sh deletes .claude/memory/.cache/current-session.json on graceful
# exit. If it exists at SessionStart, the previous session was KILLED.
if [ -f .claude/memory/.cache/current-session.json ]; then
  # JUSTIFIED: reads from a session JSON that may be partially written by a killed session; jq's // defaults plus suppression mean a truncated file degrades to "unknown"/0 rather than aborting the killed-session warning
  killed_id=$(jq -r '.session_id // "unknown"' .claude/memory/.cache/current-session.json 2>/dev/null)
  killed_branch=$(jq -r '.branch // "unknown"' .claude/memory/.cache/current-session.json 2>/dev/null)
  killed_turns=$(jq -r '.turn_count // 0' .claude/memory/.cache/current-session.json 2>/dev/null)
  # JUSTIFIED: same partially-written session JSON — // default + suppression degrade a truncated file to 0 uncommitted rather than aborting
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
  # JUSTIFIED: GNU-vs-BSD stat probe — the unsupported flag form errors silently; final `|| echo 0` treats an unstat-able brief as epoch 0 (very old) so it is flagged stale rather than crashing
  age_mins=$(( ( $(date +%s) - $(stat -f %m .claude/memory/in-flight.md 2>/dev/null || stat -c %Y .claude/memory/in-flight.md 2>/dev/null || echo 0) ) / 60 ))
  age_days=$(( age_mins / 1440 ))
  if [ "$age_days" -gt 7 ]; then
    # Rename so we don't keep injecting stale content
    # JUSTIFIED: best-effort rename of a stale brief; if a same-day stale file already exists the mv may fail and that is harmless — the warning context is still emitted
    mv .claude/memory/in-flight.md ".claude/memory/in-flight.stale-$(date +%Y%m%d).md" 2>/dev/null || true
    ctx_parts+=("⚠ STALE-INFLIGHT: previous in-flight brief was ${age_days}d old; renamed to .claude/memory/in-flight.stale-*.md. Review manually before trusting.")
  else
    ctx_parts+=("In-flight brief (${age_mins}m old): .claude/memory/in-flight.md — read it FIRST to resume.")
  fi
fi

# ─── Last compaction witness brief ──────────────────────────────────────
# Show whenever it exists. No 24h filter — a longer-gap project still benefits from
# knowing the last decision context. Stale briefs are flagged with an age hint.
# Memory-system review §7.6: a brief still "(pending)" after a day means the async
# witness DIED — say so loudly instead of suggesting it be read.
# JUSTIFIED: no checkpoint glob match makes `ls` error to /dev/null and yields empty (no brief to show); the stat probe below is GNU-vs-BSD fallback, defaulting to epoch 0 so an unstat-able file just reads as old
last_brief=$(ls -t .claude/memory/.cache/checkpoints/*.md 2>/dev/null | head -1 || echo "")
if [ -n "$last_brief" ]; then
  age_days=$(( ( $(date +%s) - $(stat -f %m "$last_brief" 2>/dev/null || stat -c %Y "$last_brief" 2>/dev/null || echo 0) ) / 86400 ))
  if grep -q '(pending)' "$last_brief" 2>/dev/null && [ "$age_days" -ge 1 ]; then
    ctx_parts+=("⚠ WITNESS-DEAD: $last_brief is still '(pending)' after ${age_days}d — the async witness subagent died. Only its git snapshot is usable; check .claude/hooks/.log/precompact.log and harness-doctor.")
  elif [ "$age_days" -le 1 ]; then
    ctx_parts+=("Last witness brief (${age_days}d): $last_brief — read if context is unclear.")
  else
    ctx_parts+=("Last witness brief (${age_days}d old, possibly stale): $last_brief — read with skepticism.")
  fi
fi

# ─── Initiative living state (memory-system review §7.2) ────────────────
# One line: id, phase, task counts, freshness — the always-current answer to
# "where is this initiative?". Generated by initiative-state.sh sync at
# network boundaries; `show` only reads.
if [ -x .claude/scripts/initiative-state.sh ]; then
  # JUSTIFIED: best-effort injection — a failing show (no STATE.md yet) yields empty and the line is omitted
  init_line=$(bash .claude/scripts/initiative-state.sh show 2>/dev/null || true)
  [ -n "$init_line" ] && ctx_parts+=("$init_line")
fi

# ─── Memory recall (memory-system review §7.3 — the read path) ──────────
# Top-3 index entries whose paths_touched intersect the current working set.
if [ -x .claude/scripts/memory-recall.sh ]; then
  # JUSTIFIED: best-effort injection — no relevant entries yields empty and the line is omitted
  recall=$(bash .claude/scripts/memory-recall.sh --limit 3 2>/dev/null | tr '\n' ' ' || true)
  [ -n "${recall// /}" ] && ctx_parts+=("$recall")
fi

# ─── Active instincts ───────────────────────────────────────────────────
if [ -f .claude/memory/instincts/active.yml ]; then
  # JUSTIFIED: grep -c returns 0 with exit 1 when no instincts match — both the suppression and the `|| echo 0` resolve to a valid "zero active instincts" count
  instinct_count=$(grep -c '^- id:' .claude/memory/instincts/active.yml 2>/dev/null || echo 0)
  if [ "$instinct_count" -gt 0 ]; then
    ctx_parts+=("Active instincts: $instinct_count (see .claude/memory/instincts/active.yml).")
  fi
fi

# ─── Top 3 unblocked tasks ──────────────────────────────────────────────
# T-[0-9]+ guard: TASKS.md's format section contains a literal "- [ ] T-NNN ..."
# template line that the bare pattern matched (memory-system review, 2026-06-12).
if [ -f tasks/TASKS.md ]; then
  # JUSTIFIED: optional task peek — no pending tasks (grep exits 1) is a valid state, yields empty and the next-tasks line is simply omitted
  next_tasks=$(grep -m3 -E '^- \[ \] T-[0-9]+' tasks/TASKS.md 2>/dev/null | sed 's/^- \[ \] *//' | head -3 | tr '\n' '|' || echo "")
  if [ -n "$next_tasks" ]; then
    ctx_parts+=("Next tasks: $next_tasks")
  fi
fi

# ─── Dream state ────────────────────────────────────────────────────────
if [ -f .claude/memory/.cache/.dream-state.json ]; then
  # JUSTIFIED: optional dream-state read — a corrupt cache yields empty, only affects an informational "Last dream:" line
  last_dream=$(jq -r '.last_run // "never"' .claude/memory/.cache/.dream-state.json 2>/dev/null)
  ctx_parts+=("Last dream: $last_dream")
fi

# ─── Memory pressure ────────────────────────────────────────────────────
if [ -f .claude/memory/MEMORY.md ]; then
  # JUSTIFIED: best-effort line count guarded by the -f test above; an unreadable file falls back to 0, which simply skips the over-budget warning
  mem_lines=$(wc -l < .claude/memory/MEMORY.md 2>/dev/null || echo 0)
  if [ "$mem_lines" -gt 200 ]; then
    ctx_parts+=("⚠ MEMORY.md is ${mem_lines} lines (cap=200) — run \`.claude/scripts/memory-gc.sh enforce\`.")
  fi
fi

# ─── Round 8 C: Repo Atlas pointer ──────────────────────────────────────
# Inject a 1-line atlas summary so agents know the stack without re-discovering.
if [ -f .claude/memory/atlas/manifest.json ] && command -v jq >/dev/null 2>&1; then
  # JUSTIFIED: optional atlas-manifest field reads — a missing key/malformed manifest yields empty, surfaced as a "stale" hint, never an error
  atlas_updated=$(jq -r .updated_at .claude/memory/atlas/manifest.json 2>/dev/null)
  atlas_sha=$(jq -r .git_sha .claude/memory/atlas/manifest.json 2>/dev/null)
  atlas_web=$(jq -r .frameworks.web .claude/memory/atlas/manifest.json 2>/dev/null)
  # JUSTIFIED: optional atlas-manifest field reads — a missing key/malformed manifest yields empty, surfaced as a "stale" hint, never an error
  atlas_api=$(jq -r .frameworks.api .claude/memory/atlas/manifest.json 2>/dev/null)
  atlas_orm=$(jq -r .frameworks.orm .claude/memory/atlas/manifest.json 2>/dev/null)

  # Compute age
  if [ -n "$atlas_updated" ]; then
    # JUSTIFIED: GNU vs BSD date probe — whichever flag form is unsupported errors silently; the final `|| echo 0` makes an unparseable timestamp read as epoch 0 (very old), which correctly trips the staleness path below
    age_days=$(( ( $(date +%s) - $(date -d "$atlas_updated" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%S%z' "${atlas_updated%%+*}" +%s 2>/dev/null || echo 0) ) / 86400 ))
  else
    age_days=99
  fi

  # Check stale vs current
  # JUSTIFIED: git rev-parse fails outside a repo / before first commit — empty SHA is fine, it only feeds an advisory staleness hint
  current_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
  stale_reason=""
  [ "$age_days" -gt 7 ] && stale_reason="atlas >7d old"
  [ -f .claude/memory/atlas/.dirty ] && stale_reason="watched files changed since refresh"

  if [ -n "$stale_reason" ]; then
    # Gap-audit G21: no /atlas command exists — the script is the only real path
    ctx_parts+=("⚠ ATLAS STALE ($stale_reason) — run \`bash .claude/scripts/atlas-refresh.sh\`.")
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
# Gap-audit G45: staleness from CONTENT dates, not file mtime — a git clone
# (or any touch) resets mtimes, so `find -mtime +365` never fired on real
# repos. An ADR is stale when its freshest content date (last_verified if
# present, else Date) is >12 months old.
if [ -d .claude/memory/decisions ]; then
  cutoff=$(date -v-1y +%Y-%m-%d 2>/dev/null || date -d '1 year ago' +%Y-%m-%d 2>/dev/null)
  stale_adrs=0
  for adr in .claude/memory/decisions/[0-9]*.md; do
    [ -f "$adr" ] || continue
    case "$adr" in *0000-template.md) continue ;; esac
    fresh=$(grep -E '^- \*\*last_verified\*\*:' "$adr" | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
    [ -z "$fresh" ] && fresh=$(grep -E '^- \*\*Date\*\*:' "$adr" | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
    [ -z "$fresh" ] && continue  # placeholder/template dates — not assessable
    # YYYY-MM-DD compares correctly as a string
    if [ -n "$cutoff" ] && [ "$fresh" \< "$cutoff" ]; then
      stale_adrs=$((stale_adrs + 1))
    fi
  done
  if [ "$stale_adrs" -gt 0 ]; then
    ctx_parts+=("$stale_adrs ADR(s) not verified in >12mo — re-check each, then stamp it: \`/adr-walk --reverify <id>\`.")
  fi
fi

# ─── Round 6 F: recent rate-limit events ────────────────────────────────
# If we've hit rate-limit in the last hour, surface a warning so the operator
# knows the slowness isn't us — and considers throttling concurrency.
if [ -f .claude/hooks/.log/ratelimit.jsonl ]; then
  # Portable: the previous gawk 3-arg match() was a syntax error on BSD awk
  # (macOS), so this check had been silently broken there.
  # JUSTIFIED: GNU date form is tried first and its error muted on BSD, where the second form computes the cutoff instead
  rl_cutoff=$(date -u -d '1 hour ago' -Iseconds 2>/dev/null || date -u -v -1H -Iseconds)
  # JUSTIFIED: grep exits 1 when no rate-limit lines exist — empty pipeline yields 0, the correct count
  recent_limits=$(grep '"kind":"rate_limit"' .claude/hooks/.log/ratelimit.jsonl 2>/dev/null \
    | sed -nE 's/.*"ts":"([^"]+)".*/\1/p' \
    | awk -v c="$rl_cutoff" '$0 >= c' | wc -l | tr -d ' ')
  if [ "${recent_limits:-0}" -gt 0 ]; then
    ctx_parts+=("⚠ ${recent_limits} rate-limit hits in last 1h — see .claude/hooks/.log/ratelimit.jsonl. Consider lower swarm concurrency or Sonnet fallback.")
  fi
fi

# ─── Round 6 F: background daemon status ────────────────────────────────
# claude --bg sessions can die silently on network outage. Surface a hint
# if fleet.json claims running streams but their process IDs are gone.
if [ -f .swarms/coordinator/fleet.json ] && command -v jq >/dev/null 2>&1; then
  # JUSTIFIED: optional fleet read — a malformed/empty fleet.json yields empty, defaulted to 0 via ${running_count:-0} below
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
