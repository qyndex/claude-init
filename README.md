# Claude Code Golden Harness

> A production-grade `.claude/` starter that any project team can drop into a repo to get an autonomous, spec-driven, TDD-first, verification-gated, security-aware agent system in 15 minutes.

[![Harness validate](https://img.shields.io/badge/harness-validated-brightgreen)](.github/workflows/harness-validate.yml)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-v2.1+-blue)](https://code.claude.com)
[![MCP](https://img.shields.io/badge/MCP-enabled-purple)](https://modelcontextprotocol.io)

## What this is

A complete agentic harness for Claude Code that includes:

- **A constitution** — `.claude/CLAUDE.md` — the agent's operating rules
- **An engineering team** — 10 specialized subagents under `.claude/agents/`
- **A workflow** — eight phases (constitute → specify → clarify → plan → tasks → analyze → implement → verify → review → ship), each a slash command
- **Disciplines** — TDD, verification-before-completion, browser E2E, security guard, token budget, auto-loop, research grounding
- **Memory system** — `.claude/memory/` with decisions, patterns, incidents, playbooks
- **Security guardrails** — `.claude/hooks/` block destructive commands, scan for secrets, audit dependencies
- **MCP servers** — `.mcp.json` pre-wired with filesystem, git, github, chrome-devtools, playwright, context7, postgres, sentry
- **CI/CD** — `.github/workflows/` with claude-code-action, claude-code-security-review, CI matrix, E2E on preview, auto-merge Dependabot, release-please
- **Templates** — `specs/templates/`, `plans/templates/` (Spec Kit-style)

## Quick start

```bash
# 1. Copy this folder into your project (or use as a template repo)
git -C path/to/claude-init archive HEAD | tar -x -C your-project/   # git-aware copy: tracked files only

# 2. Run setup (installs canonical plugins, configures hooks, validates)
cd your-project
bash .claude/scripts/setup.sh

# 3. Open Claude Code
claude

# 4. NEW TEAM MEMBER? Take the 10-min interactive tour
/onboard             # walks the eight-phase workflow with a concrete example

# 5. Otherwise: try the workflow yourself
/constitution        # set up project principles (once)
/specify "add user login with email + password"
/clarify             # resolve open questions
/plan                # technical plan
/tasks               # decompose into atomic tasks
/analyze             # consistency check
/implement all       # walk the DAG with strict TDD
/verify              # run the app, exercise the journey
/review              # code + security review
/ship                # PR, CI, merge, deploy
```

## Why this exists

Without a harness, every project's Claude Code setup is bespoke and forgettable. With this golden repo, every team that adopts it gets:

- The same eight-phase workflow
- The same security baselines
- The same observability (token usage, logs, snapshots)
- The same quality bar (TDD + verification + multi-pass review)
- The same shipping pipeline (claude-code-action + CI gates + auto-merge)

It's modeled on the consensus best practices from May 2026: github/spec-kit, obra/superpowers, anthropics/claude-plugins-official, anthropics/claude-code-action, chrome-devtools-mcp, playwright-mcp, Anthropic's own engineering blog posts on effective harnesses for long-running agents.

See [docs/RESEARCH.md](docs/RESEARCH.md) for the full reference list with GitHub links.

## What's in the box

```
.
├── .claude/
│   ├── CLAUDE.md                     # Project constitution (auto-loaded each session)
│   ├── settings.json                  # Team-shared permissions, hooks, env
│   ├── agents/
│   │   ├── core/                     # architect, planner, implementer, coordinator, feature-stream, roadmap-architect
│   │   ├── quality/                  # tester, reviewer, security, verifier, anti-slop-reviewer
│   │   └── specialists/              # debugger, researcher, doc-writer, release, designer, extractor, feedback-extractor
│   ├── skills/
│   │   ├── constitution/             # /constitution workflow
│   │   ├── specify/                  # /specify workflow
│   │   ├── clarify/                  # /clarify workflow
│   │   ├── plan/                     # /plan workflow
│   │   ├── tasks/                    # /tasks workflow
│   │   ├── analyze/                  # /analyze cross-artifact consistency
│   │   ├── implement/                # /implement (delegates to implementer)
│   │   ├── verify/                   # /verify (delegates to verifier)
│   │   ├── review/                   # /review (delegates to reviewer + security)
│   │   ├── ship/                     # /ship (delegates to release)
│   │   ├── loop/                     # /loop (autonomous run)
│   │   ├── debug/                    # /debug (delegates to debugger)
│   │   ├── research/                 # /research (delegates to researcher)
│   │   ├── tdd-loop/                 # TDD discipline (red-green-refactor)
│   │   ├── verification/             # verification-before-completion discipline
│   │   ├── browser-e2e/              # browser-driven E2E discipline
│   │   ├── security-guard/           # OWASP + LLM Top 10 checklist
│   │   ├── token-budget/             # cache/delegate/compact discipline
│   │   ├── auto-loop/                # safe autonomous-loop discipline
│   │   ├── research-grounding/       # evidence-based decisions
│   │   ├── spec-driven/              # spec→plan→tasks methodology
│   │   └── …                         # 58 skills total — ls .claude/skills/
│   ├── hooks/
│   │   ├── pre-bash-guard.sh         # block destructive bash
│   │   ├── pre-write-secret-scan.sh  # scan writes for secrets (gitleaks)
│   │   ├── post-write-format.sh      # auto-format after edits
│   │   ├── post-bash-log.sh          # audit-log every bash run
│   │   ├── user-prompt-context.sh    # inject branch/spec/plan context
│   │   ├── session-start.sh          # boot-time summary
│   │   ├── session-end.sh            # capture usage
│   │   ├── stop-verify.sh            # nudge to /verify before ending
│   │   ├── subagent-stop.sh          # log subagent runs
│   │   ├── pre-compact-witness.sh    # async witness brief on compaction (mvara-ai pattern)
│   │   ├── workflow-state.sh          # per-turn state + loop detection (ccg-workflow port)
│   │   ├── session-start-context.sh   # additional boot context
│   │   ├── subagent-context.sh        # PreToolUse on Agent/Task — injects spec
│   │   ├── skill-router.sh            # UserPromptSubmit — hint overlay
│   │   ├── auto-dream-check.sh        # Stop hook — triggers /dream every 24h
│   │   ├── instinct-observer.sh       # PostToolUse — appends to instinct log
│   │   └── …                          # 25 hooks total — ls .claude/hooks/
│   ├── memory/
│   │   ├── MEMORY.md                 # index of decisions / patterns / incidents / playbooks
│   │   ├── decisions/                # ADRs
│   │   ├── patterns/                 # reusable code patterns
│   │   ├── incidents/                # postmortems
│   │   └── playbooks/                # new-feature, flaky-test, rollback
│   ├── plugins/marketplace.json      # curated plugin marketplaces
│   ├── output-styles/                # concise (default), teaching
│   ├── statuslines/                  # budget statusline
│   └── scripts/                      # setup, validate, run, verify, lint, tests, loop
├── .mcp.json                          # pinned MCP servers
├── .github/
│   ├── workflows/
│   │   ├── claude.yml                # @claude mention handler
│   │   ├── claude-review.yml         # PR code review
│   │   ├── claude-security.yml       # PR security review + gitleaks + deps
│   │   ├── ci.yml                    # lint + typecheck + tests
│   │   ├── e2e-preview.yml           # Playwright on preview deploy
│   │   ├── auto-merge-dependabot.yml # auto-merge patch/minor
│   │   ├── release-please.yml        # Conventional Commits → CHANGELOG
│   │   ├── harness-validate.yml      # lint the .claude/ folder itself
│   │   └── …                         # 36 workflows total — ls .github/workflows/
│   ├── rulesets/main-protection.json # branch protection (Rulesets)
│   ├── ISSUE_TEMPLATE/               # bug, feature
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── CODEOWNERS
│   └── dependabot.yml
├── specs/templates/spec.md            # feature spec template
├── plans/templates/plan.md            # technical plan template
├── tasks/TASKS.md                     # append-only task ledger
└── docs/
    ├── README.md                      # this file
    ├── OPERATOR-MANUAL.md             # ⭐ how to RUN the factory (read this first)
    ├── STARTING-PROMPT.md             # the first prompt for a brand-new product (/kickoff)
    ├── ADOPTION.md                    # bring an EXISTING/legacy repo under the factory (/adopt)
    ├── ONBOARDING.md                  # 15-minute adoption guide
    ├── ARCHITECTURE.md                # how the pieces fit together
    ├── PLAYBOOK.md                    # operational recipes
    └── RESEARCH.md                    # the research that shaped every decision
```

## Run it (operators start here)

- **New to operating this factory?** Read [docs/OPERATOR-MANUAL.md](docs/OPERATOR-MANUAL.md) —
  mental model, a day in the life, the eight-phase workflow, the safety model, and a copy-paste
  runbook. ~20 minutes; anyone on the team can follow it.
- **Starting a brand-new product from zero?** Use [docs/STARTING-PROMPT.md](docs/STARTING-PROMPT.md)
  (or just type `/kickoff`): the factory interviews you, builds the roadmap, and delivers it
  end-to-end in safe phased increments.
- **Bringing an EXISTING / legacy project in?** Read [docs/ADOPTION.md](docs/ADOPTION.md) and run
  `/adopt`: six human-gated phases (archaeology → reconcile → import → baseline → backlog →
  handoff) that ingest the repo's docs, issues, and conventions and make it safe for autonomy
  (*no tests = no writes* on untested legacy).

## Adopt in an existing project

Read [docs/ONBOARDING.md](docs/ONBOARDING.md). Short version:

```bash
# From the repo root of your existing project:
git clone https://github.com/<your-org>/claude-init /tmp/claude-init
git -C /tmp/claude-init archive HEAD | tar -x -C .
bash .claude/scripts/setup.sh
```

## Customize per project

- Edit `.claude/CLAUDE.md` — tighten the constitution to your stack
- Edit `.claude/settings.json` — adjust the `allow`/`ask`/`deny` lists
- Edit `.mcp.json` — comment out servers you don't need, add ones you do
- Edit `.claude/scripts/run.sh` — match your project's start command
- Edit `.github/CODEOWNERS` — your team's handles
- Edit `.github/dependabot.yml` — your stacks

## Philosophy

This harness encodes three opinions:

1. **Spec before code.** No non-trivial change without a spec, plan, and task list.
2. **Evidence before assertion.** No task complete without machine-verifiable proof.
3. **Cite the source.** No claim without a citation; no decision without a doc URL.

Everything else is in service of those three.

## Inspirations

- [github/spec-kit](https://github.com/github/spec-kit) — Spec-driven workflow
- [obra/superpowers](https://github.com/obra/superpowers) — TDD, debugging, verification skills
- [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) — Plugin marketplace patterns
- [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action) — PR automation
- [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review) — Multi-pass security review
- [ChromeDevTools/chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) — Browser debugging
- [microsoft/playwright-mcp](https://github.com/microsoft/playwright-mcp) — E2E driving
- [wshobson/agents](https://github.com/wshobson/agents) — Tiered model assignment, agent collection
- [disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery) — Hooks patterns

Full reference list in [docs/RESEARCH.md](docs/RESEARCH.md).

## License

MIT. Use it, fork it, improve it, share back if you can.
