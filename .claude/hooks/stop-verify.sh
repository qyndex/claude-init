#!/usr/bin/env bash
# Stop hook. Reminds Claude to verify before claiming done, when the session
# has produced uncommitted changes touching production code.
# Also enforces NEXUS handoff for coordinator sessions (AC-3).

set -uo pipefail

# Fail-closed jq preamble (e2e-audit hooks-engineering-4): this gate parses the
# Stop payload (stop_hook_active, agent type) with jq — without it the gate
# cannot reason about re-entry and must not silently pass.
if ! command -v jq >/dev/null 2>&1; then
  echo "stop-verify.sh: jq is not installed; the verification gate fails CLOSED. Install jq (brew install jq)." >&2
  exit 2
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# ─── AC-3: coordinator NEXUS enforcement at Stop time ───────────────────
# A coordinator may be launched directly (claude --bg --agent coordinator),
# in which case the Stop hook fires — not SubagentStop. Re-run the same
# NEXUS block check that subagent-stop.sh performs for coordinator subagents.
input_json=$(cat)
agent_type=$(printf '%s' "$input_json" | jq -r '.tool_input.subagent_type // .agent_type // ""' 2>/dev/null || true)

# ─── e2e-audit autopilot-3: livelock breaker ────────────────────────────
# When this hook blocks a Stop, Claude Code re-invokes the agent and the next
# Stop carries stop_hook_active=true. An agent that CANNOT satisfy the gate
# (e.g. verify needs an operator-only artifact) would loop forever in auto
# mode. Policy: strict on the first pass; on re-entry with stop_hook_active
# (or after 3 consecutive blocks in this session per the blocks log) let the
# Stop through but append a loud ESCALATION line to OVERNIGHT_REPORT.md so the
# morning operator cannot miss it.
stop_hook_active=$(printf '%s' "$input_json" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)
session_id=$(printf '%s' "$input_json" | jq -r '.session_id // ""' 2>/dev/null || true)
escalate_instead_of_block=0
if [ "$stop_hook_active" = "true" ]; then
  escalate_instead_of_block=1
elif [ -n "$session_id" ] && [ -f .claude/state/stop-verify-blocks.log ]; then
  # JUSTIFIED: grep -c on a missing/empty log yields 0 via the fallback — absence of prior blocks is the normal case
  prior_blocks=$(grep -c "	session=${session_id}	" .claude/state/stop-verify-blocks.log 2>/dev/null || echo 0)
  [ "${prior_blocks:-0}" -ge 3 ] && escalate_instead_of_block=1
