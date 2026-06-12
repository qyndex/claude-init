## G1 [high] Zero local cache hit-rate measurement — the metric the harness tells itself to watch does not exist anywhere
DIM: Prompt caching — prefix stability and cost measurement
FIX: null
EVIDENCE: .claude/statuslines/budget.sh:13-17 extracts only model/current_dir/total_cost_usd/context tokens — no cache fields. .claude/scripts/cost-report.sh:46 `total=$(... | jq '[.[].total_cost_usd] | add // 0')` and :52-59 awk matches only "total_cost_usd" — cache token fields in usage.jsonl are dropped. .claude/skills/context-budget/SKILL.md:4 `when_to_use: Context >60% full. Cache hit rate dropping.` docs/OBSERVABILITY.md:57 (cache_read_tokens exported, never consumed in-repo). docs/RESEARCH.md:155 (uninstalled tool citation). grep for cache_hit/cache_read across .claude/ and docs/ matches only those three doc/skill files — no executable code.

## G2 [medium] .claude/skills/* is the one §IX cache surface left unprotected by the constitution guard
DIM: Prompt caching — prefix stability and cost measurement
FIX: null
EVIDENCE: .claude/hooks/pre-edit-constitution-guard.sh:81-93 — deny case list contains `.claude/agents/*` and `.claude/rules/*` but no `.claude/skills/*`. .claude/settings.json:27 `"defaultMode": "acceptEdits"`; allow list (:37-68) has no Edit(.claude/skills/**) entry either way. .claude/CLAUDE.md §IX names 'skill frontmatter' explicitly.

## G3 [low] Cache-relevant env invariants are not validated
DIM: Prompt caching — prefix stability and cost measurement
FIX: null
EVIDENCE: grep -n 'ENABLE_TOOL_SEARCH|AUTO_COMPACT|cache' over .claude/scripts/validate.sh and .claude/scripts/harness-doctor.sh returns no env checks (only an unrelated .cache path filter at validate.sh:97 and a checkpoints path at harness-doctor.sh:113).

## G4 [low] Residual per-turn changing injections (dirty-file count; stuck-streak counter)
DIM: Prompt caching — prefix stability and cost measurement
FIX: null
EVIDENCE: .claude/hooks/user-prompt-context.sh:16,23 — `dirty=$(git status --porcelain | wc -l)` injected as '[harness] Branch: $branch | Dirty files: $dirty' every turn. .claude/hooks/workflow-state.sh:119-122 — `<warn>still stuck (streak=$streak); see BREAK-LOOP above</warn>` re-emitted with an incrementing number every stuck turn.

## G5 [low] Cache TTL knowledge is documented but has no operational hook
DIM: Prompt caching — prefix stability and cost measurement
FIX: null
EVIDENCE: docs/RESEARCH.md:150 — 'default dropped from 1h → 5min. For longer sessions, explicitly set cache_control: {"type":"ephemeral","ttl":"1h"}'. No corresponding mention in .claude/CLAUDE.md §IX or .claude/skills/context-budget/SKILL.md.

## G6 [high] Subagent prompt-size ceiling (32KB deny / 16KB ask) is dead code — pre-spawn-cost-gate.sh is not registered on the Agent|Task matcher
DIM: Context size optimization in long sessions (input AND output tokens), auto-compact without losing state
FIX: null
EVIDENCE: .claude/hooks/pre-spawn-cost-gate.sh:5-8, 22, 31-42 vs .claude/settings.json:431-450 (Bash matcher: pre-bash-guard, pre-spawn-cost-gate, pre-bash-dep-freshness) and 465-474 (Agent|Task matcher: subagent-context.sh only)

## G7 [medium] Output-token budget is purely advisory — no mechanical cap, monitor, or mid-session accounting of Claude's own output verbosity
DIM: Context size optimization in long sessions (input AND output tokens), auto-compact without losing state
FIX: null
EVIDENCE: .claude/settings.json:6 (outputStyle "Default"), 356-382 (env block — no output/thinking token caps); .claude/CLAUDE.md §IX (advisory only); .claude/skills/prime-discipline/SKILL.md:53-57 (manual-invoke); .claude/hooks/session-end.sh:49-57 (only token capture point, end-of-session, best-effort)

## G8 [medium] token-budget skill is referenced in five places but does not exist on disk
DIM: Context size optimization in long sessions (input AND output tokens), auto-compact without losing state
FIX: null
EVIDENCE: `test -d .claude/skills/token-budget` → MISSING; references at /Volumes/M/sourcecode/qyndex/claude-init/README.md:95, CLAUDE.md:72, docs/ARCHITECTURE.md:29, docs/RESEARCH.md:141, .claude/skills/prime-discipline/SKILL.md:53; full skills listing contains no token-budget entry

## G9 [medium] No mid-session context-fill monitor on the model side — the >60% trigger for context-budget is unwired and the only automatic response to context growth is the 400K auto-compact
DIM: Context size optimization in long sessions (input AND output tokens), auto-compact without losing state
FIX: null
EVIDENCE: .claude/skills/context-budget/SKILL.md:4 (trigger condition with no mechanical trigger); .claude/hooks/skill-router.sh:40-41 (keyword-only); .claude/statuslines/budget.sh:16-17,46-50 (display-only); no hook in .claude/hooks/ reads context token counts (verified across all 23 hooks listed)

## G10 [medium] memory-gc.sh's claimed wiring is partly aspirational — not run at PreCompact, no 03:30 cron, no >300-line SessionStart hard fail
DIM: Context size optimization in long sessions (input AND output tokens), auto-compact without losing state
FIX: null
EVIDENCE: .claude/scripts/memory-gc.sh:11-15 (claims) vs .claude/settings.json:539-550 (PreCompact = witness only), .claude/routines/gc-nightly.yml:14 (cron 30 2 * * *, scripts list at prompt lines 31-33 exclude memory-gc), .claude/routines/dream-cron.yml:15 (cron 0 3 * * *, no memory-gc), .claude/routines/quarterly-archive.yml:134-137 (only scheduled enforce), .claude/hooks/session-start-context.sh:117-123 (warn-only)

## G11 [low] The 16KB subagent-prompt warning would be a no-op in autonomous contexts even once wired — "ask" auto-resolves under Auto Mode
DIM: Context size optimization in long sessions (input AND output tokens), auto-compact without losing state
FIX: null
EVIDENCE: .claude/hooks/pre-spawn-cost-gate.sh:27-30 (self-acknowledged), 53-63 (16KB ask), 114-125 (90% ask); .claude/CLAUDE.md §X ("Auto Mode is the default in autopilot contexts")

## G12 [high] Auto-creation pipeline is broken at the middle link: nothing consumes _candidates.jsonl
DIM: Dimension 3 — Auto-discovery and auto-use of .claude/skills before tasks + auto-creation of new skills
FIX: null
EVIDENCE: .claude/hooks/task-signature-detector.sh:8-9 vs .claude/hooks/auto-dream-check.sh:1-93 (no _candidates/skill-creator reference); grep '_candidates' across .claude/**/*.sh returns only the detector itself

## G13 [high] Dream lifecycle destroys pending skill proposals and candidates (shared .claude/memory.proposed/ directory)
DIM: Dimension 3 — Auto-discovery and auto-use of .claude/skills before tasks + auto-creation of new skills
FIX: null
EVIDENCE: .claude/hooks/auto-dream-check.sh:55-65 (gate), 76-77 (rm -rf + cp); .claude/commands/dream-review.md:48-49 (--approve mv), :66-68 (--approve-skill path)

## G14 [medium] Router coverage is static and covers under half the skill catalogue
DIM: Dimension 3 — Auto-discovery and auto-use of .claude/skills before tasks + auto-creation of new skills
FIX: null
EVIDENCE: .claude/hooks/skill-router.sh:19-111 (full trigger list) vs `ls -d .claude/skills/*/` = 55 dirs; e.g. .claude/skills/db-migration, codemod, characterize have no corresponding case arm

## G15 [medium] skill-creator's triggers.yml output has no consumer — approved skills never enter the router
DIM: Dimension 3 — Auto-discovery and auto-use of .claude/skills before tasks + auto-creation of new skills
FIX: null
EVIDENCE: .claude/skills/skill-creator/SKILL.md:28,76 ('triggers.yml # phrase patterns for skill-router.sh') vs grep -rn 'triggers.yml' .claude --include='*.sh' → no matches

## G16 [medium] REGISTRY.md is generated but never loaded, and is stale (42 of 55 skills, 15 days old)
DIM: Dimension 3 — Auto-discovery and auto-use of .claude/skills before tasks + auto-creation of new skills
FIX: null
EVIDENCE: .claude/skills/REGISTRY.md:4 ('Last generated: 2026-05-28T03:10:51+10:00') + `grep -c '^| \`'` = 42 vs 55 dirs; grep 'skills/REGISTRY' across hooks/scripts/agents → empty; .claude/hooks/post-write-format.sh:75-80

## G17 [medium] No enforcement of skill use — hints are advisory with no adherence signal
DIM: Dimension 3 — Auto-discovery and auto-use of .claude/skills before tasks + auto-creation of new skills
FIX: null
EVIDENCE: .claude/hooks/skill-router.sh:5-7 ('HINT-OVERLAY, not a routing layer'); no PreToolUse/Stop hook in .claude/settings.json references skill invocation; workflow-state.sh only *suggests* self-heal in its loop-breaker text (line 110)

## G18 [low] task-signature-detector's documented quality gates are not implemented
DIM: Dimension 3 — Auto-discovery and auto-use of .claude/skills before tasks + auto-creation of new skills
FIX: null
EVIDENCE: .claude/hooks/task-signature-detector.sh:6,13-14 (claims) vs :33 (grep exit=0 only), :60 (count ≥5 only), :63-100 (no session logic despite comment)

## G19 [low] validate.sh does not enforce the 1536-char description cap or skill-creator's richer frontmatter
DIM: Dimension 3 — Auto-discovery and auto-use of .claude/skills before tasks + auto-creation of new skills
FIX: null
EVIDENCE: .claude/settings.json:23; .claude/scripts/validate.sh:152-160; .claude/commands/dream-review.md:71-73

## G20 [medium] Hint coverage is sparse: only ~7 of 55 commands have any auto-surfacing trigger
DIM: AUTO-USE of .claude/commands without explicit user invocation
FIX: null
EVIDENCE: .claude/hooks/skill-router.sh:79-105 (full command-hint set); .claude/commands/ directory listing (55 files); skill-router.sh:82-84 (*"incident"* → /lesson-learned, no /incident-start arm); no hook references "commands/" (grep -rn "commands/" .claude/hooks/*.sh returns nothing).

## G21 [medium] Dangling hint: session-start-context.sh suggests `/atlas refresh`, a command that does not exist
DIM: AUTO-USE of .claude/commands without explicit user invocation
FIX: null
EVIDENCE: .claude/hooks/session-start-context.sh:152 (`run \`bash .claude/scripts/atlas-refresh.sh\` or \`/atlas refresh\``); .claude/commands/ listing contains no atlas.md; .claude/skills/ listing contains no atlas/ (only mentions of the word inside other skills' SKILL.md bodies).

## G22 [medium] `disable-model-invocation: true` policy is documented but not mechanically enforced
DIM: AUTO-USE of .claude/commands without explicit user invocation
FIX: null
EVIDENCE: .claude/commands/README.md:14-16 (policy claim); .claude/scripts/validate.sh:136-141 (only `description:` checked for commands); current compliance verified by per-file scan (55/55 have the flag) — so this is a missing guard, not a present violation.

## G23 [medium] /dream-review unblock requirement is surfaced only in a log file, never in injected context
DIM: AUTO-USE of .claude/commands without explicit user invocation
FIX: null
EVIDENCE: .claude/hooks/auto-dream-check.sh:55-65 (review gate writes only to .claude/hooks/.log/dream.log and re-arms session count); grep -rn "memory.proposed\|dream-review" .claude/hooks/session-start*.sh returns nothing; gitStatus snapshot shows multiple pending .claude/memory.proposed/ entries.

## G24 [low] Injected hints name commands the model cannot invoke, with no "ask the user" framing
DIM: AUTO-USE of .claude/commands without explicit user invocation
FIX: null
EVIDENCE: .claude/hooks/skill-router.sh:86 (hints /create-skill, a disable-model-invocation command), :123-129 (injected as additionalContext to the model); .claude/hooks/session-start-context.sh:189 ("run `/adr-walk`"); .claude/commands/README.md:16 (flag blocks model invocation); .claude/commands/create-skill.md frontmatter (disable-model-invocation: true confirmed by scan).

## G25 [critical] Instinct extraction stage never runs — the pipeline is dead between observations and active.yml
DIM: Cross-agent and cross-session learning / knowledge sharing
FIX: null
EVIDENCE: .claude/skills/instinct/SKILL.md:41-48 vs settings.json Stop hook list (stop-verify.sh, auto-dream-check.sh, task-signature-detector.sh — full read of all three confirms none extracts); find across repo: no active.yml/global.yml; .claude/memory/instincts/ absent; observations.jsonl = 1,996 lines unconsumed

## G26 [high] Project → global instinct promotion (2+ projects) is purely aspirational
DIM: Cross-agent and cross-session learning / knowledge sharing
FIX: null
EVIDENCE: .claude/skills/instinct/SKILL.md:55-61 (promotion spec); grep for global.yml across .claude/scripts and .claude/hooks: zero hits outside SKILL.md; .claude/commands/ listing contains no instinct.md

## G27 [high] Subagent followup_tasks / decisions are counted, not persisted — child learnings die with the parent's context
DIM: Cross-agent and cross-session learning / knowledge sharing
FIX: null
EVIDENCE: .claude/CLAUDE.md §XV; .claude/skills/handoff/SKILL.md:107; .claude/hooks/subagent-stop.sh:51,175-196 (count-only); .claude/agents/core/coordinator.md:104 (prompt-only); grep for followup_tasks consumers in scripts/: none parse it

## G28 [medium] Skill-candidate consumption is documented as automatic but no consumer exists
DIM: Cross-agent and cross-session learning / knowledge sharing
FIX: null
EVIDENCE: .claude/hooks/task-signature-detector.sh:8-9 vs full read of .claude/hooks/auto-dream-check.sh (no _candidates reference); .claude/skills/skill-creator/SKILL.md:106; .claude/memory.proposed/skills/_candidates.jsonl exists (modified per git status)

## G29 [medium] memory-promote.sh and learn-from-success.sh run only via the optionally-installed desktop cron — not via the in-repo dream path
DIM: Cross-agent and cross-session learning / knowledge sharing
FIX: null
EVIDENCE: .claude/routines/dream-cron.yml:43-49 (sole caller; grep confirms learn-from-success.sh has no other caller); .claude/hooks/auto-dream-check.sh:81 (prompt omits both scripts); .claude/skills/dream/SKILL.md steps 1-8 (omits both); .claude/scripts/install-overnight-tasks.sh:29-31

## G30 [medium] learn-from-success.sh can never produce its routing insights: stale model id + no agent field writer
DIM: Cross-agent and cross-session learning / knowledge sharing
FIX: null
EVIDENCE: .claude/scripts/learn-from-success.sh:73 ('claude-opus-4-7'); .claude/hooks/session-end.sh:39-43 (jq adds only initiative/spec); .claude/scripts/cost-report.sh:62-69; usage.jsonl currently absent

## G31 [medium] skill-router.sh does not match instinct triggers despite the skill's claim
DIM: Cross-agent and cross-session learning / knowledge sharing
FIX: null
EVIDENCE: .claude/skills/instinct/SKILL.md:52-53 vs grep of .claude/hooks/skill-router.sh for instinct/active.yml: zero matches (only lines 37, 86 mention memory/skills)

## G32 [low] Implementer (and most worker agents) get no memory recall — shared learnings flow to reviewers but not to the code writer
DIM: Cross-agent and cross-session learning / knowledge sharing
FIX: null
EVIDENCE: grep -rln '.claude/memory' .claude/agents/ → implementer.md, planner.md, tester.md, verifier.md, researcher.md, coordinator.md, feature-stream.md absent from the list; .claude/hooks/subagent-context.sh:26-80 (no memory-recall injection); memory-recall.sh exists and is already injection-safe (≤5 short lines)

## G33 [high] Subagent handoff digests never reach persistent memory — only the parent's transcript
DIM: AUTO-USE of subagents for independent tasks WHILE ensuring memory gets updated from their work
FIX: null
EVIDENCE: Writer: .claude/hooks/subagent-stop.sh:196 (>> .claude/hooks/.log/subagent.jsonl). Consumers: grep -rn 'subagent.jsonl' across .claude/.github/docs matches ONLY subagent-stop.sh itself (plus worktree copies). Dream inputs: .claude/skills/dream/SKILL.md step 1 ('read .claude/memory/ topic files and every checkpoint under .claude/memory/.cache/checkpoints/') — no mention of subagent logs or handoffs; .claude/hooks/auto-dream-check.sh:81 prompt scope is memory.proposed + checkpoints only.

## G34 [high] Instructed memory write-back is mechanically impossible for the agents told to do it
DIM: AUTO-USE of subagents for independent tasks WHILE ensuring memory gets updated from their work
FIX: null
EVIDENCE: .claude/agents/core/architect.md:1-11 (tools list without Write/Edit/Bash, permissionMode: plan, isolation: worktree) vs :83 ('A new ADR is written to .claude/memory/decisions/'); .claude/agents/quality/reviewer.md:1-10 (tools: Read, Glob, Grep, Bash, TodoWrite; permissionMode: plan; 'Read-only') vs :73 ('a new pattern is written to .claude/memory/patterns/<slug>.md'); .claude/agents/specialists/debugger.md:1-11 vs :98 ('always logged in .claude/memory/incidents/'); worktree copies present at .claude/worktrees/agent-a73a316705ae5c627/

## G35 [medium] Delegation (auto-USE of subagents) is suggestion-only — no mechanical trigger or enforcement
DIM: AUTO-USE of subagents for independent tasks WHILE ensuring memory gets updated from their work
FIX: null
EVIDENCE: .claude/CLAUDE.md sec.IV (table + six gates, advisory text only); .claude/hooks/skill-router.sh:109-110 (the only mechanical surface: case match on the four literal phrases); no delegation logic in user-prompt-context.sh / session-start-context.sh (grep for delegate/Explore/subagent/dispatch returns only an unrelated witness warning)

## G36 [medium] Subagent prompt-size gate is dead code — wired on the wrong matcher
DIM: AUTO-USE of subagents for independent tasks WHILE ensuring memory gets updated from their work
FIX: null
EVIDENCE: .claude/hooks/pre-spawn-cost-gate.sh:8 ('Wired on Bash and Agent|Task matchers') and :22 (if [ "$tool_name" = "Agent" ] || [ "$tool_name" = "Task" ]); .claude/settings.json:431-449 (Bash matcher: pre-bash-guard, pre-spawn-cost-gate, pre-bash-dep-freshness) vs :466-474 (Agent|Task matcher: subagent-context.sh only); root CLAUDE.md hook-lifecycle table mirrors the same wiring.

## G37 [medium] Handoff followup_tasks -> TASKS.md bridge is LLM-mediated, not automated, and format-mismatched
DIM: AUTO-USE of subagents for independent tasks WHILE ensuring memory gets updated from their work
FIX: null
EVIDENCE: .claude/skills/handoff/SKILL.md ('followup_tasks becomes TASKS.md entries. findings-to-tasks.sh parses this list. Don't fake it.'); .claude/scripts/findings-to-tasks.sh:112 (input pattern: grep -E '^[- ]*\[ \]'); .claude/hooks/subagent-stop.sh:51 (only counts followups, never persists them); .claude/agents/core/coordinator.md:104 (prose instruction); .claude/commands/swarm/merge.md:53 (comment, not code)

## G38 [low] 'SOFT (warn, accept)' handoff enforcement does not actually warn
DIM: AUTO-USE of subagents for independent tasks WHILE ensuring memory gets updated from their work
FIX: null
EVIDENCE: .claude/hooks/subagent-stop.sh:79-93 (missing-block handling exists only for feature-stream|coordinator; no else/warn branch for other agents); .claude/CLAUDE.md sec.XV ('SOFT (warn, accept)'); .claude/skills/handoff/SKILL.md enforcement table ('free prose accepted with a warning')

## G39 [critical] Zero real ADRs exist — creation never happens, so the entire lifecycle runs on an empty set
DIM: Dimension 7 — Strict ADR lifecycle enforcement for every action
FIX: null
EVIDENCE: ls .claude/memory/decisions/ → only 0000-template.md; git log --oneline --all -- .claude/memory/decisions/ → single scaffold commit 780fa60; .claude/CLAUDE.md §V/§VII/§XVI document Round 5/10/11 architecture decisions with no corresponding ADR files.

## G40 [high] Nothing blocks an architectural change that lacks an ADR — enforcement is entirely LLM-judged prose
DIM: Dimension 7 — Strict ADR lifecycle enforcement for every action
FIX: null
EVIDENCE: grep -rn -i adr .claude/hooks/*.sh → only skill-router.sh:82 and session-start-context.sh:182-191, both informational; no workflow under .github/workflows/ references decisions/ except lint-exception-audit.yml which delegates to a script that doesn't check ADRs (see next gap).

## G41 [high] 'Security disables require an ADR' is aspirational — lint-exception-check.sh only echoes it, never verifies
DIM: Dimension 7 — Strict ADR lifecycle enforcement for every action
FIX: null
EVIDENCE: .claude/scripts/lint-exception-check.sh:45-69 (awk checks only JUSTIFICATION/ISSUE), :79 (ADR requirement is an echo in the error path only); root CLAUDE.md 'Commit format' section claims enforcement by lint-exception-audit.yml.

## G42 [medium] /adr-walk does not perform the re-verification it advertises — last_verified is never bumped and chain-walking is a stub
DIM: Dimension 7 — Strict ADR lifecycle enforcement for every action
FIX: null
EVIDENCE: .claude/commands/adr-walk.md:54-64 (stub chain walk + print-only recommendation), :66-77 (only mutation is archiving); .claude/memory/decisions/0000-template.md:17 ('bumped by /adr-walk'); .claude/scripts/memory-promote.sh:138-139.

## G43 [medium] ADR provenance fields are never populated — 'populated by hook' claim has no hook
DIM: Dimension 7 — Strict ADR lifecycle enforcement for every action
FIX: null
EVIDENCE: grep -rn source_session .claude/hooks/ → no matches (only .claude/scripts/memory-index.sh:87,105,120); .claude/memory/decisions/0000-template.md:15-16 claims hook-populated provenance.

## G44 [low] Dream contradiction detection keys on a 'subsystem:' frontmatter field the ADR template does not have
DIM: Dimension 7 — Strict ADR lifecycle enforcement for every action
FIX: null
EVIDENCE: .claude/skills/dream/SKILL.md:39-44 vs .claude/memory/decisions/0000-template.md (frontmatter lines 11-22 contain Tags but no subsystem field).

## G45 [low] Session-start staleness check uses file mtime, diverging from the frontmatter-date logic used everywhere else
DIM: Dimension 7 — Strict ADR lifecycle enforcement for every action
FIX: null
EVIDENCE: .claude/hooks/session-start-context.sh:186-187 (find -mtime +365 | xargs grep -L '^- \*\*last_verified\*\*:') vs .claude/commands/adr-walk.md:34-49 and .claude/scripts/memory-promote.sh:95-101 (frontmatter date parsing).

## G46 [high] Deep code review is same-model: Opus reviews Opus, in-session and in CI
DIM: Dimension 8 — Auto-verification of own work by a different model, fact-based, anti-overconfidence
FIX: null
EVIDENCE: .claude/agents/core/implementer.md:5 (model: opus); .claude/agents/quality/reviewer.md:5 (model: opus); .github/workflows/claude-review.yml:31 (model: claude-opus-4-8); .github/workflows/claude-security.yml:40 (model: claude-opus-4-8); .claude/CLAUDE.md §V ('Opus 4.8 → architect, implementer, reviewer, security...')

## G47 [medium] Confidence/Scope-risk/Not-tested commit trailers are mandated but never validated
DIM: Dimension 8 — Auto-verification of own work by a different model, fact-based, anti-overconfidence
FIX: null
EVIDENCE: .github/workflows/commitlint.yml:35,41 (only --extends '@commitlint/config-conventional'); .claude/CLAUDE.md §VI trailer block; root CLAUDE.md 'Conventional Commits with required trailers (enforced by commitlint.yml)'; grep 'Confidence:' hits only .claude/scripts/stale-deps/bump-loop.sh:107,144 (hardcoded 'high')

## G48 [medium] stop-verify.sh checks report existence/recency, not content — and self-documents its bypass
DIM: Dimension 8 — Auto-verification of own work by a different model, fact-based, anti-overconfidence
FIX: null
EVIDENCE: .claude/hooks/stop-verify.sh:52 (exclusion grep), 62 (find verify -name 'REPORT.md' -mtime -1 ... | head -1 — no content check), 66 (bypass instructions in the error message)

## G49 [medium] evidence.json is agent-committed and trusted; CI never re-runs the journey/smoke it attests
DIM: Dimension 8 — Auto-verification of own work by a different model, fact-based, anti-overconfidence
FIX: null
EVIDENCE: .github/workflows/evidence-gate.yml:44-57 (jq over committed file, no re-execution); .claude/scripts/collect-evidence.sh:65-77 (smoke run happens locally, output committed); .github/rulesets/main-protection.json:31-35 (e2e job not a required check)

## G50 [low] Reviewer's multi-pass re-verification is prompt-level only — no mechanical check that pass 2 happened
DIM: Dimension 8 — Auto-verification of own work by a different model, fact-based, anti-overconfidence
FIX: null
EVIDENCE: .claude/agents/quality/reviewer.md:21,48,64-66 (instructions only); .github/workflows/claude-review.yml:42,47-81 vs .github/workflows/pr-review.yml:1-41 (duplicate anti-slop pass, both advisory with no ramp tracking)

## G51 [critical] spec-match.sh never checks that the tagged test PASSED — a failing journey still 'proves' every AC
DIM: Dimension 9 — Task-completion verification from the end-user's perspective (run the product, capture evidence, prove 100% AC coverage)
FIX: null
EVIDENCE: .claude/scripts/spec-match.sh:40-43 — jq_prog='[.. | objects | select(.status? == "expected" or .status? == "passed")] as $ok | [.. | objects | select(.tags?)] | .[].tags[]?' — $ok is dead code; fallback at :47-50 greps raw AC ids with no status filter. Reproduced: jq run against {"specs":[{"tags":["AC-1"],"tests":[{"results":[{"status":"failed"}]}]}]} outputs AC-1. Collect-evidence consumes it at .claude/scripts/collect-evidence.sh:84-91.

## G52 [high] All journey evidence is self-attested by the agent; CI never independently runs the E2E journey on a PR
DIM: Dimension 9 — Task-completion verification from the end-user's perspective (run the product, capture evidence, prove 100% AC coverage)
FIX: null
EVIDENCE: .github/workflows/evidence-gate.yml:27-57 (grep + jq over committed files only). .github/workflows/ci.yml:107-117 (Lint/Typecheck/Unit/Integration steps; grep for 'playwright|verify.sh|spec-match|collect-evidence' across ci.yml and daily-batch.yml returned zero hits). .github/workflows/e2e-preview.yml:6-7 (on: deployment_status only). .github/rulesets/main-protection.json:30-36 (required checks: lint-test, review, security-review, harness-validate, evidence-gate — no e2e-preview, no playwright job).

## G53 [high] evidence-gate accepts a stale or wrong-spec evidence.json — no binding to the PR's spec or commits
DIM: Dimension 9 — Task-completion verification from the end-user's perspective (run the product, capture evidence, prove 100% AC coverage)
FIX: null
EVIDENCE: .github/workflows/evidence-gate.yml:46 (find verify -name evidence.json 2>/dev/null | sort -r | head -1 — no spec/SHA correlation). .claude/scripts/collect-evidence.sh:115-126 (evidence.json schema: spec, ac_total, ac_proven, ac_unproven, smoke_exit_max, coverage, verdict — no commit, no timestamp). .claude/scripts/spec-match.sh:27 (fallback 'verify/*/results.json' matches any feature's results).

## G54 [medium] story-test-map.sh's per-story mapping is fictional — one E2E file satisfies every story in the spec, and passing is never checked
DIM: Dimension 9 — Task-completion verification from the end-user's perspective (run the product, capture evidence, prove 100% AC coverage)
FIX: null
EVIDENCE: .claude/scripts/story-test-map.sh:63-67 (test_files=$(find e2e -path "e2e/${spec_id}*/*" -name '*.spec.*' ...) — ${story_num} appears nowhere in the search; only in the error hint at :76). Consumed by .claude/scripts/verify.sh:227-234.

## G55 [medium] The autonomous local gate (verify.sh) never executes the user journey — AC coverage is enforced only at PR time
DIM: Dimension 9 — Task-completion verification from the end-user's perspective (run the product, capture evidence, prove 100% AC coverage)
FIX: null
EVIDENCE: .claude/scripts/verify.sh — full read: stack test/coverage blocks at :78-185, Round-10 gates at :187-283; no playwright/spec-match/collect-evidence invocation anywhere (grep confirms). Constitution claim at .claude/CLAUDE.md §VII items 4 and 7.

## G56 [low] Stop hook accepts any REPORT.md regardless of verdict or feature
DIM: Dimension 9 — Task-completion verification from the end-user's perspective (run the product, capture evidence, prove 100% AC coverage)
FIX: null
EVIDENCE: .claude/hooks/stop-verify.sh:58-68 — recent_verify=$(find verify -name 'REPORT.md' -mtime -1 ...); only emptiness is checked, never the contents.

## G57 [low] evidence-gate's documented docs-only escape hatch (no-ac.json) does not work
DIM: Dimension 9 — Task-completion verification from the end-user's perspective (run the product, capture evidence, prove 100% AC coverage)
FIX: null
EVIDENCE: .github/workflows/evidence-gate.yml:46 (find verify -name evidence.json) vs :56 (error message referencing verify/<date>/no-ac.json). 'no-ac' appears nowhere else in .github/, .claude/scripts/, or docs/ (repo-wide grep).

## G58 [high] No empty-backlog -> ideate trigger anywhere in the autonomous loops
DIM: Dimension 10 — Auto-proposing the next high-value feature (revenue/customer-satisfaction driven, research-grounded) once current features are done
FIX: null
EVIDENCE: .claude/scripts/loop-iteration.sh:53-56 ('STOP no pending tasks'; exit 1); .claude/skills/verify-loop/SKILL.md:37-44 (stop conditions: 'No more unblocked tasks in tasks/TASKS.md'); .claude/routines/overnight-build.yml:161-165 ('Stop when ANY of: No more unblocked tasks...'); .claude/commands/feedback.md:5 and .claude/commands/roadmap.md:5 both set disable-model-invocation: true (human-invoked only); grep for 'ideate|propose next|backlog' across dream/SKILL.md, auto-dream-check.sh, render-overnight-report.sh found nothing

## G59 [medium] Triage — the actual ranking/proposal step — has no scheduled trigger and no deterministic scorer
DIM: Dimension 10 — Auto-proposing the next high-value feature (revenue/customer-satisfaction driven, research-grounded) once current features are done
FIX: null
EVIDENCE: .claude/commands/feedback.md:37 ('Runs weekly + on-demand') vs .claude/routines/ listing (no triage routine); feedback.md:129-130 (triage is 'claude -p --max-turns 20 --max-budget-usd 0.50 "Run feedback triage..."' — prompt-only); grep -i feedback .claude/scripts/validate.sh returned no matches

## G60 [medium] All feedback source connectors are disabled/unauthenticated out of the box, and the poll routine is a non-executable template
DIM: Dimension 10 — Auto-proposing the next high-value feature (revenue/customer-satisfaction driven, research-grounded) once current features are done
FIX: null
EVIDENCE: .claude/routines/feedback-poll.yml:34-39 (connectors: '- slack' with '# - fireflies / # - intercom / # - pendo' commented out); .mcp.json:303,315,327 (FIREFLIES_API_KEY/INTERCOM_ACCESS_TOKEN/PENDO_INTEGRATION_KEY all ':-' empty-default); ls .claude/memory/feedback/ shows only 0000-template.md; .claude/scripts/post-ship-close-feedback.sh:23 ('no $active — nothing to close')

## G61 [medium] No automated revenue signal — ARR/renewal data is hand-entered or aspirational Pendo metadata; OKR 'Today' values are static text
DIM: Dimension 10 — Auto-proposing the next high-value feature (revenue/customer-satisfaction driven, research-grounded) once current features are done
FIX: null
EVIDENCE: .claude/memory/feedback/0000-template.md:20-23 (arr_band/contract_renewal as manual frontmatter) and :33-34 ('P0 = imminent churn / revenue at risk'); .claude/agents/specialists/feedback-extractor.md:38 ('Customer ARR band from Pendo's account-attached metadata'); .mcp.json jq output: stripe appears only under _disabled_examples; OKRs.md:14-26 (hand-maintained 'Today' columns); no script under .claude/scripts/ touches ARR/revenue (grep -i 'revenue|ARR|MRR' across okrs.md/initiative.md/okr-align returned nothing)

## G62 [low] Proposal flow is not research-grounded by mandate — researcher is never invoked in the initiative/roadmap path
DIM: Dimension 10 — Auto-proposing the next high-value feature (revenue/customer-satisfaction driven, research-grounded) once current features are done
FIX: null
EVIDENCE: .claude/agents/core/roadmap-architect.md:46-65 (workflow reads OKRs.md, roadmap.md, decisions/, invokes grill-me — no researcher step); .claude/agents/specialists/researcher.md:3 (researcher exists for 'surveying competitor implementations'); .claude/commands/initiative.md:36-47 (--from-feedback path, corroboration bar only)

## G63 [low] /okrs draft ignores the feedback registry; /feedback link clobbers existing refs
DIM: Dimension 10 — Auto-proposing the next high-value feature (revenue/customer-satisfaction driven, research-grounded) once current features are done
FIX: null
EVIDENCE: .claude/commands/okrs.md:30-36 (/okrs draft input list — no feedback mention); .claude/commands/feedback.md:147-148 (sed full-line replace with comment 'simplistic — proper YAML editor preferred'); .claude/scripts/post-ship-close-feedback.sh:32 (grep on spec_refs is the closure mechanism that loses entries if clobbered)

