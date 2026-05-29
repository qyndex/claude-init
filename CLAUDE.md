# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`claude-init` is a **template harness** (v2.0.0) — a curated `.claude/`, `.github/`, `specs/`, `plans/`, `tasks/`, and `docs/` scaffold that any project copies in to get a spec-driven, TDD-first, verification-gated Claude Code workflow. It is not a running application; there is no `package.json`, `pyproject.toml`, or build step. Every artifact is a shell script, Markdown file, or JSON config.

This CLAUDE.md governs sessions where you are **developing the harness itself** (fixing bugs in scripts, adding agents/skills/hooks, updating CI, etc.).

**Deploy is Bring-Your-Own (BYO).** The harness ships no working deploy pipeline — `.github/workflows/canary-deploy.yml` is a STUB (echo + sleep placeholders that preserve the progressive-rollout shape). Wire your platform following [docs/DEPLOY-INTEGRATION.md](docs/DEPLOY-INTEGRATION.md).

The **authoritative constitution** (agent operating law) is `.claude/CLAUDE.md` — that file is auto-loaded every session and governs autonomous behavior. This root CLAUDE.md is the developer guide.

## Validating changes

Run after any edit to `.claude/`:

```bash
# Structural lint — JSON validity, YAML frontmatter, executables, hooks, agents, skills
bash .claude/scripts/validate.sh

# Full health check (also checks autopilot artifacts, swarm state, memory budget)
/harness-doctor
```

`validate.sh` is data-driven (uses `find`), so adding or removing files is automatically reflected. It checks 14 categories: core files, JSON validity, YAML frontmatter, executable bits, agents, skills, commands, hook cross-references, autopilot artifacts, swarm state, spec/plan/task scaffold, memory layout, security invariants, MCP version pinning.

## Development commands

```bash
# Validate the harness after any .claude/ edit (primary "test" for this repo)
bash .claude/scripts/validate.sh

# Run with ShellCheck (install: brew install shellcheck)
shellcheck .claude/hooks/*.sh .claude/scripts/*.sh

# Lint all JSON files (install: brew install jq)
find .claude .github .mcp.json -name '*.json' | xargs -I{} jq -e . {} > /dev/null

# First-time setup in any target project
bash .claude/scripts/setup.sh
SKIP_PLUGINS=1 bash .claude/scripts/setup.sh   # skip plugin install

# Make a new script executable before running
chmod +x .claude/scripts/<name>.sh .claude/hooks/<name>.sh

# Run verify.sh without stack-specific gates (no real project stack needed)
SKIP_COVERAGE=1 SKIP_TDD_LEDGER=1 SKIP_STORY_MAP=1 SKIP_INTEG_COV=1 bash .claude/scripts/verify.sh

# Operational utilities
bash .claude/scripts/cost-report.sh month        # Anthropic spend vs. cap
bash .claude/scripts/requeue-failed.sh           # list [!] failed tasks
bash .claude/scripts/squash-wip.sh               # squash WIP commits before PR
bash .claude/scripts/collect-evidence.sh <id>    # emit AC checklist + evidence bundle
bash .claude/scripts/memory-gc.sh enforce        # prune MEMORY.md if > 200 lines
bash .claude/scripts/install-plugins.sh          # install canonical plugins
bash .claude/scripts/reconcile-claude-dir.sh \
  --from <factory-clone> --into .               # merge factory into brownfield repo
```

## Architecture of the harness

The harness is a layered stack. Each layer is independent; changes to one should not cascade to others without deliberate intent.

```
Constitution   .claude/CLAUDE.md          — auto-loaded every session; the law
Configuration  .claude/settings.json      — permissions, hooks, env
               .mcp.json                  — MCP server definitions (pinned versions)
Workflow       .claude/skills/<name>/     — one SKILL.md per slash command
Agents         .claude/agents/{core,quality,specialists}/*.md
Discipline     skills: tdd-loop, browser-e2e, security-guard, token-budget, etc.
Memory         .claude/memory/{MEMORY.md, decisions/, patterns/, incidents/, playbooks/}
Hooks          .claude/hooks/*.sh         — deterministic guardrails (fire before the classifier)
Scripts        .claude/scripts/*.sh       — ~60 operational utilities
CI             .github/workflows/         — GitHub Actions gates
Artifacts      specs/ plans/ tasks/ verify/ docs/
Swarm          .swarms/{coordinator,streams,templates}/
Routines       .claude/routines/          — Cloud Routine YAML (overnight-build, dream-cron)
```

