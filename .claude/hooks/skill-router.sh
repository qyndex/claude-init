#!/usr/bin/env bash
# UserPromptSubmit hook. Detects keywords in user prompts and injects skill hints.
# v2 — expanded to ~25 trigger groups + 3-hint cap per Round-3 audit H-B3.
#
# This is a HINT-OVERLAY, not a routing layer — Claude can auto-trigger skills
# based on their description metadata regardless. This hook just surfaces the
# most relevant skills as system-reminders when keywords match, to nudge selection.

set -uo pipefail

input=$(cat)
# JUSTIFIED: jq stderr suppressed — malformed hook stdin yields empty prompt, handled by the [ -z ] guard below
prompt=$(printf '%s' "$input" | jq -r '.prompt // .user_prompt // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')

[ -z "$prompt" ] && exit 0

hints=()

case "$prompt" in *"autopilot"*|*"auto-pilot"*|*"ultrawork"*|*"ralph"*|*"unattended"*)
  hints+=(".claude/skills/autopilot/SKILL.md — 5-phase autonomous execution") ;;
esac
case "$prompt" in *"swarm"*|*"parallel features"*|*"fan out"*|*"in parallel"*|*"5 streams"*|*"10 streams"*)
  hints+=(".claude/skills/parallel-swarm/SKILL.md — coordinator-led multi-stream") ;;
esac
case "$prompt" in *"verify until"*|*"loop until"*|*"100% verified"*|*"keep going"*|*"verify-loop"*)
  hints+=(".claude/skills/verify-loop/SKILL.md — /loop with verification gate") ;;
esac
case "$prompt" in *"fix this"*|*"self-heal"*|*"auto-heal"*|*"make it pass"*|*"tests are red"*|*"flaky"*)
  hints+=(".claude/skills/self-heal/SKILL.md — 4-tier escalation") ;;
esac
case "$prompt" in *"tdd"*|*"red-green"*|*"failing test first"*|*"red green refactor"*)
  hints+=("superpowers:test-driven-development — strict red-green-refactor (plugin)") ;;
esac
case "$prompt" in *"debug "*|*" debug"*|*"what's wrong"*|*"why does this fail"*|*"root cause"*|*"reproduce"*)
  hints+=("superpowers:systematic-debugging — 4-phase root-cause (plugin)") ;;
esac
case "$prompt" in *"dream"*|*"consolidate memory"*|*"clean up memory"*|*"compact memory"*)
  hints+=("/dream (plugin) or bash .claude/skills/dream-trigger.sh") ;;
esac
case "$prompt" in *"context-budget"*|*"context budget"*|*"too many tokens"*|*"trim the harness"*|*"cost reducer"*|*"reduce tokens"*)
  hints+=(".claude/skills/context-budget/SKILL.md — inventory + prune") ;;
esac
case "$prompt" in *"spec out"*|*"write a spec"*|*"let's design"*|*"feature spec"*|*"prd"*)
  hints+=("/specify — Phase 2 of the 8-phase workflow") ;;
esac
case "$prompt" in *"clarify"*|*"open question"*|*"oq tags"*|*"resolve ambiguity"*)
  hints+=("/clarify — Phase 2.5, resolve [OQ]") ;;
esac
case "$prompt" in *"plan it"*|*"technical plan"*|*"design the implementation"*|*"how would you build"*)
  hints+=("/plan — Phase 3 technical plan") ;;
esac
case "$prompt" in *"break it into tasks"*|*"task list"*|*"decompose the plan"*|*"task breakdown"*)
  hints+=("/tasks — Phase 4 task decomposition") ;;
esac
case "$prompt" in *"analyze the plan"*|*"check consistency"*|*"any gaps"*|*"cross-check"*)
  hints+=("/analyze — Phase 4.5 cross-artifact gate") ;;
esac
case "$prompt" in *"implement"*|*"start coding"*|*"build it"*)
  hints+=("/implement — Phase 5, walks task DAG with TDD") ;;
