#!/usr/bin/env bash
# Per-gap verification rig for the 2026-06-12 gap-fix campaign.
# Each test names the gap it proves (G1..G63). Run from repo root:
#   bash verify/2026-06-12-gap-fixes/test-gap-fixes.sh
# Staged (operator-install) files are tested IN PLACE under staged/ — these
# tests prove the staged copy, then re-prove after install via INSTALLED=1.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
STAGED="verify/2026-06-12-gap-fixes/staged"
# INSTALLED=1 → test the live tree instead of the staged copies
HOOKS="$STAGED/.claude/hooks"
[ "${INSTALLED:-0}" = "1" ] && HOOKS=".claude/hooks"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  ✗ %s\n' "$1"; }
check(){ # check <desc> <expected-exit> <actual-exit>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want exit $2, got $3)"; fi
}

echo "── G1: cache hit-rate plumbing ──"
bash .claude/scripts/cost-report.sh month >/dev/null 2>&1
jq -e 'has("cache_read_tokens") and has("cache_creation_tokens") and has("cache_hit_rate")' \
  .claude/hooks/.log/cost-summary.json >/dev/null && ok "G1 cost-summary.json has cache fields" || bad "G1 cache fields missing"
grep -q 'cache:' .claude/statuslines/budget.sh && ok "G1 statusline reads cache_hit_rate" || bad "G1 statusline missing cache"
grep -q 'cache hit-rate' .claude/scripts/harness-doctor.sh && ok "G1 doctor has cache check" || bad "G1 doctor missing cache check"

echo "── G2: constitution guard covers .claude/skills/* (staged) ──"
out=$(printf '%s' '{"tool_input":{"file_path":".claude/skills/tdd-loop/SKILL.md"}}' | bash "$HOOKS/pre-edit-constitution-guard.sh" 2>/dev/null >/dev/null; echo $?)
check "G2 deny live SKILL.md write" 2 "$out"
out=$(printf '%s' '{"tool_input":{"file_path":".claude/memory.proposed/skills/foo/SKILL.md"}}' | bash "$HOOKS/pre-edit-constitution-guard.sh" >/dev/null 2>&1; echo $?)
check "G2 allow proposed-skill write" 0 "$out"
out=$(printf '%s' '{"tool_input":{"file_path":"src/app.ts"}}' | bash "$HOOKS/pre-edit-constitution-guard.sh" >/dev/null 2>&1; echo $?)
check "G2 allow normal write" 0 "$out"

echo "── G3: validate.sh env invariants ──"
v_out=$(bash .claude/scripts/validate.sh 2>/dev/null)
echo "$v_out" | grep -q 'ENABLE_TOOL_SEARCH=true' && ok "G3 validate checks ENABLE_TOOL_SEARCH" || bad "G3 ENABLE_TOOL_SEARCH check missing"
echo "$v_out" | grep -q 'CLAUDE_CODE_AUTO_COMPACT_WINDOW set' && ok "G3 validate checks AUTO_COMPACT_WINDOW" || bad "G3 AUTO_COMPACT_WINDOW check missing"

echo "── G4: stable per-turn injections (staged) ──"
upc_out=$(printf '{}' | bash "$HOOKS/user-prompt-context.sh" 2>/dev/null || true)
echo "$upc_out" | grep -q 'Dirty files: [0-9]' && bad "G4 user-prompt-context still emits raw dirty count" || ok "G4 dirty count bucketed"
echo "$upc_out" | grep -qE 'Tree: (clean|dirty)' && ok "G4 bucket label present" || bad "G4 bucket label missing"
grep -q 'streak=\$streak); see BREAK-LOOP' "$HOOKS/workflow-state.sh" && bad "G4 workflow-state still emits streak integer" || ok "G4 streak integer dropped from repeat reminder"

echo "── G5: cache-TTL advice actionable ──"
grep -q 'cache_control is an API-level parameter\|API-level parameter Claude Code does not expose' docs/RESEARCH.md && ok "G5 RESEARCH.md converted to actionable" || bad "G5 RESEARCH.md still unactionable"
grep -q 'TTL is ~5 minutes' .claude/skills/context-budget/SKILL.md && ok "G5 context-budget has TTL note" || bad "G5 context-budget missing TTL note"

echo "── G6/G36: spawn gate on Agent|Task matcher (staged settings) ──"
SETTINGS="$STAGED/.claude/settings.json"; [ "${INSTALLED:-0}" = "1" ] && SETTINGS=".claude/settings.json"
jq -e '.hooks.PreToolUse[] | select(.matcher=="Agent|Task") | [.hooks[].command] | any(contains("pre-spawn-cost-gate"))' "$SETTINGS" >/dev/null \
  && ok "G6 gate registered under Agent|Task" || bad "G6 gate not under Agent|Task"
jq -e . "$SETTINGS" >/dev/null && ok "G6 staged settings.json valid JSON" || bad "G6 staged settings invalid"
grep -q 'tool_name Agent/Task but is not registered' .claude/scripts/validate.sh && ok "G6 validate has matcher-coverage check" || bad "G6 validate check missing"

echo "── G7: output-side discipline ──"
[ "$(jq -r '.outputStyle' "$SETTINGS")" = "Concise" ] && ok "G7 staged outputStyle=Concise" || bad "G7 outputStyle not Concise"
grep -q 'CONTEXT_MONITOR_DELTA_WARN' "$HOOKS/context-monitor.sh" && ok "G7 per-turn output-growth monitor exists" || bad "G7 growth monitor missing"

echo "── G8: token-budget skill exists + refs resolve ──"
[ -f .claude/skills/token-budget/SKILL.md ] && ok "G8 token-budget skill on disk" || bad "G8 skill missing"
v8=$(bash .claude/scripts/validate.sh 2>/dev/null || true)
echo "$v8" | grep -q 'all referenced skill paths resolve' && ok "G8 no dangling skill refs" || bad "G8 dangling refs remain"

echo "── G9: context-fill monitor thresholds ──"
# the hook derives its repo root from its own path — staged copies root at staged/
t=/tmp/g9-transcript.jsonl
rm -f "$ROOT/.claude/state/context-monitor/g9sess.state" \
      "$STAGED/.claude/state/context-monitor/g9sess.state" 2>/dev/null
# keep rig state out of the staged install payload
trap 'rm -rf "$STAGED/.claude/state" 2>/dev/null' EXIT
head -c 1000000 /dev/zero | tr '\0' 'a' > "$t"
o=$(jq -nc --arg tp "$t" '{transcript_path:$tp, session_id:"g9sess"}' | bash "$HOOKS/context-monitor.sh")
echo "$o" | grep -q 'est. fill ~62%' && ok "G9 60% threshold fires" || bad "G9 60% threshold silent"
o2=$(jq -nc --arg tp "$t" '{transcript_path:$tp, session_id:"g9sess"}' | bash "$HOOKS/context-monitor.sh")
[ -z "$o2" ] && ok "G9 threshold fires once per session" || bad "G9 repeated warning"
head -c 1400000 /dev/zero | tr '\0' 'a' > "$t"
o3=$(jq -nc --arg tp "$t" '{transcript_path:$tp, session_id:"g9sess"}' | bash "$HOOKS/context-monitor.sh")
echo "$o3" | grep -q 'Compaction is close' && ok "G9 80% escalation fires" || bad "G9 80% escalation missing"
echo "$o3" | grep -q '\[output\] last turn grew' && ok "G7 output-growth warning fires" || bad "G7 growth warning missing"
jq -e '.hooks.UserPromptSubmit[0].hooks | [.[].command] | any(contains("context-monitor"))' "$SETTINGS" >/dev/null \
  && ok "G9 context-monitor registered in staged settings" || bad "G9 not registered"

