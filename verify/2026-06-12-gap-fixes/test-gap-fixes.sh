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

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
