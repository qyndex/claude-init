#!/usr/bin/env bash
# SubagentStop hook — Round 6 C makes this a DIGEST, not just a log line.
#
# When a subagent completes, parse its final message for a NEXUS YAML handoff
# block. Extract status, files modified, follow-up tasks, blockers. Surface
# the digest back to the parent as additionalContext so the parent doesn't
# have to read 30 turns of transcript to understand what happened.
#
# Also runs `git diff --name-only` against any swarm worktree to surface file
# changes the parent's main worktree can't see.
#
# Output schema (single JSON line to subagent.jsonl):
# {ts, agent_type, session_id, status, files_modified, followup_tasks, blockers}

set -uo pipefail

# Shared swarm root (e2e-audit swarm-1): .swarms/** reads/writes must resolve
# to the MAIN checkout even when this hook fires inside a feat-* worktree.
# shellcheck source=../scripts/lib/swarm-root.sh
. "$(cd "$(dirname "$0")/../scripts/lib" && pwd)/swarm-root.sh"

mkdir -p .claude/hooks/.log

input=$(cat)
agent_type=$(printf '%s' "$input" | jq -r '.agent_type // .tool_input.subagent_type // "unknown"')
session_id=$(printf '%s' "$input" | jq -r '.session_id // ""')
final_message=$(printf '%s' "$input" | jq -r '.tool_response.final_message // .tool_response.content // ""')
ts=$(date -Iseconds)

# e2e-audit autopilot-3: livelock breaker — on re-entry (stop_hook_active) the
# hard-enforce paths below escalate into the handoff log + OVERNIGHT_REPORT.md
# instead of exit-2-looping a subagent that cannot produce a valid handoff.
stop_hook_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)
escalate_handoff() { # escalate_handoff <reason>
  printf '%s\tagent=%s\tESCALATION\t%s\n' "$ts" "$agent_type" "$1" >> .claude/hooks/.log/subagent.log
  {
    echo ""
    echo "## ⚠ ESCALATION ($ts) — ${agent_type} handoff gate could not be satisfied"
    echo "- reason: $1"
    echo "- session: ${session_id:-unknown}"
  } >> OVERNIGHT_REPORT.md 2>/dev/null || true
  echo "[subagent-stop] ESCALATION: $1 — allowing Stop after re-entry; see OVERNIGHT_REPORT.md" >&2
}

# Plain log (preserved for backward compat)
printf '%s\tagent=%s\n' "$ts" "$agent_type" >> .claude/hooks/.log/subagent.log

# ─── Round 6 C: extract NEXUS YAML handoff block ────────────────────────
# Look for fenced ```nexus or ```yaml block in the final message.
status=""
handoff_path=""
followup_count=0
blockers_count=0
files_modified=""
archive_file=""
soft_missing=0
adr_missing=0