echo "── G10: memory-gc wiring honest ──"
grep -q 'PreCompact hook' .claude/scripts/memory-gc.sh && bad "G10 header still claims PreCompact" || ok "G10 header fixed"
grep -q 'memory-gc.sh enforce' .claude/routines/gc-nightly.yml && ok "G10 gc-nightly runs memory-gc" || bad "G10 gc-nightly missing memory-gc"

echo "── G11: autonomous-context hardening (staged gate) ──"
big=$(head -c 20000 /dev/zero | tr '\0' 'x')
o=$(jq -nc --arg p "$big" '{tool_name:"Agent", tool_input:{prompt:$p}}' | CLAUDE_AUTOPILOT=1 bash "$HOOKS/pre-spawn-cost-gate.sh")
echo "$o" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null && ok "G11 16KB→deny under autopilot" || bad "G11 autopilot still ask"
o=$(jq -nc --arg p "$big" '{tool_name:"Agent", tool_input:{prompt:$p}}' | CLAUDE_AUTOPILOT=0 bash "$HOOKS/pre-spawn-cost-gate.sh")
echo "$o" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null && ok "G11 16KB→ask interactively" || bad "G11 interactive not ask"
huge=$(head -c 40000 /dev/zero | tr '\0' 'x')
o=$(jq -nc --arg p "$huge" '{tool_name:"Agent", tool_input:{prompt:$p}}' | bash "$HOOKS/pre-spawn-cost-gate.sh")
echo "$o" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null && ok "G11 32KB hard deny intact" || bad "G11 32KB ceiling broken"

echo "── G12/G13: candidate consumer + proposal preservation (staged dream hook) ──"
grep -q '_candidates.jsonl' "$HOOKS/auto-dream-check.sh" && ok "G12 dream hook consumes candidates" || bad "G12 no consumer"
grep -q 'skills_keep' "$HOOKS/auto-dream-check.sh" && ok "G13 dream mirror preserves skills/" || bad "G13 mirror still destroys proposals"
grep -q 'skills_keep' .claude/commands/dream-review.md && ok "G13 dream-review preserves skill queue" || bad "G13 dream-review still moves skills/"

echo "── G14/G15: generated router triggers ──"
[ -s .claude/state/skill-triggers.tsv ] && ok "G14 trigger table generated ($(wc -l < .claude/state/skill-triggers.tsv | tr -d ' ') rows)" || bad "G14 no trigger table"
cov=$(cut -f1 .claude/state/skill-triggers.tsv | sort -u | wc -l | tr -d ' ')
[ "$cov" -ge 40 ] && ok "G14 coverage: $cov skills (was ~25 static groups)" || bad "G14 coverage only $cov"
o=$(jq -nc '{prompt:"we need a codemod to migrate 80 call sites"}' | bash "$HOOKS/skill-router.sh")
echo "$o" | grep -q 'skills/codemod' && ok "G14 router matches previously-uncovered skill" || bad "G14 dynamic match failed"
grep -q 'triggers.yml' .claude/scripts/regen-skill-registry.sh && ok "G15 triggers.yml consumed by generator" || bad "G15 triggers.yml still dead"

echo "── G16: registry freshness ──"
grep -q 'regen-skill-registry' "$HOOKS/session-start-context.sh" && ok "G16 session-start regenerates registry" || bad "G16 no session-start regen"
v16=$(bash .claude/scripts/validate.sh 2>/dev/null || true)
echo "$v16" | grep -q 'REGISTRY.md fresh' && ok "G16 validate freshness check passes" || bad "G16 freshness check absent/stale"

echo "── G17: skill-use telemetry ──"
o=$(jq -nc '{tool_input:{skill:"tdd-loop"}}' | bash "$HOOKS/skill-use-log.sh"; echo $?)
[ "$o" = "0" ] && tail -1 .claude/hooks/.log/skill-use.jsonl | grep -q 'tdd-loop' && ok "G17 logger records Skill invocations" || bad "G17 logger broken"
jq -e '.hooks.PostToolUse[] | select(.matcher=="Skill")' "$SETTINGS" >/dev/null && ok "G17 Skill matcher in staged settings" || bad "G17 no Skill matcher"
bash .claude/scripts/harness-doctor.sh --json | jq -e '.[] | select(.check=="skill-use telemetry")' >/dev/null && ok "G17 doctor reports skill use" || bad "G17 doctor check missing"

echo "── G18: detector quality gates (staged) ──"
td=$(mktemp -d); mkdir -p "$td/.claude/hooks/.log" "$td/.claude/memory/.cache"
{ for i in 1 2 3; do printf '2026-06-12T0%d:00:01+10:00\texit=0\tnpm run build\n2026-06-12T0%d:00:02+10:00\texit=0\tnpm test --all\n2026-06-12T0%d:00:03+10:00\texit=0\tgit commit -m x\n' $i $i $i; done
  for i in 1 2 3; do printf '2026-06-12T1%d:00:01+10:00\texit=0\tnpm run build\n2026-06-12T1%d:00:02+10:00\texit=0\tnpm test --all\n2026-06-12T1%d:00:03+10:00\texit=0\tgit commit -m x\n' $i $i $i; done
} > "$td/.claude/hooks/.log/bash.log"
(cd "$td" && bash "$ROOT/$HOOKS/task-signature-detector.sh" 2>/dev/null || cd "$td" && bash "$ROOT/.claude/hooks/task-signature-detector.sh" >/dev/null 2>&1)
[ "${INSTALLED:-0}" = "1" ] && DET="$ROOT/.claude/hooks/task-signature-detector.sh" || DET="$ROOT/$STAGED/.claude/hooks/task-signature-detector.sh"
rm -rf "$td"; td=$(mktemp -d); mkdir -p "$td/.claude/hooks/.log" "$td/.claude/memory/.cache"
{ for i in 1 2 3; do printf '2026-06-12T0%d:00:01+10:00\texit=0\tnpm run build\n2026-06-12T0%d:00:02+10:00\texit=0\tnpm test --all\n2026-06-12T0%d:00:03+10:00\texit=0\tgit commit -m x\n' $i $i $i; done
  for i in 1 2 3; do printf '2026-06-12T1%d:00:01+10:00\texit=0\tnpm run build\n2026-06-12T1%d:00:02+10:00\texit=0\tnpm test --all\n2026-06-12T1%d:00:03+10:00\texit=0\tgit commit -m x\n' $i $i $i; done
} > "$td/.claude/hooks/.log/bash.log"
(cd "$td" && bash "$DET" >/dev/null 2>&1)
[ -s "$td/.claude/memory.proposed/skills/_candidates.jsonl" ] && ok "G18 multi-session clean pattern emits candidate" || bad "G18 no candidate emitted"
rm -rf "$td"; td=$(mktemp -d); mkdir -p "$td/.claude/hooks/.log" "$td/.claude/memory/.cache"
for i in 1 2 3 4 5 6; do printf '2026-06-12T01:0%d:01+10:00\texit=0\tnpm run build\n2026-06-12T01:0%d:02+10:00\texit=0\tnpm test --all\n2026-06-12T01:0%d:03+10:00\texit=0\tgit commit -m x\n' $i $i $i; done > "$td/.claude/hooks/.log/bash.log"
(cd "$td" && bash "$DET" >/dev/null 2>&1)
[ ! -s "$td/.claude/memory.proposed/skills/_candidates.jsonl" ] && ok "G18 single-session pattern rejected" || bad "G18 session gate missing"
rm -rf "$td"

