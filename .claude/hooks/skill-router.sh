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
# Gap-audit G20: "incident" used to misroute here (postmortem tool) — live
# incidents now route to /incident-start below; this arm keeps the
# after-the-fact phrases only.
case "$prompt" in *"lesson learned"*|*"postmortem"*|*"capture what we learned"*|*"adr"*|*"decision record"*)
  hints+=("suggest the user run /lesson-learned — incidents / decisions / patterns / playbooks (user-only command)") ;;
esac
# Gap-audit G20: high-value operational commands previously had zero discovery
# path. G24: framed as "suggest the user run" — these are disable-model-invocation
# commands the model cannot execute itself.
case "$prompt" in *"incident"*|*"outage"*|*"prod is down"*|*"production is down"*|*"sev1"*|*"sev 1"*)
  hints+=("suggest the user run /incident-start --severity P1|P2|P3 (user-only command) — IC assignment + incident doc + deploy/flag/error pull") ;;
esac
case "$prompt" in *"harness broken"*|*"hooks not firing"*|*"harness doctor"*|*"behavior feels off"*|*"harness health"*)
  hints+=("suggest the user run /harness-doctor (user-only command), or run: bash .claude/scripts/harness-doctor.sh") ;;
esac
case "$prompt" in *"triage"*|*"bug report"*|*"re-rank tasks"*|*"reprioritize"*|*"what should we work on"*)
  hints+=("suggest the user run /triage (user-only command) — re-rank pending tasks by priority + age + spec health") ;;
esac
case "$prompt" in *"dependency audit"*|*"outdated deps"*|*"vulnerable packages"*|*"audit dependencies"*|*"deps audit"*)
  hints+=("suggest the user run /deps-audit (user-only command) — outdated + vulnerable + low-quality packages") ;;
esac
case "$prompt" in *"brownfield"*|*"existing project"*|*"adopt this repo"*|*"legacy repo"*|*"bring under the framework"*)
  hints+=("suggest the user run /adopt start (user-only command) — six-phase brownfield adoption; see docs/ADOPTION.md") ;;
esac
case "$prompt" in *"create a skill"*|*"new skill"*|*"author a skill"*|*"build a skill"*)
  hints+=("suggest the user run /create-skill <slug> (user-only command) — native skill-creator; writes to .claude/memory.proposed/skills/ for review") ;;
esac
case "$prompt" in *"create an agent"*|*"new agent"*|*"create-agent"*|*"new subagent"*|*"build an agent"*)
  hints+=("suggest the user run /create-agent (user-only command) — scaffolds .claude/agents/<tier>/<name>.md") ;;
esac
case "$prompt" in *"build an mcp"*|*"new mcp"*|*"mcp server"*|*"author mcp"*)
  hints+=("/plugin install mcp-builder@claude-plugins-official") ;;
esac
case "$prompt" in *"brainstorm"*|*"think through"*|*"explore options"*|*"throw ideas"*)
  hints+=("superpowers:brainstorming — design before code (plugin)") ;;
esac
case "$prompt" in *"prime me"*|*"load context"*|*"refresh state"*|*"prime discipline"*)
  hints+=("suggest the user run /prime (user-only command) — load project context") ;;
esac
case "$prompt" in *"what's the state"*|*"current status"*|*"what's happening"*|*"swarm status"*)
  hints+=("suggest the user run /status (user-only command) — branch, dirty, active spec/plan, CI") ;;
esac
case "$prompt" in *"onboard"*|*"new team member"*|*"first time"*|*"orient me"*)
  hints+=("suggest the user run /onboard (user-only command) — 10-min interactive walkthrough") ;;
esac
case "$prompt" in *"worktree"*|*"isolated workspace"*|*"feat branch"*)
  hints+=("superpowers:using-git-worktrees + native claude -w") ;;
esac
case "$prompt" in *"should i delegate"*|*"six gates"*|*"subagent criteria"*|*"dispatch criteria"*)
  hints+=(".claude/skills/dispatch-criteria/SKILL.md — six gates") ;;
esac

# ─── Gap-audit G14/G15: generated trigger table ─────────────────────────
# .claude/state/skill-triggers.tsv (skill<TAB>phrase, lowercase) is emitted by
# regen-skill-registry.sh from skill frontmatter + triggers.yml files, so
# router coverage tracks the catalogue instead of this hand-written case list.
# cwd is the project root for hooks (matches the other relative paths here)
TRIGGERS_TSV=".claude/state/skill-triggers.tsv"
if [ -f "$TRIGGERS_TSV" ] && [ ${#hints[@]} -lt 3 ]; then
  seen_skills=" ${hints[*]:-} "
  while IFS=$'\t' read -r t_skill t_phrase; do
    [ -z "$t_skill" ] || [ -z "$t_phrase" ] && continue
    case "$prompt" in
      *"$t_phrase"*)
        # skip skills already hinted by the static arms
        case "$seen_skills" in *"/$t_skill/"*|*" $t_skill "*) continue ;; esac
        hints+=(".claude/skills/$t_skill/SKILL.md (matched: $t_phrase)")
        seen_skills="$seen_skills $t_skill "
        [ ${#hints[@]} -ge 3 ] && break
        ;;
    esac
  done < "$TRIGGERS_TSV"
fi

# ─── Gap-audit G31: instinct triggers (instinct/SKILL.md read path) ──────
# Match learned instincts (confidence ≥0.5 per the skill's own rule) against
# the prompt and inject the action just-in-time.
INSTINCTS=".claude/memory/instincts/active.yml"
if [ -s "$INSTINCTS" ] && [ ${#hints[@]} -lt 3 ]; then
  while IFS=$'\t' read -r i_trigger i_action i_conf; do
    [ -z "$i_trigger" ] || [ -z "$i_action" ] && continue
    awk -v c="$i_conf" 'BEGIN { exit !(c >= 0.5) }' || continue
    lt=$(printf '%s' "$i_trigger" | tr '[:upper:]' '[:lower:]')
    case "$prompt" in
      *"$lt"*)
        hints+=("[instinct] $i_action (learned; confidence $i_conf)")
        [ ${#hints[@]} -ge 3 ] && break
        ;;
    esac
  done < <(awk '
    /^- id:/ { if (trg != "") printf "%s\t%s\t%s\n", trg, act, conf; trg=""; act=""; conf="0" }
    /^[[:space:]]*trigger:/ { sub(/^[[:space:]]*trigger:[[:space:]]*/, ""); gsub(/"/, ""); trg=$0 }
    /^[[:space:]]*action:/  { sub(/^[[:space:]]*action:[[:space:]]*/, "");  gsub(/"/, ""); act=$0 }
    /^[[:space:]]*confidence:/ { sub(/^[[:space:]]*confidence:[[:space:]]*/, ""); conf=$0 }
    END { if (trg != "") printf "%s\t%s\t%s\n", trg, act, conf }
  ' "$INSTINCTS")
fi

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