if [ -n "$final_message" ]; then
  # Save final message to a temp for grep + extract block content
  tmp_msg=$(mktemp)
  printf '%s' "$final_message" > "$tmp_msg"

  # Look for ```nexus or ```yaml block
  yaml_block=$(awk '
    /^```(nexus|yaml)$/ { in_block=1; next }
    /^```$/ && in_block { in_block=0 }
    in_block { print }
  ' "$tmp_msg")

  if [ -n "$yaml_block" ]; then
    # Crude field extraction (we don't depend on yq; bash + grep is enough for status)
    status=$(echo "$yaml_block" | grep -E '^status:' | head -1 | sed 's/status:[[:space:]]*//' | tr -d '"' | head -c 50)
    followup_count=$(echo "$yaml_block" | awk '/^followup_tasks:/{f=1; next} /^[a-z_]+:/{f=0} f && /^[[:space:]]*-/' | wc -l | tr -d ' ')
    blockers_count=$(echo "$yaml_block" | awk '/^blockers_encountered:/{f=1; next} /^[a-z_]+:/{f=0} f && /^[[:space:]]*-[[:space:]]*description:/' | wc -l | tr -d ' ')
    files_modified=$(echo "$yaml_block" | awk '/^files_modified:/{f=1; next} /^[a-z_]+:/{f=0} f && /^[[:space:]]*-[[:space:]]*path:/' | sed 's/.*path:[[:space:]]*//' | head -10 | tr '\n' ',' | sed 's/,$//')

    # ─── Round 6 D: hard-enforce for swarm streams ──────────────────────
    # feature-stream and coordinator MUST emit valid YAML. Other agents emit
    # but block-validation is soft (warn, accept).
    case "$agent_type" in
      feature-stream|coordinator)
        # Validate the block; non-zero exit blocks the subagent's stop
        if ! echo "$yaml_block" | bash .claude/scripts/validate-handoff.sh --stdin >/dev/null 2>&1; then
          rm -f "$tmp_msg"
          cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "[subagent-stop] BLOCK: ${agent_type} returned an INVALID NEXUS handoff. Re-emit with all required fields per .swarms/templates/handoff.yaml. Run: echo \\\"\$BLOCK\\\" | bash .claude/scripts/validate-handoff.sh --stdin to debug."
  }
}
EOF
          # Log the failure
          printf '%s\tagent=%s\tinvalid_handoff\n' "$ts" "$agent_type" >> .claude/hooks/.log/subagent.log
          if [ "$stop_hook_active" = "true" ]; then
            escalate_handoff "${agent_type} returned an INVALID NEXUS handoff (re-entry)"
          else
            # On exit 2 the harness surfaces STDERR to the agent; stdout JSON is ignored.
            echo "[subagent-stop] BLOCK: ${agent_type} returned an INVALID NEXUS handoff. Re-emit with all required fields per .swarms/templates/handoff.yaml." >&2
            exit 2
          fi
        fi
        ;;
    esac

    # ─── Gap-audit G27/G33/G34: persist the handoff durably ─────────────────
    # Previously the digest lived only in the parent's transcript + a count-only
    # JSONL — decisions_made, rejected_hypotheses, and incident notes evaporated
    # with the parent's context. Archive the full YAML where the dream pipeline
    # (and any future session) can consolidate it.
    handoff_dir=".claude/memory/handoffs/$(date +%Y-%m)"
    # JUSTIFIED: archive is best-effort — an unwritable dir leaves archive_file empty and the digest simply omits it
    if mkdir -p "$handoff_dir" 2>/dev/null; then
      safe_ts=$(printf '%s' "$ts" | tr ':+' '--')
      archive_file="$handoff_dir/${safe_ts}-${agent_type}.yaml"
      printf '%s\n' "$yaml_block" > "$archive_file" 2>/dev/null || archive_file=""
    fi

    # ─── Gap-audit G37: followup_tasks → TASKS.md, deterministically ────────
    # The constitution promised this bridge; it was prose-only. Render the YAML
    # list as checkbox lines and feed the existing lock-safe idempotent helper.
    followup_items=$(echo "$yaml_block" | awk '/^followup_tasks:/{f=1; next} /^[a-z_]+:/{f=0} f && /^[[:space:]]*-/' \
      | sed -E 's/^[[:space:]]*-[[:space:]]*//; s/^"//; s/"$//' | grep -v '^$' || true)
    if [ -n "$followup_items" ] && [ -x .claude/scripts/findings-to-tasks.sh ]; then
      ft_tmp=$(mktemp)
      printf '%s\n' "$followup_items" | sed 's/^/- [ ] /' > "$ft_tmp"
      # JUSTIFIED: bridge is best-effort — a failure is visible via followup_tasks count in the digest; it must not block the subagent's stop
      bash .claude/scripts/findings-to-tasks.sh "$ft_tmp" --priority normal --source "handoff:${agent_type}" >/dev/null 2>&1 || true
      rm -f "$ft_tmp"
    fi

    # ─── Gap-audit G40: architect handoff must cite ADRs ────────────────────
    # An architect run that made decisions but referenced no ADR is the exact
    # leak the adr-gate catches later at PR time — flag it at the source.
    if [ "$agent_type" = "architect" ]; then
      adr_refs=$(echo "$yaml_block" | awk '/^adrs_referenced:/{f=1; next} /^[a-z_]+:/{f=0} f && /^[[:space:]]*-/' | grep -v '^\s*-\s*$' || true)
      if [ -z "$adr_refs" ]; then
        adr_missing=1
        printf '%s\tagent=%s\tadrs_referenced_empty\n' "$ts" "$agent_type" >> .claude/hooks/.log/subagent.log
      fi
    fi
  elif [ "$agent_type" = "feature-stream" ] || [ "$agent_type" = "coordinator" ]; then
    # Hard-enforced agent didn't emit a YAML block at all
    rm -f "$tmp_msg"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "[subagent-stop] BLOCK: ${agent_type} did not emit a NEXUS handoff block (\`\`\`nexus or \`\`\`yaml). This is required for swarm agents. See .claude/skills/handoff/SKILL.md."
  }
}
EOF
    printf '%s\tagent=%s\tmissing_handoff\n' "$ts" "$agent_type" >> .claude/hooks/.log/subagent.log
    if [ "$stop_hook_active" = "true" ]; then
      escalate_handoff "${agent_type} did not emit a NEXUS handoff block (re-entry)"
    else
      echo "[subagent-stop] BLOCK: ${agent_type} did not emit a NEXUS handoff block (\`\`\`nexus or \`\`\`yaml). This is required for swarm agents. See .claude/skills/handoff/SKILL.md." >&2
      exit 2
    fi
  else
    # ─── Gap-audit G38: SOFT tier actually warns now ────────────────────────
    # Constitution §XV says soft agents are "warn, accept" — previously a soft
    # agent skipping the handoff was silently accepted, so the contract decayed
    # invisibly. Log it (measurable) + nudge the parent (visible).
    case "$agent_type" in
      architect|planner|implementer|reviewer|verifier|security|debugger|researcher|doc-writer|tester)
        printf '%s\tagent=%s\tmissing_handoff_soft\n' "$ts" "$agent_type" >> .claude/hooks/.log/subagent.log
        soft_missing=1
        ;;
    esac
  fi

  # Find any handoff-<ts>.yaml or .md file the subagent may have written
  # JUSTIFIED: the redirect drops find stderr when .swarms or the reference log is absent — an empty handoff_path just leaves the digest field blank
  handoff_path=$(find "${SWARM_ROOT:-.}/.swarms" -name 'handoff-*.yaml' -newer .claude/hooks/.log/subagent.log -type f 2>/dev/null | head -1)

  # ─── AC-25: auto-populate tdd_state for feature-stream if absent ────────
  # If the agent didn't emit tdd_state, derive it from the WIP commit log and
  # the bash.log tdd-ledger lines so the coordinator can make merge decisions.
  if [ "$agent_type" = "feature-stream" ] && [ -n "$yaml_block" ]; then
    if ! echo "$yaml_block" | grep -qE '^tdd_state:|^  phase:'; then
      # Derive tdd_phase from bash.log: last tdd-ledger line wins
      tdd_phase="n/a"
      if [ -f .claude/hooks/.log/bash.log ]; then
        last_tdd=$(grep -E 'tdd-(red|green|refactor)' .claude/hooks/.log/bash.log 2>/dev/null | tail -1)
        case "$last_tdd" in
          *tdd-red*)     tdd_phase="red" ;;
          *tdd-green*)   tdd_phase="green" ;;
          *tdd-refactor*) tdd_phase="refactor" ;;
        esac
      fi
      # Derive wip_sha from most recent WIP: commit in current or worktree repo
      wip_sha=""
      if [ -n "${worktree:-}" ] && [ -d "$worktree" ]; then
        wip_sha=$(cd "$worktree" && git log --grep='^WIP:' --format='%h' -1 2>/dev/null || true)
      fi
      [ -z "$wip_sha" ] && wip_sha=$(git log --grep='^WIP:' --format='%h' -1 2>/dev/null || true)

      # Append tdd_state block to the handoff YAML in the digest context (not the live file)
      tdd_block="tdd_state:
  phase: ${tdd_phase}
  last_test_command: \"\"
  last_test_exit_code: \"\"
  wip_sha: \"${wip_sha}\""
      # Surface in the digest additionalContext
      yaml_block="${yaml_block}