echo "── G19: skill frontmatter checks in validate ──"
echo "$v16" | grep -q -- '-char cap' && ok "G19 description cap checked" || bad "G19 cap check missing"
echo "$v16" | grep -qE 'when_to_use' && ok "G19 when_to_use checked" || bad "G19 when_to_use check missing"

echo "── G20/G24: operational-command hints with user-runs framing (staged) ──"
o=$(jq -nc '{prompt:"we have an incident, prod is down"}' | bash "$HOOKS/skill-router.sh")
echo "$o" | grep -q 'incident-start' && ok "G20 incident routes to /incident-start" || bad "G20 incident misroute persists"
echo "$o" | grep -q 'suggest the user run' && ok "G24 user-runs framing present" || bad "G24 framing missing"
o=$(jq -nc '{prompt:"can you run a dependency audit"}' | bash "$HOOKS/skill-router.sh")
echo "$o" | grep -q 'deps-audit' && ok "G20 deps-audit discoverable" || bad "G20 deps-audit unhinted"
o=$(jq -nc '{prompt:"hooks not firing, harness feels broken"}' | bash "$HOOKS/skill-router.sh")
echo "$o" | grep -q 'harness-doctor' && ok "G20 harness-doctor discoverable" || bad "G20 harness-doctor unhinted"

echo "── G21: dangling /atlas hint ──"
grep -q '/atlas refresh' "$HOOKS/session-start-context.sh" && bad "G21 staged hook still says /atlas refresh" || ok "G21 dangling /atlas dropped (staged)"
grep -q 'dangling slash-command' .claude/scripts/validate.sh && ok "G21 validate checks hook-injected commands" || bad "G21 validate check missing"

echo "── G22: disable-model-invocation enforced ──"
echo "$v16" | grep -q 'all commands carry disable-model-invocation' && ok "G22 enforcement present + passing" || bad "G22 enforcement missing"

echo "── G23: DREAM-PENDING surfaced (staged) ──"
grep -q 'DREAM-PENDING' "$HOOKS/session-start-context.sh" && ok "G23 session-start surfaces pending dream" || bad "G23 still log-only"

echo "── G25: instinct extraction stage exists + gated + wired ──"
[ -x .claude/scripts/instinct-extract.sh ] && ok "G25 extractor script exists" || bad "G25 extractor missing"
grep -q 'instinct-extract.sh' "$HOOKS/auto-dream-check.sh" && ok "G25 Stop-hook trigger wired (staged)" || bad "G25 trigger unwired"
o=$(INSTINCT_EXTRACT_MIN=999999 DRY_RUN=1 bash .claude/scripts/instinct-extract.sh)
[ -z "$o" ] && ok "G25 below-threshold gate silent" || bad "G25 gate leaks"
o=$(DRY_RUN=1 bash .claude/scripts/instinct-extract.sh --force)
echo "$o" | grep -q 'instincts/active.yml' && ok "G25 --force emits extraction prompt" || bad "G25 force path broken"

echo "── G26: project→global promotion ──"
g26=$(mktemp -d)
printf -- '- id: g26-test\n  trigger: "g26 unique trigger"\n  action: "do the thing"\n  confidence: 0.9\n  status: project\n' > /tmp/g26-active.yml
cp /tmp/g26-active.yml .claude/memory/instincts/active.yml.g26bak 2>/dev/null || true
INSTINCT_GLOBAL_DIR="$g26" bash .claude/scripts/instinct-promote.sh auto >/dev/null 2>&1 || true
# run against the real active.yml? use isolated project instead:
p1=$(mktemp -d); p2=$(mktemp -d)
for p in "$p1" "$p2"; do mkdir -p "$p/.claude/scripts" "$p/.claude/memory/instincts"; cp .claude/scripts/instinct-promote.sh "$p/.claude/scripts/"; cp /tmp/g26-active.yml "$p/.claude/memory/instincts/active.yml"; done
rm -rf "$g26"; g26=$(mktemp -d)
(cd "$p1" && INSTINCT_GLOBAL_DIR="$g26" bash .claude/scripts/instinct-promote.sh auto >/dev/null)
grep -q 'status: candidate' "$g26/global.yml" && ok "G26 1st project → candidate" || bad "G26 candidate staging broken"
(cd "$p2" && INSTINCT_GLOBAL_DIR="$g26" bash .claude/scripts/instinct-promote.sh auto >/dev/null)
grep -q 'status: global' "$g26/global.yml" && ok "G26 2nd project → global (threshold)" || bad "G26 threshold broken"
[ -f .claude/commands/instinct.md ] && ok "G26 /instinct command exists" || bad "G26 /instinct missing"
rm -rf "$g26" "$p1" "$p2"; rm -f .claude/memory/instincts/active.yml.g26bak