esac
case "$prompt" in *"verify "*|*"did it work"*|*"is it done"*|*"test end-to-end"*)
  hints+=("/verify — Phase 6 verifier agent") ;;
esac
case "$prompt" in *"ship it"*|*"open the pr"*|*"merge"*|*"deploy"*|*"release"*|*"send the pr"*)
  hints+=("/ship — Phase 8") ;;
esac
case "$prompt" in *"code review"*|*"review the diff"*|*"lgtm"*|*"any issues"*)
  hints+=("/review — reviewer + security agents") ;;
esac
case "$prompt" in *"security review"*|*"audit"*|*"is this safe"*|*"check for vulns"*|*"owasp"*|*"semgrep"*|*"codeql"*)
  hints+=(".claude/skills/security-guard/SKILL.md + semgrep + codeql") ;;
esac
case "$prompt" in *"test in browser"*|*"e2e"*|*"open the app and try"*|*"playwright"*|*"chrome devtools"*|*"ui test"*|*"did the ui work"*)
  hints+=(".claude/skills/browser-e2e/SKILL.md + webapp-testing plugin") ;;
esac
case "$prompt" in *"which library"*|*"compare options"*|*"research "*|*" research"*|*"compare y vs z"*|*"best way to"*|*"evaluate"*)
  hints+=("/research — parallel sub-researcher fan-out") ;;
esac
case "$prompt" in *"handoff"*|*"status report"*|*"what did you do"*|*"next session"*|*"hand off"*)
  hints+=(".claude/skills/handoff/SKILL.md — NEXUS schema") ;;
esac
case "$prompt" in *"lesson learned"*|*"postmortem"*|*"capture what we learned"*|*"adr"*|*"decision record"*|*"incident"*)
  hints+=("/lesson-learned — incidents / decisions / patterns / playbooks") ;;
esac
case "$prompt" in *"create a skill"*|*"new skill"*|*"author a skill"*|*"build a skill"*)
  hints+=("/create-skill <slug> \"<desc>\" — native skill-creator (Round 9 A); writes to .claude/memory.proposed/skills/ for review") ;;
esac
case "$prompt" in *"create an agent"*|*"new agent"*|*"create-agent"*|*"new subagent"*|*"build an agent"*)
  hints+=("/create-agent — scaffolds .claude/agents/<tier>/<name>.md") ;;
esac
case "$prompt" in *"build an mcp"*|*"new mcp"*|*"mcp server"*|*"author mcp"*)
  hints+=("/plugin install mcp-builder@claude-plugins-official") ;;
esac
case "$prompt" in *"brainstorm"*|*"think through"*|*"explore options"*|*"throw ideas"*)
  hints+=("superpowers:brainstorming — design before code (plugin)") ;;
esac
case "$prompt" in *"prime me"*|*"load context"*|*"refresh state"*|*"prime discipline"*)
  hints+=("/prime — load project context") ;;
esac
case "$prompt" in *"what's the state"*|*"current status"*|*"what's happening"*|*"swarm status"*)
  hints+=("/status — branch, dirty, active spec/plan, CI") ;;
esac
case "$prompt" in *"onboard"*|*"new team member"*|*"first time"*|*"orient me"*)
  hints+=("/onboard — 10-min interactive walkthrough") ;;
esac
case "$prompt" in *"worktree"*|*"isolated workspace"*|*"feat branch"*)
  hints+=("superpowers:using-git-worktrees + native claude -w") ;;
esac
case "$prompt" in *"should i delegate"*|*"six gates"*|*"subagent criteria"*|*"dispatch criteria"*)
  hints+=(".claude/skills/dispatch-criteria/SKILL.md — six gates") ;;
esac

# Done? Bail.
[ ${#hints[@]} -eq 0 ] && exit 0

# Cap at 3 hints to avoid noise.
if [ ${#hints[@]} -gt 3 ]; then
  hints=( "${hints[@]:0:3}" )
fi

hint_text=$(IFS=' | '; echo "${hints[*]}")

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "[skill-router v2] Consider: $hint_text"
  }
}
EOF

exit 0