**Skill resolution order** (highest → lowest precedence):

1. Project: `.claude/skills/<name>/SKILL.md`
2. User: `~/.claude/skills/<name>/SKILL.md`
3. Plugin: namespaced as `/<plugin>:<name>`
4. Built-in Claude Code skills
5. Legacy: `.claude/commands/<name>.md`

**Agent model assignments** (frontmatter `model:` must match):

- Opus 4.8: architect, implementer, reviewer, security, debugger, designer, extractor
- Sonnet 4.6: planner, tester, verifier, researcher, doc-writer, release, roadmap-architect, coordinator, feature-stream, feedback-extractor
- Haiku 4.5: `Explore` subagent (retrieval only)

## Hook lifecycle

```
SessionStart      → session-start.sh + session-start-context.sh
UserPromptSubmit  → user-prompt-context.sh, workflow-state.sh, skill-router.sh, session-heartbeat.sh
PreToolUse:Bash   → pre-bash-guard.sh (exit 2 = hard block), pre-spawn-cost-gate.sh, pre-bash-dep-freshness.sh
PreToolUse:Write  → pre-write-secret-scan.sh (gitleaks)
PreToolUse:Agent  → subagent-context.sh
PostToolUse:Write → post-write-format.sh, instinct-observer.sh, post-write-roadmap.sh
PostToolUse:Bash  → post-bash-log.sh, instinct-observer.sh
Stop              → stop-verify.sh, auto-dream-check.sh, task-signature-detector.sh
SubagentStop      → subagent-stop.sh
PreCompact        → pre-compact-witness.sh (async witness brief)
SessionEnd        → session-end.sh (ccusage token capture)
```

Every hook referenced in `settings.json` must exist on disk; every `.sh` in `.claude/hooks/` must be registered — `validate.sh` enforces both sides.

**Hook mechanics:** Hooks read tool input from stdin as JSON and write a JSON decision to stdout. Exit code 2 = hard block (fires before the classifier). Exit code 0 = continue. The `pre-bash-guard.sh` splits chained commands on `;`, `&&`, `||`, `|` and checks each segment independently to prevent evasion like `git status; rm -rf ~/proj`.

## Adding new harness components

**New agent** — add `.claude/agents/<tier>/<name>.md` with required frontmatter: `name`, `description`, `model`, `permissionMode`. Tier must match the model routing table above.

**New skill** — add `.claude/skills/<name>/SKILL.md` with `name` and `description` frontmatter. Description (~100 tokens) loads into context at every session start — keep it to one tight trigger sentence. The `maxSkillDescriptionChars` cap is 1536 (set in `settings.json`).

**New hook** — add `.claude/hooks/<name>.sh` (executable), register it in `.claude/settings.json` under the correct event key. `validate.sh` fails until both sides exist.

**New command** (legacy) — add `.claude/commands/<name>.md` with `description:` frontmatter. Skills take precedence over commands when names collide. Commands in `.claude/commands/swarm/` are namespaced as `/swarm:<name>`.

**New CI workflow** — add under `.github/workflows/`. To make it a required merge gate, add the job name to `.github/rulesets/main-protection.json`.

## Extending verify.sh for a new stack