fi
# Detect coordinator by agent_type field or by session context marker.
# CLAUDE_AGENT_TYPE is set by the coordinator's session; fall back to checking
# the current .swarms/coordinator/ state.
if [ "${agent_type}" = "coordinator" ] || [ "${CLAUDE_AGENT_TYPE:-}" = "coordinator" ]; then
  final_msg=$(printf '%s' "$input_json" | jq -r '.tool_response.final_message // .tool_response.content // ""' 2>/dev/null || true)
  if [ -n "$final_msg" ]; then
    yaml_block=$(printf '%s' "$final_msg" | awk '
      /^```(nexus|yaml)$/ { in_block=1; next }
      /^```$/ && in_block { in_block=0 }
      in_block { print }
    ')
    nexus_fail=""
    if [ -z "$yaml_block" ]; then
      nexus_fail='coordinator Stop without NEXUS handoff block. Emit a ```nexus or ```yaml block per .swarms/templates/handoff.yaml before stopping.'
    elif [ -f .claude/scripts/validate-handoff.sh ] \
      && ! printf '%s' "$yaml_block" | bash .claude/scripts/validate-handoff.sh --stdin >/dev/null 2>&1; then
      nexus_fail='coordinator Stop with INVALID NEXUS handoff. Re-emit with all required fields per .swarms/templates/handoff.yaml.'
    fi
    if [ -n "$nexus_fail" ]; then
      if [ "$escalate_instead_of_block" = "1" ]; then
        # Livelock breaker (autopilot-3): same policy as the verify gate below.
        {
          echo ""
          echo "## ⚠ ESCALATION ($(date -Iseconds)) — coordinator stopped without a valid NEXUS handoff"
          echo "- reason: $nexus_fail"
          echo "- session: ${session_id:-unknown}"
        } >> OVERNIGHT_REPORT.md 2>/dev/null || true
        echo "stop-verify: NEXUS gate unsatisfied after re-entry — allowing Stop, ESCALATION appended to OVERNIGHT_REPORT.md" >&2
      else
        # Stop-hook protocol: on exit 2 the harness surfaces STDERR to Claude; stdout is ignored.
        echo "$nexus_fail" >&2
        exit 2
      fi
    fi
  fi
fi

# JUSTIFIED: the redirect drops git stderr when not in a repo — guarded by the rev-parse check above, an empty result yields dirty=0 and a clean early exit
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$dirty" -eq 0 ]; then
  exit 0
fi

# Check if any production files changed
# Root CLAUDE.md is harness meta-documentation (same class as README/docs/), not production code.
# JUSTIFIED: the redirect drops git diff stderr and the fallback yields empty when grep matches nothing (exit 1) — empty prod_changed correctly means "no prod files touched" and triggers a clean exit
prod_changed=$(git diff --name-only HEAD 2>/dev/null | grep -Ev '^(specs/|plans/|tasks/|docs/|.claude/|.github/|verify/|README|CHANGELOG|CLAUDE.md)' | head -5 || true)

if [ -z "$prod_changed" ]; then
  exit 0
fi

# ─── Gap-audit G48: check report CONTENT, not just existence/recency ─────
# A REPORT.md with verdict FAIL (or for a different feature) used to satisfy
# this gate. Now: newest recent report must carry a PASS verdict, and if it
# names a feature, that feature must relate to this session's branch or
# touched specs. Blocks are logged so /harness-doctor can surface bypasses.
block() { # block <reason>
  mkdir -p .claude/state
  # JUSTIFIED: log write is best-effort telemetry — a failure must not mask the block itself
  printf '%s\tsession=%s\t%s\n' "$(date -Iseconds)" "${session_id:-unknown}" "$1" >> .claude/state/stop-verify-blocks.log 2>/dev/null
  if [ "$escalate_instead_of_block" = "1" ]; then
    # Livelock breaker (autopilot-3): re-entry or 3 strikes — allow the Stop,
    # escalate loudly instead of looping the agent against an unpassable gate.
    {
      echo ""
      echo "## ⚠ ESCALATION ($(date -Iseconds)) — stop-verify gate could not be satisfied"
      echo "- reason: $1"
      echo "- session: ${session_id:-unknown}"
      echo "- action needed: run /verify manually and inspect .claude/state/stop-verify-blocks.log"
    } >> OVERNIGHT_REPORT.md 2>/dev/null || true
    echo "stop-verify: gate unsatisfied after re-entry — allowing Stop, ESCALATION appended to OVERNIGHT_REPORT.md ($1)" >&2
    exit 0
  fi
  echo "$1 Run /verify before ending." >&2
  exit 2
}

recent_verify=""
if [ -d verify ]; then
  # JUSTIFIED: the redirect drops find stderr and the fallback yields empty if find errors or matches nothing — empty recent_verify correctly emits the "no recent verification" block
  recent_verify=$(find verify -name 'REPORT.md' -mtime -1 -print 2>/dev/null | sort -r | head -1 || true)
fi

if [ -z "$recent_verify" ]; then
  block "Production files changed but no recent verification report (verify/*/REPORT.md from the last 24h)."
fi

# Verdict must be PASS (case-insensitive on the label, strict on the value)
if ! grep -qiE '(verdict|result)[:* ]+.*PASS' "$recent_verify"; then
  block "Recent report $recent_verify does not carry a PASS verdict — a failing report is not verification."
fi

# Feature match: verify/<date>-<feature>/REPORT.md — if a feature slug is
# present, it must appear in the branch name or in a touched spec/plan path.
report_dir=$(basename "$(dirname "$recent_verify")")
feature=$(printf '%s' "$report_dir" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-?//')
if [ -n "$feature" ]; then
  # JUSTIFIED: git stderr suppressed — detached HEAD yields empty branch; the spec-path check below still applies
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  touched=$(git diff --name-only HEAD 2>/dev/null | grep -E '^(specs|plans)/' || true)
  if ! printf '%s\n%s\n' "$branch" "$touched" | grep -qiF "$feature"; then
    # Heuristic, so warn-strength only when the report is otherwise valid:
    # block ONLY if the session touched specs/plans for a clearly different feature.
    if [ -n "$touched" ]; then
      block "Recent report is for '$feature' but this session touched different spec/plan files — verify THIS feature."
    fi
  fi
fi

exit 0