${tdd_block}"
    fi
  fi

  rm -f "$tmp_msg"
fi

# ─── Worktree git diff surface (feature-stream only) ────────────────────
worktree_diff=""
if [ "$agent_type" = "feature-stream" ]; then
  # Look up worktree from fleet.json by session_id (shared root — swarm-1)
  if [ -f "${SWARM_ROOT:-.}/.swarms/coordinator/fleet.json" ] && command -v jq >/dev/null 2>&1; then
    # JUSTIFIED: the redirect drops jq stderr on a malformed fleet.json — an empty worktree fails the guard below and skips the diff surface
    worktree=$(jq -r --arg sid "$session_id" \
      '.fleet | to_entries[] | select(.value.sessionId == $sid) | .value.worktree' \
      "${SWARM_ROOT:-.}/.swarms/coordinator/fleet.json" 2>/dev/null | head -1)
    if [ -n "$worktree" ] && [ -d "$worktree" ]; then
      # JUSTIFIED: the redirect drops git diff stderr if the worktree has no main ref — an empty diff just leaves the worktree_diff digest field blank
      worktree_diff=$(cd "$worktree" && git diff --name-only main...HEAD 2>/dev/null | head -10 | tr '\n' ',' | sed 's/,$//')
    fi
  fi

  # ─── Spec 001 AC-17: emit lane.finished when a swarm stream stops ───────
  # Derive the stream id from the worktree branch (feat-<N>); fall back to the
  # worktree dir basename. The coordinator tails .swarms/events/<id>.jsonl and
  # treats lane.finished as the signal a stream is ready for a merge decision.
  lane_stream_id=""
  if [ -n "${worktree:-}" ] && [ -d "$worktree" ]; then
    # JUSTIFIED: the redirect drops git stderr if the worktree has no branch — the basename fallback still yields a usable stream id
    lane_stream_id=$(cd "$worktree" && git rev-parse --abbrev-ref HEAD 2>/dev/null | grep -oE '^feat-[a-z0-9-]+' || true)
    [ -z "$lane_stream_id" ] && lane_stream_id=$(basename "$worktree")
  fi
  if [ -n "$lane_stream_id" ]; then
    mkdir -p "${SWARM_ROOT:-.}/.swarms/events"
    fin_json=$(jq -nc \
      --arg ts "$ts" \
      --arg sid "$lane_stream_id" \
      --arg status "${status:-unknown}" \
      --arg session_id "$session_id" \
      '{ts: $ts, stream_id: $sid, event: "lane.finished", payload: {status: $status, session_id: $session_id}}')
    # JUSTIFIED: the redirect drops write stderr — lane telemetry is best-effort; a write failure must never abort the SubagentStop hook
    printf '%s\n' "$fin_json" >> "${SWARM_ROOT:-.}/.swarms/events/${lane_stream_id}.jsonl" 2>/dev/null
  fi