`verify.sh` detects the stack via sentinel files (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`). To add a stack:

1. Add a detection block guarded on a sentinel file.
2. Follow the pattern: `step` / `ok_msg` / `fail_msg`, increment `$fails`.
3. Respect `SKIP_COVERAGE` and `SKIP_*` env vars.

Coverage thresholds: ≥90% line, ≥85% branch (overridden by `COVERAGE_MIN_LINE` / `COVERAGE_MIN_BRANCH`). Critical paths (auth, payments, crypto) get 95% via `codecov.yml`.

## Brownfield adoption

When adopting an existing project (not greenfield setup):

```bash
# From the target repo root
git clone https://github.com/<org>/claude-init /tmp/claude-init
cp -nr /tmp/claude-init/{.claude,.github,specs,plans,tasks,docs,.mcp.json,.gitignore} .
bash .claude/scripts/setup.sh
# If .claude/CLAUDE.md already exists and isn't factory-format:
bash .claude/scripts/reconcile-claude-dir.sh --from /tmp/claude-init --into .
# Then run the six-phase adoption guide:
/adopt start    # see docs/ADOPTION.md
```

`setup.sh` auto-detects a non-factory `.claude/CLAUDE.md` (by checking for "Karpathy's Four Principles") and halts with instructions. Override: `FORCE_GREENFIELD=1 bash .claude/scripts/setup.sh`.

## MCP server model

Three servers are `alwaysLoad: true` (filesystem, git, github). All others are **deferred via Tool Search** (`ENABLE_TOOL_SEARCH=true` in settings.json) — their schemas load on-demand to preserve context budget.

Optional servers in `_disabled_examples` (supabase, linear, notion, stripe, etc.) are catalogue entries — copy a block into `mcpServers` to activate. All active servers should be version-pinned; `validate.sh` warns on `@latest`.

The Graphify MCP (`query_graph`, `shortest_path`, `get_neighbors`) is preferred over grep for cross-module/call-graph questions on >3 files.

## Source-of-truth map

| Question               | Look here                                  |
| ---------------------- | ------------------------------------------ |
| Task state             | `tasks/TASKS.md` — sole source             |
| Active specs           | `specs/active/*.md`                        |
| Active plans           | `plans/active/*.md`                        |
| Decisions (ADRs)       | `.claude/memory/decisions/`                |
| Reusable patterns      | `.claude/memory/patterns/`                 |
| Constitution (the law) | `.claude/CLAUDE.md`                        |
| Personal overrides     | `.claude/settings.local.json` (gitignored) |

Task status markers: `[ ]` pending · `[~]` in progress · `[x]` done · `[!]` failed · `[b]` blocked · `[s]` skipped.

## Commit format

Conventional Commits with required trailers (enforced by `commitlint.yml`):

```
feat(hooks): add pre-spawn cost gate

Constraint:    must not add latency to interactive turns
Rejected:      inline check | too fragile
Confidence:    high
Scope-risk:    localized

Task: T-042

Co-Authored-By: Claude <noreply@anthropic.com>
```

WIP checkpoints: `WIP: <6-word decision>` subject, squash-filtered before PR via `bash .claude/scripts/squash-wip.sh`.

Every `eslint-disable`, `# noqa`, `# type: ignore` requires `JUSTIFICATION:` and `ISSUE: #N` within 3 lines. Security disables require an ADR. Enforced by `lint-exception-audit.yml`.

## Security invariants (never break)

- `disableBypassPermissionsMode: "disable"` must remain in `settings.json` (the string `"disable"`, not boolean `true` — Claude Code silently ignores the boolean form).
- `pre-bash-guard.sh` must block: `rm -rf`, `git push --force origin main`, `DROP TABLE`, `--no-verify`, `curl|sh`, `eval`, `base64|sh`, `python -c`, `node -e`.
- `.env*`, `*.pem`, `*.key`, `*credentials*` must stay deny-listed for Read and Write.
- `.claude/CLAUDE.md` (the constitution) is intentionally blocked from Claude writes — do not circumvent this.
- `validate.sh` checks `disableBypassPermissionsMode` and absence of `Bash(env)` / bare `Bash(claude:*)` in the allow list.
- GitHub Issues are **write-only projections** of `tasks/TASKS.md`. Never read task state from `gh issue view` / `gh api .../issues` — `no-issue-authority.yml` fails the build if introduced.