echo "── G27/G33/G37/G38: subagent-stop persistence + bridge + soft warn (staged) ──"
SSTOP="$HOOKS/subagent-stop.sh"
td=$(mktemp -d); mkdir -p "$td/.claude/hooks/.log" "$td/.claude/scripts/lib" "$td/tasks"
cp .claude/scripts/findings-to-tasks.sh "$td/.claude/scripts/"
cp .claude/scripts/lib/tasks-lib.sh .claude/scripts/lib/with-lock.sh "$td/.claude/scripts/lib/" 2>/dev/null || true
printf '# Tasks\n\n## Active\n\n- [ ] T-001 | spec:001 | existing task | accept: true\n' > "$td/tasks/TASKS.md"
o=$(cd "$td" && jq -nc '{agent_type:"researcher", session_id:"s1", tool_response:{final_message:"just prose"}}' | bash "$ROOT/$SSTOP" 2>/dev/null)
[ "${INSTALLED:-0}" = "1" ] && o=$(cd "$td" && jq -nc '{agent_type:"researcher", session_id:"s1", tool_response:{final_message:"just prose"}}' | bash "$ROOT/.claude/hooks/subagent-stop.sh" 2>/dev/null)
echo "$o" | grep -q 'WARN (soft)' && ok "G38 soft agent missing-handoff warns" || bad "G38 soft warn missing"
grep -q 'missing_handoff_soft' "$td/.claude/hooks/.log/subagent.log" && ok "G38 soft miss logged" || bad "G38 log missing"
nexus_msg=$(printf 'did work\n```yaml\nstatus: complete\nfollowup_tasks:\n  - "add retry to the http client"\n  - "document the cache flag"\nfiles_modified:\n  - path: src/a.ts\n```\ndone')
o=$(cd "$td" && jq -nc --arg m "$nexus_msg" '{agent_type:"researcher", session_id:"s2", tool_response:{final_message:$m}}' | bash "$ROOT/$SSTOP" 2>/dev/null)
echo "$o" | grep -q 'archived=' && ok "G27/G33 handoff archived to memory" || bad "G27/G33 no archive"
ls "$td"/.claude/memory/handoffs/*/*researcher.yaml >/dev/null 2>&1 && ok "G33 archive file on disk" || bad "G33 archive file missing"
grep -q 'add retry to the http client' "$td/tasks/TASKS.md" && ok "G37 followup_tasks → TASKS.md" || bad "G37 bridge broken"
rm -rf "$td"

echo "── G31: router matches instinct triggers (staged) ──"
mkdir -p .claude/memory/instincts
g31bak=""
[ -f .claude/memory/instincts/active.yml ] && { g31bak=$(mktemp); cp .claude/memory/instincts/active.yml "$g31bak"; }
printf -- '- id: g31\n  trigger: "g31 magic phrase"\n  action: "use the g31 procedure"\n  confidence: 0.7\n' > .claude/memory/instincts/active.yml
o=$(jq -nc '{prompt:"please handle the g31 magic phrase case"}' | bash "$HOOKS/skill-router.sh")
echo "$o" | grep -q 'use the g31 procedure' && ok "G31 instinct action injected" || bad "G31 no injection"
printf -- '- id: g31\n  trigger: "g31 magic phrase"\n  action: "use the g31 procedure"\n  confidence: 0.4\n' > .claude/memory/instincts/active.yml
o=$(jq -nc '{prompt:"please handle the g31 magic phrase case"}' | bash "$HOOKS/skill-router.sh" || true)
echo "$o" | grep -q 'use the g31 procedure' && bad "G31 low-confidence leaked" || ok "G31 confidence <0.5 gated"
if [ -n "$g31bak" ]; then cp "$g31bak" .claude/memory/instincts/active.yml; rm -f "$g31bak"; else rm -f .claude/memory/instincts/active.yml; fi

echo "── G32: memory recall reaches subagents (staged) ──"
grep -q 'memory-recall.sh' "$HOOKS/subagent-context.sh" && ok "G32 subagent-context injects recall" || bad "G32 no recall injection"

echo "── G29: dream covers promote/learn scripts ──"
grep -q 'memory-promote.sh' .claude/skills/dream/SKILL.md && grep -q 'learn-from-success.sh' .claude/skills/dream/SKILL.md \
  && ok "G29 dream runs promote + learn-from-success" || bad "G29 dream steps missing"
grep -q 'instinct-extract.sh --force' .claude/skills/dream/SKILL.md && ok "G25 dream extraction step present" || bad "G25 dream step missing"
grep -q 'memory/handoffs' .claude/skills/dream/SKILL.md && ok "G33 dream gathers handoff archives" || bad "G33 gather step missing"

echo "── G30: learn-from-success data shapes ──"
grep -q 'claude-opus-4-7' .claude/scripts/learn-from-success.sh && bad "G30 stale model literal remains" || ok "G30 model prefix-matched"
grep -q 'subagent.jsonl' .claude/scripts/learn-from-success.sh && ok "G30 agent data from subagent.jsonl" || bad "G30 still reads nonexistent field only"

echo "── G34: agent memory-write contracts ──"
grep -q 'NEXUS handoff' "$STAGED/.claude/agents/core/architect.md" && ok "G34 architect contract routed via handoff (staged)" || bad "G34 architect unfixed"
grep -q 'NEXUS handoff' "$STAGED/.claude/agents/quality/reviewer.md" && ok "G34 reviewer contract routed via handoff (staged)" || bad "G34 reviewer unfixed"
grep -q 'NEXUS handoff' "$STAGED/.claude/agents/specialists/debugger.md" && ok "G34 debugger contract routed via handoff (staged)" || bad "G34 debugger unfixed"
grep -q 'claims memory writes but has no Write/Edit tool' .claude/scripts/validate.sh && ok "G34 validate guard present" || bad "G34 validate guard missing"

echo "── G35: delegation nudge ──"
rm -rf .claude/state/read-nudge
for i in 1 2 3 4 5 6 7; do jq -nc '{session_id:"g35t"}' | bash "$HOOKS/read-volume-nudge.sh" >/dev/null; done
o=$(jq -nc '{session_id:"g35t"}' | bash "$HOOKS/read-volume-nudge.sh")
echo "$o" | grep -q 'delegation' && ok "G35 nudge fires at threshold" || bad "G35 no nudge"
o=$(jq -nc '{session_id:"g35t"}' | bash "$HOOKS/read-volume-nudge.sh")
[ -z "$o" ] && ok "G35 silent between thresholds" || bad "G35 noisy"
rm -rf .claude/state/read-nudge
jq -e '.hooks.PostToolUse[] | select(.matcher=="Read")' "$SETTINGS" >/dev/null && ok "G35 Read matcher registered (staged)" || bad "G35 unregistered"

echo "── G39/G43/G44: ADR creation pipeline ──"
adr_out=$(bash .claude/scripts/adr-new.sh "rig smoke decision" --by architect --subsystem testing 2>/dev/null)
if [ -n "$adr_out" ] && [ -f "$adr_out" ]; then
  ok "G39 adr-new.sh creates auto-numbered ADR"
  grep -q '^- \*\*written_by\*\*: architect' "$adr_out" && ok "G43 written_by stamped" || bad "G43 written_by not stamped"
  grep -q '<session-id>' "$adr_out" && bad "G43 source_session placeholder survives" || ok "G43 source_session resolved (no placeholder)"
  grep -qE '^- \*\*Date\*\*: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$adr_out" && ok "G39 Date stamped" || bad "G39 Date placeholder survives"
  grep -q '^- \*\*subsystem\*\*: testing' "$adr_out" && ok "G44 subsystem grouping key stamped" || bad "G44 subsystem not stamped"
  rm -f "$adr_out"
else
  bad "G39 adr-new.sh failed to create an ADR"
fi
ls .claude/memory/decisions/0001-*.md .claude/memory/decisions/0002-*.md .claude/memory/decisions/0003-*.md >/dev/null 2>&1 \
  && ok "G39 foundational ADRs 0001-0003 backfilled" || bad "G39 backfill missing"
grep -q 'subsystem' .claude/memory/decisions/0000-template.md && ok "G44 template carries subsystem field" || bad "G44 template lacks subsystem"
grep -q 'ADR store non-vacuous\|adr-new.sh (gap-audit G39)' .claude/scripts/validate.sh && ok "G39 validate non-vacuous check present" || bad "G39 validate check missing"
grep -q 'adr-new.sh' .claude/skills/plan/SKILL.md && ok "G39 plan skill mandates ADR creation" || bad "G39 plan skill silent on ADRs"
grep -q 'adr-new.sh' .claude/skills/ship/SKILL.md && ok "G40 ship skill has ADR stop-rule" || bad "G40 ship skill silent on ADRs"

echo "── G40: adr-gate workflow + architect handoff warn (staged) ──"
GATE="$STAGED/.github/workflows/adr-gate.yml"; [ "${INSTALLED:-0}" = "1" ] && GATE=".github/workflows/adr-gate.yml"
[ -f "$GATE" ] && ok "G40 adr-gate.yml staged" || bad "G40 adr-gate.yml missing"
grep -q 'adr-surfaces.txt' "$GATE" 2>/dev/null && grep -q 'memory/decisions' "$GATE" 2>/dev/null \
  && ok "G40 gate wires surfaces list + decisions check" || bad "G40 gate logic incomplete"
[ -f .claude/adr-surfaces.txt ] && grep -qE '^[^#]' .claude/adr-surfaces.txt && ok "G40 adr-surfaces.txt has globs" || bad "G40 surfaces list missing/empty"
SSTOP="$STAGED/.claude/hooks/subagent-stop.sh"; [ "${INSTALLED:-0}" = "1" ] && SSTOP=".claude/hooks/subagent-stop.sh"
g40_msg='Design done.
```yaml
status: complete
adrs_referenced: []
files_modified:
  - path: docs/x.md
```'
touch /tmp/.g40-marker
o=$(jq -nc --arg m "$g40_msg" '{agent_type:"architect", session_id:"g40t", tool_response:{final_message:$m}}' | bash "$SSTOP" 2>/dev/null)
echo "$o" | grep -q 'WARN:adrs_referenced=EMPTY' && ok "G40 architect empty-ADR handoff warns parent" || bad "G40 no warn on empty adrs_referenced"
g40_msg2='Design done.
```yaml
status: complete
adrs_referenced:
  - ADR-0001
files_modified:
  - path: docs/x.md
```'
o=$(jq -nc --arg m "$g40_msg2" '{agent_type:"architect", session_id:"g40t", tool_response:{final_message:$m}}' | bash "$SSTOP" 2>/dev/null)
echo "$o" | grep -q 'WARN:adrs_referenced' && bad "G40 false warn despite cited ADR" || ok "G40 cited ADR passes clean"
find .claude/memory/handoffs -name '*-architect.yaml' -newer /tmp/.g40-marker -delete 2>/dev/null
rm -f /tmp/.g40-marker

echo "── G41: security disables require resolvable ADR ──"
g41dir=$(mktemp -d)
git -C "$g41dir" init -q
printf 'x = 1\n' > "$g41dir/app.py"
git -C "$g41dir" add app.py
git -C "$g41dir" -c user.email=rig@t -c user.name=rig commit -qm base
g41base=$(git -C "$g41dir" rev-parse HEAD)
printf 'import subprocess\n# JUSTIFICATION: rig fixture\n# ISSUE: #1\nx = subprocess.call("ls")  # nosec\n' > "$g41dir/app.py"
git -C "$g41dir" add app.py
git -C "$g41dir" -c user.email=rig@t -c user.name=rig commit -qm "add disable"
g41head=$(git -C "$g41dir" rev-parse HEAD)
(cd "$g41dir" && bash "$ROOT/.claude/scripts/lint-exception-check.sh" "$g41base" "$g41head" >/dev/null 2>&1); rc=$?
check "G41 nosec without ADR fails" 1 "$rc"
mkdir -p "$g41dir/.claude/memory/decisions"
printf '# ADR-0001: rig\n- **Status**: accepted\n' > "$g41dir/.claude/memory/decisions/0001-rig.md"
printf 'import subprocess\n# JUSTIFICATION: rig fixture\n# ISSUE: #1\n# ADR: 1\nx = subprocess.call("ls")  # nosec\n' > "$g41dir/app.py"
git -C "$g41dir" add -A
git -C "$g41dir" -c user.email=rig@t -c user.name=rig commit -qm "cite ADR"
g41head2=$(git -C "$g41dir" rev-parse HEAD)
(cd "$g41dir" && bash "$ROOT/.claude/scripts/lint-exception-check.sh" "$g41base" "$g41head2" >/dev/null 2>&1); rc=$?
check "G41 nosec with resolvable ADR passes" 0 "$rc"
rm -rf "$g41dir"

echo "── G42: adr-walk --reverify + chain walk ──"
awk '/^```bash$/{f=1;next} /^```$/{f=0} f' .claude/commands/adr-walk.md > /tmp/.g42-block.sh
g42dir=$(mktemp -d)
mkdir -p "$g42dir/.claude/memory/decisions"
printf '# ADR-0007: rig stale\n- **Status**: accepted\n- **Date**: 2020-01-01\n' > "$g42dir/.claude/memory/decisions/0007-rig-stale.md"
(cd "$g42dir" && bash /tmp/.g42-block.sh --reverify 7 >/dev/null 2>&1)
grep -qE "^- \*\*last_verified\*\*: [0-9]{4}-[0-9]{2}-[0-9]{2}" "$g42dir/.claude/memory/decisions/0007-rig-stale.md" \
  && ok "G42 --reverify stamps last_verified" || bad "G42 --reverify did not stamp"
printf '# ADR-0008\n- **Status**: superseded by ADR-0009\n' > "$g42dir/.claude/memory/decisions/0008-a.md"
printf '# ADR-0009\n- **Status**: superseded by ADR-0010\n' > "$g42dir/.claude/memory/decisions/0009-b.md"
printf '# ADR-0010\n- **Status**: accepted\n- **Date**: 2026-01-01\n' > "$g42dir/.claude/memory/decisions/0010-c.md"
o=$(cd "$g42dir" && bash /tmp/.g42-block.sh 2>/dev/null)
echo "$o" | grep -q 'ADR-0008 → ADR-0009 → ADR-0010' && ok "G42 chain walked end-to-end" || bad "G42 chain walk incomplete"
echo "$o" | grep -q 'left to manual' && bad "G42 stub text survives" || ok "G42 stub removed"
rm -rf "$g42dir" /tmp/.g42-block.sh

echo "── G45: ADR staleness from content dates (staged) ──"
SSC="$STAGED/.claude/hooks/session-start-context.sh"; [ "${INSTALLED:-0}" = "1" ] && SSC=".claude/hooks/session-start-context.sh"
grep -q 'find .claude/memory/decisions.*-mtime' "$SSC" && bad "G45 mtime heuristic survives" || ok "G45 mtime heuristic removed"
grep -q 'last_verified' "$SSC" && ok "G45 staleness reads content dates" || bad "G45 content-date logic missing"
printf '# ADR-9998: rig stale\n- **Status**: accepted\n- **Date**: 2020-01-01\n' > .claude/memory/decisions/9998-rig-stale.md
o=$(printf '{}' | bash "$SSC" 2>/dev/null || true)
echo "$o" | grep -q 'not verified in >12mo' && ok "G45 stale ADR surfaced at session start" || bad "G45 stale ADR not surfaced"
rm -f .claude/memory/decisions/9998-rig-stale.md
o=$(printf '{}' | bash "$SSC" 2>/dev/null || true)
echo "$o" | grep -q 'not verified in >12mo' && bad "G45 false positive on fresh store" || ok "G45 fresh store stays quiet"

echo "── G46: cross-model review gate ──"
CRW="$STAGED/.github/workflows/claude-review.yml"; [ "${INSTALLED:-0}" = "1" ] && CRW=".github/workflows/claude-review.yml"
grep -A1 'Run Claude code-reviewer' "$CRW" >/dev/null 2>&1 || true
awk '/jobs:/,0' "$CRW" | grep -m1 'model: claude-' | grep -q 'claude-sonnet' && ok "G46 CI reviewer runs Sonnet (≠ implementer Opus)" || bad "G46 CI reviewer still same-model"
CONST="$STAGED/.claude/CLAUDE.md"; [ "${INSTALLED:-0}" = "1" ] && CONST=".claude/CLAUDE.md"
grep -q 'Cross-model review' "$CONST" && ok "G46 §V documents cross-model rule" || bad "G46 §V silent"
o=$(REVIEW_WORKFLOW="$CRW" bash .claude/scripts/check-model-consistency.sh >/dev/null 2>&1; echo $?)
check "G46 checker passes on cross-model workflow" 0 "$o"
printf 'jobs:\n  review:\n    steps:\n      - with:\n          model: claude-opus-4-8\n' > /tmp/.g46-bad.yml
o=$(REVIEW_WORKFLOW=/tmp/.g46-bad.yml bash .claude/scripts/check-model-consistency.sh >/dev/null 2>&1; echo $?)
check "G46 checker fails on same-model workflow" 1 "$o"
rm -f /tmp/.g46-bad.yml

echo "── G47: commit trailers validated ──"
g47dir=$(mktemp -d)
git -C "$g47dir" init -q
git -C "$g47dir" -c user.email=rig@t -c user.name=rig commit -q --allow-empty -m base
g47base=$(git -C "$g47dir" rev-parse HEAD)
git -C "$g47dir" -c user.email=rig@t -c user.name=rig commit -q --allow-empty -m 'feat(x): no trailers here'
o=$( (cd "$g47dir" && bash "$ROOT/.claude/scripts/lint-trailers.sh" "$g47base" HEAD >/dev/null 2>&1); echo $?)
check "G47 commit without trailers fails" 1 "$o"
git -C "$g47dir" -c user.email=rig@t -c user.name=rig commit -q --allow-empty -m 'feat(y): good trailers

body

Confidence: high
Scope-risk: localized
Not-tested: edge cases'
g47mid=$(git -C "$g47dir" rev-parse HEAD~1)
o=$( (cd "$g47dir" && bash "$ROOT/.claude/scripts/lint-trailers.sh" "$g47mid" HEAD >/dev/null 2>&1); echo $?)
check "G47 valid trailers pass" 0 "$o"
git -C "$g47dir" -c user.email=rig@t -c user.name=rig commit -q --allow-empty -m 'feat(z): bad enum

Confidence: very-sure
Scope-risk: localized'
o=$( (cd "$g47dir" && bash "$ROOT/.claude/scripts/lint-trailers.sh" HEAD~1 HEAD >/dev/null 2>&1); echo $?)
check "G47 out-of-enum Confidence fails" 1 "$o"
git -C "$g47dir" -c user.email=rig@t -c user.name=rig commit -q --allow-empty -m 'WIP: six word decision checkpoint here now'
o=$( (cd "$g47dir" && bash "$ROOT/.claude/scripts/lint-trailers.sh" HEAD~1 HEAD >/dev/null 2>&1); echo $?)
check "G47 WIP checkpoints skipped" 0 "$o"
rm -rf "$g47dir"
CML="$STAGED/.github/workflows/commitlint.yml"; [ "${INSTALLED:-0}" = "1" ] && CML=".github/workflows/commitlint.yml"
grep -q 'lint-trailers.sh' "$CML" && ok "G47 commitlint workflow runs trailer lint" || bad "G47 workflow step missing"

echo "── G48: stop-verify checks report content ──"
SV="$STAGED/.claude/hooks/stop-verify.sh"; [ "${INSTALLED:-0}" = "1" ] && SV=".claude/hooks/stop-verify.sh"
grep -q 'resubmission to bypass' "$SV" && bad "G48 bypass still advertised" || ok "G48 bypass advertisement dropped"
g48dir=$(mktemp -d)
git -C "$g48dir" init -q
printf 'x=1\n' > "$g48dir/app.py"
git -C "$g48dir" add app.py
git -C "$g48dir" -c user.email=rig@t -c user.name=rig commit -qm base
printf 'x=2\n' > "$g48dir/app.py"   # dirty production file
o=$( (cd "$g48dir" && printf '{}' | bash "$ROOT/$SV" >/dev/null 2>&1); echo $?)
check "G48 no report → block" 2 "$o"
mkdir -p "$g48dir/verify/2026-06-12-widget"
printf '# Report\nVerdict: FAIL\n' > "$g48dir/verify/2026-06-12-widget/REPORT.md"
o=$( (cd "$g48dir" && printf '{}' | bash "$ROOT/$SV" >/dev/null 2>&1); echo $?)
check "G48 FAIL report → block (content checked)" 2 "$o"
printf '# Report\nVerdict: PASS\n' > "$g48dir/verify/2026-06-12-widget/REPORT.md"
o=$( (cd "$g48dir" && printf '{}' | bash "$ROOT/$SV" >/dev/null 2>&1); echo $?)
check "G48 PASS report → allow" 0 "$o"
[ -s "$g48dir/.claude/state/stop-verify-blocks.log" ] && ok "G48 blocks logged for doctor" || bad "G48 no block log"
rm -rf "$g48dir"
grep -q 'stop-verify blocks' .claude/scripts/harness-doctor.sh && ok "G48 doctor surfaces blocks" || bad "G48 doctor check missing"

echo "── G49: CI re-executes the proof ──"
EG="$STAGED/.github/workflows/evidence-gate.yml"; [ "${INSTALLED:-0}" = "1" ] && EG=".github/workflows/evidence-gate.yml"
grep -q 'Re-execute proof against head' "$EG" && ok "G49 re-execution step present" || bad "G49 still trusts committed evidence"
grep -q 'scripts/verify.sh' "$EG" && grep -q 'spec-match.sh' "$EG" && ok "G49 re-runs smoke + spec-match" || bad "G49 re-run incomplete"

echo "── G50: anti-slop ramp + multi-pass proxy ──"
grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' .claude/state/anti-slop-wirein.date && ok "G50 wire-in date recorded" || bad "G50 no wire-in date"
grep -q 'anti-slop ramp' .claude/scripts/harness-doctor.sh && ok "G50 doctor has dated ramp check" || bad "G50 doctor check missing"
d_out=$(bash .claude/scripts/harness-doctor.sh --json 2>/dev/null)
echo "$d_out" | jq -e '.[] | select(.check=="anti-slop ramp (30d)")' >/dev/null && ok "G50 ramp check executes" || bad "G50 ramp check broken"
grep -q 'anti-slop-triage' "$CRW" && bad "G50 duplicate anti-slop job survives in claude-review.yml" || ok "G50 anti-slop deduped to pr-review.yml"
grep -q 'Multi-pass: re-verified' "$CRW" && ok "G50 review format contract + lint present" || bad "G50 no mechanical pass-2 proxy"

echo "── G51/G53: spec-match requires PASSING tests + spec-bound results ──"
g51dir=$(mktemp -d)
mkdir -p "$g51dir/.claude/scripts" "$g51dir/specs/active" "$g51dir/verify/2026-06-12-099-widget"
cp .claude/scripts/spec-match.sh "$g51dir/.claude/scripts/"
printf '# Spec 099\n- **AC-1**: does a thing\n- **AC-2**: does another\n' > "$g51dir/specs/active/099-widget.md"
printf '{"suites":[{"specs":[{"ok":false,"tags":["@AC-1","@AC-2"],"title":"journey","tests":[{"results":[{"status":"failed"}]}]}]}]}\n' \
  > "$g51dir/verify/2026-06-12-099-widget/results.json"
o=$( (cd "$g51dir" && bash .claude/scripts/spec-match.sh 099 >/dev/null 2>&1); echo $?)
check "G51 failing tagged journey proves NOTHING" 1 "$o"
printf '{"suites":[{"specs":[{"ok":true,"tags":["@AC-1"],"title":"a","tests":[{"results":[{"status":"expected"}]}]},{"ok":true,"tags":["@AC-2"],"title":"b","tests":[{"results":[{"status":"passed"}]}]}]}]}\n' \
  > "$g51dir/verify/2026-06-12-099-widget/results.json"
o=$( (cd "$g51dir" && bash .claude/scripts/spec-match.sh 099 >/dev/null 2>&1); echo $?)
check "G51 passing tagged tests prove ACs" 0 "$o"
mkdir -p "$g51dir/verify/2026-01-01-088-other"
mv "$g51dir/verify/2026-06-12-099-widget/results.json" "$g51dir/verify/2026-01-01-088-other/results.json"
o=$( (cd "$g51dir" && bash .claude/scripts/spec-match.sh 099 >/dev/null 2>&1); echo $?)
check "G53 foreign-spec results.json not picked up (wildcard dropped)" 1 "$o"
rm -rf "$g51dir"

echo "── G54: story map is per-story + pass-checked ──"
g54dir=$(mktemp -d)
mkdir -p "$g54dir/specs/active" "$g54dir/e2e/077" "$g54dir/.claude/scripts"
cp .claude/scripts/story-test-map.sh "$g54dir/.claude/scripts/"
printf 'status: approved\n# Spec 077\n## User stories\n- As a user I want A so that X\n- As a user I want B so that Y\n## Next\n' > "$g54dir/specs/active/077-thing.md"
printf 'test\n' > "$g54dir/e2e/077/story-1.spec.ts"
printf 'test\n' > "$g54dir/e2e/077/unrelated.spec.ts"
o=$( (cd "$g54dir" && bash .claude/scripts/story-test-map.sh >/dev/null 2>&1); echo $?)
check "G54 one file no longer satisfies every story" 1 "$o"
printf 'test\n' > "$g54dir/e2e/077/story-2.spec.ts"
o=$( (cd "$g54dir" && bash .claude/scripts/story-test-map.sh >/dev/null 2>&1); echo $?)
check "G54 per-story files satisfy mapping (no results yet)" 0 "$o"
mkdir -p "$g54dir/verify/2026-06-12-077-thing"
printf '{"suites":[{"specs":[{"ok":true,"tags":["@story-1"],"title":"s1","tests":[{"results":[{"status":"passed"}]}]},{"ok":false,"tags":["@story-2"],"title":"s2","tests":[{"results":[{"status":"failed"}]}]}]}]}\n' \
  > "$g54dir/verify/2026-06-12-077-thing/results.json"
o=$( (cd "$g54dir" && bash .claude/scripts/story-test-map.sh >/dev/null 2>&1); echo $?)
check "G54 failing story-2 journey flips gate to FAIL" 1 "$o"
rm -rf "$g54dir"

echo "── G55: verify.sh runs the journey locally ──"
grep -q 'E2E journey gate' .claude/scripts/verify.sh && ok "G55 journey gate added to verify.sh" || bad "G55 verify.sh still skips the journey"
grep -q 'SKIP_E2E_JOURNEY' .claude/scripts/verify.sh && ok "G55 operator-gated skip registered" || bad "G55 no skip plumbing"
grep -q 'spec-match.sh' .claude/scripts/verify.sh && ok "G55 gate chains spec-match" || bad "G55 no AC proof in gate"

echo "── G53: evidence bound to commit + PR ──"
grep -q 'generated_at' .claude/scripts/collect-evidence.sh && grep -q 'ev_commit' .claude/scripts/collect-evidence.sh \
  && ok "G53 evidence.json stamps commit + timestamp" || bad "G53 no binding fields"
grep -q 'merge-base --is-ancestor' "$EG" && ok "G53 gate checks commit ancestry" || bad "G53 no ancestry check"
grep -q 'pr-changed-files' "$EG" && ok "G53 evidence must ride in the PR diff" || bad "G53 tree-wide evidence still accepted"
grep -q 'PR touches spec' "$EG" && ok "G53 spec binding asserted" || bad "G53 no spec binding"

echo "── G56: stop hook verdict/feature checks (same fix as G48) ──"
grep -q 'PASS verdict' "$SV" && ok "G56 verdict content required (see G48 functional proofs)" || bad "G56 verdict not checked"
grep -q 'report_dir' "$SV" && ok "G56 feature-match heuristic present" || bad "G56 any-feature report accepted"

echo "── G57: docs-only escape hatch works ──"
grep -q 'no-ac' "$EG" && grep -q 'nondocs' "$EG" && ok "G57 hatch implemented + scoped to docs-only diffs" || bad "G57 hatch still fictional"

echo "── G58: empty backlog → ideation branch ──"
g58dir=$(mktemp -d)
mkdir -p "$g58dir/.claude/scripts/lib" "$g58dir/tasks" "$g58dir/.claude/hooks/.log" "$g58dir/.claude/state"
cp .claude/scripts/loop-iteration.sh "$g58dir/.claude/scripts/"
cp .claude/scripts/lib/loop-state.sh "$g58dir/.claude/scripts/lib/"
git -C "$g58dir" init -q
git -C "$g58dir" -c user.email=rig@t -c user.name=rig commit -q --allow-empty -m base
git -C "$g58dir" checkout -qb feat-test
printf '# Tasks\n## Active\n- [x] T-001 done thing\n' > "$g58dir/tasks/TASKS.md"
o=$( (cd "$g58dir" && bash .claude/scripts/loop-iteration.sh 2>/dev/null) || true)
echo "$o" | grep -q 'IDEATE' && ok "G58 loop emits ideation instruction on empty backlog" || bad "G58 loop dies silently"
[ -f "$g58dir/.claude/state/ideation-pending" ] && ok "G58 ideation-pending flag set" || bad "G58 no flag for overnight report"
printf '# Tasks\n## Active\n- [ ] T-002 pending thing | accept: true\n' > "$g58dir/tasks/TASKS.md"
(cd "$g58dir" && bash .claude/scripts/loop-iteration.sh >/dev/null 2>&1) || true
[ -f "$g58dir/.claude/state/ideation-pending" ] && bad "G58 stale flag survives non-empty backlog" || ok "G58 flag cleared when backlog refills"
rm -rf "$g58dir"
grep -q 'IDEATION BRANCH' .claude/routines/overnight-build.yml && ok "G58 overnight END OF RUN has ideation branch" || bad "G58 overnight unchanged"
grep -q 'never auto-promote' .claude/routines/overnight-build.yml && ok "G58 human gate preserved (propose-only)" || bad "G58 auto-promotion risk"

echo "── G59: deterministic triage scorer + scheduled trigger ──"
g59dir=$(mktemp -d)
mkdir -p "$g59dir/fb"
printf -- '---\nid: FB-1\nseverity: P0\ncustomer:\n  arr_band: ENT\n  contract_renewal: %s\n---\n' "$(date -v+10d +%Y-%m-%d 2>/dev/null || date -d '+10 days' +%Y-%m-%d)" > "$g59dir/fb/FB-1.md"
printf -- '---\nid: FB-2\nseverity: P3\ncustomer:\n  arr_band: SMB\n---\n' > "$g59dir/fb/FB-2.md"
o=$(bash .claude/scripts/feedback-score.sh "$g59dir/fb" 2>/dev/null)
first=$(echo "$o" | sed -n 2p | cut -f2)
[ "$first" = "FB-1" ] && ok "G59 scorer ranks P0×ENT×renewal-soon first (score $(echo "$o" | sed -n 2p | cut -f1))" || bad "G59 ranking wrong (got $first)"
echo "$o" | sed -n 2p | grep -q '^96' && ok "G59 score deterministic (8×4×3=96)" || bad "G59 score formula drifted: $(echo "$o" | sed -n 2p | cut -f1)"
[ -f .claude/routines/feedback-triage.yml ] && ok "G59 weekly triage routine exists" || bad "G59 no scheduled trigger"
grep -q 'feedback-score.sh' .claude/commands/feedback.md && ok "G59 /feedback triage uses the scorer" || bad "G59 triage still LLM-ranked"

echo "── G61: revenue-signal honesty ──"
e61=$(bash .claude/scripts/feedback-score.sh "$g59dir/fb" 2>&1 >/dev/null)
[ -z "$e61" ] && ok "G61 no warning when ARR coverage fine" || bad "G61 false warning: $e61"
printf -- '---\nid: FB-3\nseverity: P2\n---\n' > "$g59dir/fb/FB-3.md"
printf -- '---\nid: FB-4\nseverity: P2\n---\n' > "$g59dir/fb/FB-4.md"
printf -- '---\nid: FB-5\nseverity: P2\n---\n' > "$g59dir/fb/FB-5.md"
e61=$(bash .claude/scripts/feedback-score.sh "$g59dir/fb" 2>&1 >/dev/null)
echo "$e61" | grep -q 'OPERATOR-SUPPLIED' && ok "G61 visible degradation when ARR mostly missing" || bad "G61 silent degradation"
rm -rf "$g59dir"
grep -q 'operator-supplied' .claude/commands/feedback.md && ok "G61 /feedback documents ARR provenance" || bad "G61 docs still imply automation"

echo "── G60: poll-routine honesty ──"
[ -f .claude/memory/feedback/active/.gitkeep ] && [ -f .claude/memory/feedback/closed/.gitkeep ] \
  && ok "G60 feedback dirs seeded" || bad "G60 active/closed dirs missing"
grep -q 'feedback intake wiring' .claude/scripts/harness-doctor.sh && ok "G60 doctor checks connector wiring" || bad "G60 no wiring check"
d60=$(bash .claude/scripts/harness-doctor.sh --json 2>/dev/null | jq -r '.[] | select(.check=="feedback intake wiring") | .status')
[ "$d60" = "warn" ] && ok "G60 doctor reports UNWIRED on factory default" || bad "G60 doctor status: ${d60:-absent}"
grep -q 'Wiring customer-feedback intake' docs/ADOPTION.md && ok "G60 ADOPTION documents the wiring step" || bad "G60 undocumented"

echo "── G62: research-grounded roadmap path (staged) ──"
RA="$STAGED/.claude/agents/core/roadmap-architect.md"; [ "${INSTALLED:-0}" = "1" ] && RA=".claude/agents/core/roadmap-architect.md"
grep -q 'RESEARCH BRIEF' "$RA" && ok "G62 researcher step in workflow" || bad "G62 no research mandate"
grep -q 'Research-grounded' "$RA" && ok "G62 Done-means checklist item" || bad "G62 not in Done means"

echo "── G63: feedback ↔ planning links ──"
grep -q '_triage-latest.md' .claude/commands/okrs.md && ok "G63 /okrs draft reads feedback registry" || bad "G63 okrs ignores feedback"
grep -q 'refs appended, never clobbered' .claude/commands/feedback.md && ok "G63 /feedback link appends refs" || bad "G63 link still clobbers"
g63f=$(mktemp)
printf -- '---\nid: FB-9\nspec_refs: [087]\n---\nbody\n' > "$g63f"
awk -v k="spec_refs" -v t="099" '
  BEGIN { fm=0; done=0 }
  /^---$/ { fm++; if (fm==2 && !done) { print k": ["t"]"; done=1 } print; next }
  !done && index($0, k":") == 1 {
    if (index($0, t)) { print; done=1; next }
    if (match($0, /\[[^]]*\]/)) {
      inner = substr($0, RSTART+1, RLENGTH-2)
      gsub(/^[ \t]+|[ \t]+$/, "", inner)
      if (inner == "") print k": ["t"]"
      else print k": ["inner", "t"]"
    } else {
      val = $0; sub("^"k":[ \t]*", "", val)
      if (val == "") print k": ["t"]"
      else print k": ["val", "t"]"
    }
    done=1; next
  }
  { print }
' "$g63f" | grep -q 'spec_refs: \[087, 099\]' && ok "G63 append logic keeps existing refs" || bad "G63 append logic broken"
rm -f "$g63f"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