fi

# ─── Emit structured event ──────────────────────────────────────────────
jq -nc \
  --arg ts "$ts" \
  --arg agent_type "$agent_type" \
  --arg session_id "$session_id" \
  --arg status "${status:-unknown}" \
  --arg handoff_path "${handoff_path:-}" \
  --arg files_modified "${files_modified:-}" \
  --arg worktree_diff "${worktree_diff:-}" \
  --argjson followup_count "${followup_count:-0}" \
  --argjson blockers_count "${blockers_count:-0}" \
  '{
    ts: $ts,
    agent_type: $agent_type,
    session_id: $session_id,
    status: $status,
    handoff_path: $handoff_path,
    files_modified: ($files_modified | split(",") | map(select(length > 0))),
    worktree_diff: ($worktree_diff | split(",") | map(select(length > 0))),
    followup_tasks_count: $followup_count,
    blockers_count: $blockers_count
    # JUSTIFIED: the redirect drops jq stderr — the subagent event log is best-effort telemetry; a write failure must never abort the SubagentStop hook
  }' >> .claude/hooks/.log/subagent.jsonl 2>/dev/null

# ─── Round 6 C: surface digest back to parent ───────────────────────────
# additionalContext flows into the parent's next prompt so the parent sees
# a structured digest instead of having to re-parse the subagent's prose.
digest_parts=()
[ -n "$status" ] && digest_parts+=("status=$status")
[ -n "$handoff_path" ] && digest_parts+=("handoff=$handoff_path")
[ -n "$archive_file" ] && digest_parts+=("archived=$archive_file")
[ -n "$files_modified" ] && digest_parts+=("files_modified=[$files_modified]")
[ -n "$worktree_diff" ] && digest_parts+=("worktree_diff=[$worktree_diff]")
[ "$followup_count" -gt 0 ] && digest_parts+=("followup_tasks=$followup_count")
[ "$blockers_count" -gt 0 ] && digest_parts+=("blockers=$blockers_count")
[ "$adr_missing" = "1" ] && digest_parts+=("WARN:adrs_referenced=EMPTY — persist the architect's decisions via 'bash .claude/scripts/adr-new.sh \"<title>\" --by architect' before planning (gap-audit G40)")

if [ "${#digest_parts[@]}" -gt 0 ]; then
  digest=$(IFS=' '; echo "${digest_parts[*]}")
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "[subagent-stop digest] $agent_type: $digest"
  }
}
EOF
elif [ "$soft_missing" = "1" ]; then
  # Gap-audit G38: the documented soft warning, made real.
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "[subagent-stop] WARN (soft): $agent_type returned no NEXUS handoff block — its findings exist only in prose and will not be archived to .claude/memory/handoffs/. Accepted, but ask for a \`\`\`nexus block next time (.claude/skills/handoff/SKILL.md)."
  }
}
EOF
fi

exit 0
