# Research — every design decision, with sources

This document maps every meaningful design choice in this harness to its citation. Compiled from five parallel research streams (May 2026) across Claude Code official docs, agentic frameworks, security/CI/E2E, curated repos, and MCP/memory.

## How to read this

Each section explains a design choice in the harness and links to the primary source(s) that justified it. When the source is a GitHub repo, the link is to the repo root unless a specific file is more relevant.

---

## 1. The eight-phase workflow (constitution → spec → clarify → plan → tasks → analyze → implement → verify → review → ship)

**Why this shape**: The Spec Kit pattern is the de-facto reference for spec-driven agentic development. It crystallized in 2025 after the "vibe coding" backlash.

- [github/spec-kit](https://github.com/github/spec-kit) — GitHub's official toolkit (`/speckit.constitution`, `/speckit.specify`, `/speckit.clarify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.analyze`, `/speckit.implement`)
- [spec-driven methodology doc](https://github.com/github/spec-kit/blob/main/spec-driven.md)
- [Kiro by AWS](https://kiro.dev) — agentic IDE pioneering "spec before code"
- [Tessl: From Vibe Coding to Spec-Driven Development](https://tessl.io/blog/from-vibe-coding-to-spec-driven-development/)

**Our adaptation**: We split `/speckit.implement` into `/implement` + `/verify` + `/review` + `/ship` because verification and review are first-class phases with their own agents (verifier, reviewer, security).

---

## 2. Agent roster (architect, planner, implementer, tester, reviewer, security, verifier, debugger, researcher, doc-writer, release)

**Why these roles**: Consensus across Claude Code, Kiro, Cursor 2.0, Augment Intent on the canonical agent-team shape.

- [mizioandOrg/claude-planner-reviewer-implementer](https://github.com/mizioandOrg/claude-planner-reviewer-implementer) — reference orchestrator with planner → reviewer → implementer loop
- [wshobson/agents](https://github.com/wshobson/agents) — 191 agents organized by tier; we borrowed the tiered model assignment (Opus/Sonnet/Haiku) pattern
- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) — 100+ subagents in 10 categories
- [contains-studio/agents](https://github.com/contains-studio/agents) — department-organized
- [iannuttall/claude-agents](https://github.com/iannuttall/claude-agents) — high-quality agent prompts
- [vijaythecoder/awesome-claude-agents](https://github.com/vijaythecoder/awesome-claude-agents) — agent-team-configurator pattern
- [dl-ezo/claude-code-sub-agents](https://github.com/dl-ezo/claude-code-sub-agents) — 35 end-to-end automation agents

**Tier assignment**:
- Opus 4.7: architect, implementer, reviewer, security, debugger (hard thinking)
- Sonnet 4.6: planner, tester, verifier, researcher, doc-writer, release (everyday work)
- Haiku 4.5: built-in Explore subagent for retrieval/search

Source for tier strategy: [wshobson/agents README](https://github.com/wshobson/agents) and [Anthropic Models overview](https://platform.claude.com/docs/en/about-claude/models/overview).

---

## 3. Subagent frontmatter (name, description, tools, model, permissionMode, maxTurns, skills, mcpServers, memory, isolation, color)

**Source**: Claude Code official subagents docs.

- [Sub-agents docs](https://code.claude.com/docs/en/sub-agents)
- `description` field is critical for delegation; lead with "Use when..." trigger phrases. Field name: `name` (required, lowercase-kebab), `description` (required), `tools` (omit to inherit all), `disallowedTools`, `model` (sonnet/opus/haiku/inherit), `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `effort`, `isolation: worktree`, `color`, `initialPrompt`.

**Note**: In v2.1.63 the `Task` tool was renamed to `Agent` (alias preserved).

---

## 4. Skills with progressive disclosure (`.claude/skills/<name>/SKILL.md`)

**Why over commands**: Custom slash commands were merged into the Skills system in late 2025. New work should use skills.

- [Skills docs](https://code.claude.com/docs/en/skills)
- [Agent Skills overview (Anthropic API)](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)
- [Agent Skills best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Anthropic engineering blog on equipping agents with skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- [agentskills.io](https://agentskills.io) — open standard
- [anthropics/skills](https://github.com/anthropics/skills) — official Anthropic skills repo (skill-creator + docx/pdf/pptx/xlsx)
- [obra/superpowers](https://github.com/obra/superpowers) — the gold standard for opinionated skill authorship

**Progressive disclosure**: SKILL.md frontmatter (~100 tokens) loads at startup; body loads only when triggered. Keep SKILL.md < 500 lines; put deep reference in sibling files. Default max-skill-description is **1536 chars** (`maxSkillDescriptionChars` setting).

---

## 5. The tdd-loop skill (strict red-green-refactor)

**Why mandatory**: The single biggest documented quality lift in the agentic ecosystem.

- [obra/superpowers test-driven-development SKILL.md](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md) — the canonical implementation; will delete production code written before a failing test exists
- [aihero.dev — Skill that makes Claude great at TDD](https://www.aihero.dev/skill-test-driven-development-claude-code)

**Rule**: "if you didn't watch the test fail, you don't know if it tests the right thing" — direct from Superpowers.

---

## 6. The verification skill (evidence before assertion)

**Source**: Superpowers verification-before-completion + Anthropic's own automated security review pattern.

- [Superpowers verification-before-completion](https://www.claudepluginhub.com/skills/obra-superpowers-2/verification-before-completion)
- [Anthropic: Automate security reviews with Claude Code](https://www.anthropic.com/news/automate-security-reviews-with-claude-code) — multi-agent parallel verification with re-check pass to filter false positives

**Operational pattern**: Tests pass → boot the app → walk the journey → capture evidence → only then mark done.

---

## 7. The browser-e2e skill (chrome-devtools-mcp + playwright-mcp + stagehand)

**Tooling decision matrix** is from the research:

- **playwright-mcp** for driving (deterministic refs, snapshot-based) — [microsoft/playwright-mcp](https://github.com/microsoft/playwright-mcp)
- **chrome-devtools-mcp** for debugging (network, console, performance traces, Lighthouse v0.9.0+) — [ChromeDevTools/chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp)
- **stagehand v3** for cloud + self-healing — [browserbase/stagehand](https://github.com/browserbase/stagehand)

**Visual regression** (out of band):
- [Chromatic](https://www.chromatic.com/) — Storybook-first
- [Percy](https://percy.io/) — Visual Review Agent (smart bounding boxes, 2025+)
- [Argos](https://github.com/argos-ci/argos) — open source, Playwright integrated
- [Lost Pixel](https://github.com/lost-pixel/lost-pixel) — **deprecated** (joining Figma 2025)
- [BackstopJS](https://github.com/garris/BackstopJS) — legacy

**Benchmarks 2026**: Playwright+Claude ~92%, Stagehand ~89%, Browserbase ~90%, Anthropic Computer Use ~78%, OpenAI CUA ~75%. DOM-driven beats vision-based for 80% of web testing. Source: [callsphere.ai comparison](https://callsphere.ai/blog/claude-computer-use-vs-playwright-visual-ai-vs-dom-automation).

---

## 8. The security-guard skill (OWASP + LLM Top 10 + multi-pass)

**OWASP**:
- [OWASP Top 10 (web)](https://owasp.org/Top10/)
- [OWASP LLM Top 10 v2025](https://owasp.org/www-project-top-10-for-large-language-model-applications/assets/PDF/OWASP-Top-10-for-LLMs-v2025.pdf)
- [Prompt Injection Cheatsheet](https://cheatsheetseries.owasp.org/cheatsheets/LLM_Prompt_Injection_Prevention_Cheat_Sheet.html)

**Multi-pass discipline**:
- [Anthropic claude-code-security-review](https://github.com/anthropics/claude-code-security-review) — multi-agent parallel scan with re-verification; Opus 4.6 found 500+ production vulnerabilities

**Secret scanning**:
- [gitleaks](https://github.com/gitleaks/gitleaks) — fast, pre-commit
- [trufflehog](https://github.com/trufflesecurity/trufflehog) — verifies if creds are live
- [detect-secrets](https://github.com/Yelp/detect-secrets) — baseline-based

**Prompt-injection defense**:
- [NeMo Guardrails](https://github.com/NVIDIA/NeMo-Guardrails)
- [Llama-Guard / Prompt-Guard](https://github.com/meta-llama/PurpleLlama)
- [Promptfoo OWASP red-team](https://www.promptfoo.dev/docs/red-team/owasp-llm-top-10/)

**Claude Code CVEs (2025)** — informed our PreToolUse hook design:
- CVE-2025-54794 — path-restriction bypass (CVSS 7.7)
- CVE-2025-54795 — command-injection RCE (CVSS 8.7)
- [Cymulate writeup](https://cymulate.com/blog/cve-2025-547954-54795-claude-inverseprompt/)
- [Lasso on hidden backdoor](https://www.lasso.security/blog/the-hidden-backdoor-in-claude-coding-assistant)

---

## 9. The token-budget skill

**Source**: Anthropic's own engineering on context economy.

- [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — "smallest set of high-signal tokens"
- [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Managing context (memory + context editing)](https://www.anthropic.com/news/context-management)
- [Prompt caching docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)

**Cache TTL change** (March 6, 2026): default dropped from 1h → 5min. For longer sessions, explicitly set `cache_control: {"type":"ephemeral","ttl":"1h"}`. Source: [DEV article](https://dev.to/whoffagents/anthropic-silently-dropped-prompt-cache-ttl-from-1-hour-to-5-minutes-16ao).

**Cost-monitoring tools**:
- [ccusage](https://github.com/ryoppippi/ccusage) — local JSONL parser, statusline integration
- [cc-statusline](https://github.com/chongdashu/cc-statusline) — full statusline
- [claude-statusline-enhanced](https://github.com/displace-agency/claude-statusline-enhanced) — cache hit rate visibility
- [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) — live fuel gauge
- [claude_telemetry](https://github.com/TechNickAI/claude_telemetry) — OpenTelemetry wrapper

---

## 10. The auto-loop skill (Ralph + native /loop)

**Two patterns merged**:
- **Ralph Loop** (Geoffrey Huntley, July 2025) — fresh context each iteration, filesystem as memory
- **`/loop` command** (Claude Code, 2026) — recurring task with self-pacing

Sources:
- [vercel-labs/ralph-loop-agent](https://github.com/vercel-labs/ralph-loop-agent)
- [frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code) — Claude Code variant with smart-exit detection
- [Blake Crosley on Ralph architecture](https://blakecrosley.com/blog/ralph-agent-architecture)
- [`/loop` analysis](https://gist.github.com/sorrycc/1b2166228413234928039e84a26a3b8f)
- [Cherny on /loop & /schedule](https://www.threads.com/@boris_cherny/post/DWfjpUNlKzx/)
- [What is Claude Code's /loop command](https://www.mindstudio.ai/blog/what-is-claude-code-loop-command-recurring-tasks)

**Anthropic's `ralph-wiggum` plugin** shipped Dec 2025.

---

## 11. The research-grounding skill (no claim without a citation)

**Source**: Anthropic engineering posts + academic studies of agent grounding.

- [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — "just-in-time exploration"
- [Agent READMEs paper (arxiv 2511.12884)](https://arxiv.org/pdf/2511.12884) — empirical study
- [On Agentic Coding Manifests (arxiv 2509.14744)](https://arxiv.org/pdf/2509.14744) — empirical Claude Code study
- [Agentic Software Engineering: Foundational Pillars (arxiv 2509.06216)](https://arxiv.org/html/2509.06216v1)
- [Why Agentic PRs Get Rejected (arxiv 2602.04226)](https://arxiv.org/pdf/2602.04226) — 932K agentic PRs analyzed

---

## 12. Settings (`.claude/settings.json`) schema

**Source**: Claude Code settings reference.

- [Settings docs](https://code.claude.com/docs/en/settings)
- JSON schema: `https://json.schemastore.org/claude-code-settings.json`

**Key updates we adopted from research**:
- `includeCoAuthoredBy` is **deprecated** → use `attribution: { commit, pr }`
- New keys: `skillOverrides`, `maxSkillDescriptionChars`, `skillListingBudgetFraction`, `sandbox.{filesystem,network}`, `worktree.{baseRef,symlinkDirectories,bgIsolation}`, `effortLevel`, `disableAutoMode`, `autoMemoryEnabled`, `plansDirectory`, `prUrlTemplate`
- Permission rules: tool-scoped patterns like `Bash(npm run *)`, `Read(./.env)`, `WebFetch(domain:github.com)`
- Evaluation order: `deny → ask → allow`, first match wins

---

## 13. Hooks system (`.claude/hooks/`)

**Source**: Claude Code hooks reference.

- [Hooks docs](https://code.claude.com/docs/en/hooks)
- [karanb192/claude-code-hooks](https://github.com/karanb192/claude-code-hooks) — production hook examples
- [disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery) — all 13 events implemented (we borrowed the structure)
- [Pixelmojo: Claude Code Hooks production patterns](https://www.pixelmojo.io/blogs/claude-code-hooks-production-quality-ci-cd-patterns)
- [Pasquale: --dangerously-skip-permissions hardening](https://pasqualepillitteri.it/en/news/1832/claude-code-dangerously-skip-permissions-pretooluse-hooks-2026)
- [Context recovery hook](https://medium.com/coding-nexus/context-recovery-hook-for-claude-code-never-lose-work-to-compaction-7ee56261ee8f)

**Decision protocol**:
- Exit code 0 = success (stdout parsed as JSON)
- Exit code 2 = blocking error
- Exit code 1 or 3-255 = non-blocking error
- For PreToolUse: emit `hookSpecificOutput.permissionDecision: allow|deny|ask|defer`

**Events used**:
- `SessionStart` (matcher: startup|resume) — boot summary
- `UserPromptSubmit` — inject branch/spec/plan context
- `PreToolUse` (matchers: Bash, Write|Edit) — bash guard, secret scan
- `PostToolUse` — auto-format, audit log
- `Stop` — verification nudge
- `SubagentStop` — log subagent runs
- `PreCompact` (matcher: auto) — snapshot before compaction
- `SessionEnd` — capture usage via ccusage

---

## 14. MCP servers (`.mcp.json`)

**Source**: MCP official servers + Anthropic registry + research findings.

- [modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers) — official reference
- [Official MCP Registry](https://registry.modelcontextprotocol.io/)
- [Awesome MCP servers (punkpeye)](https://github.com/punkpeye/awesome-mcp-servers)
- [docker/mcp-registry](https://github.com/docker/mcp-registry)
- [microsoft/mcp](https://github.com/microsoft/mcp)

**Servers we bundled** (with rationale):

| Server | Repo | Why |
|---|---|---|
| filesystem | [official](https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem) | always-needed |
| git | [official](https://github.com/modelcontextprotocol/servers/tree/main/src/git) | always-needed |
| github | [github/github-mcp-server](https://github.com/github/github-mcp-server) | GA Sep 2025, OAuth |
| chrome-devtools | [ChromeDevTools/chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) | debugging |
| playwright | [microsoft/playwright-mcp](https://github.com/microsoft/playwright-mcp) | E2E driving |
| context7 | [upstash/context7](https://github.com/upstash/context7) | library docs |
| postgres | [crystaldba/postgres-mcp](https://github.com/crystaldba/postgres-mcp) | official one deprecated |
| sentry | [Sentry MCP](https://mcp.sentry.dev/mcp) | observability |

**Disabled-but-documented examples** for: supabase, linear, notion, atlassian, vercel, cloudflare, datadog, logfire, posthog, stripe, exa, brave-search, browserbase, postman, k6, semgrep, sourcegraph, aws-serverless, mem0.

**MCP risk awareness**: Pin versions, audit community servers, sandbox where possible. See [E2B Firecracker microVMs](https://e2b.dev/) and [Daytona container sandboxes](https://github.com/daytonaio/daytona) for hostile environments.

**Deprecations called out**:
- Official `postgres` MCP → use [crystaldba/postgres-mcp](https://github.com/crystaldba/postgres-mcp)
- Lighthouse MCP standalone → folded into [chrome-devtools-mcp v0.19+](https://github.com/ChromeDevTools/chrome-devtools-mcp)
- Stagehand v3 dropped Playwright dep
- Semgrep MCP → moved into `semgrep` binary as `semgrep mcp`
- MemGPT renamed to **Letta**
- SSE MCP transport deprecated → use HTTP

---

## 15. Plugin marketplaces

**Source**: Anthropic plugin docs + curated marketplaces.

- [Plugins docs](https://code.claude.com/docs/en/plugins)
- [Plugins reference](https://code.claude.com/docs/en/plugins-reference)
- [Discover plugins](https://code.claude.com/docs/en/discover-plugins)
- [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) — 150+ vetted plugins, auto-update
- [anthropics/claude-plugins-community](https://github.com/anthropics/claude-plugins-community) — auto security-scanned, pinned to SHAs
- [obra/superpowers-marketplace](https://github.com/obra/superpowers-marketplace) — Jesse Vincent's curated marketplace
- [wshobson/agents](https://github.com/wshobson/agents) — 83 plugins, 191 agents, 155 skills, 102 commands cross-harness
- [hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) — ~45k stars, canonical curated list
- [davila7/claude-code-templates](https://github.com/davila7/claude-code-templates) — browse at [aitmpl.com](https://www.aitmpl.com/)
- [Chat2AnyLLM/awesome-claude-plugins](https://github.com/Chat2AnyLLM/awesome-claude-plugins) — aggregated index

---

## 16. GitHub Actions workflows

**Source**: Anthropic's official Actions + best-practice patterns.

- [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action) — GA Aug 26, 2025. Supersedes the beta.
- [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review) — multi-agent parallel security
- [GitHub Actions docs (claude-code)](https://code.claude.com/docs/en/github-actions)

**Branch protection (Rulesets)**:
- [Rulesets docs](https://docs.github.com/en/repositories/configuring-branch-and-merge-flow/managing-rulesets) — replaces classic branch protection
- Required: `Require status checks`, `Require linear history`, `Require signed commits`, `Block force pushes`

**Auto-merge**:
- GitHub native `gh pr merge --auto --squash` — [tutorial](https://www.zonca.dev/posts/2025-10-20-github-actions-auto-merge)
- [Mergify](https://mergify.com/blog/github-auto-merge-when-native-is-enough/) — rule-based merge queue
- [Kodiak](https://github.com/chdsbd/kodiak) — **DEPRECATED**, do not adopt
- [Dependabot fetch-metadata](https://docs.github.com/en/code-security/tutorials/secure-your-dependencies/automating-dependabot-with-github-actions)
- [navikt/automerge-dependabot](https://github.com/navikt/automerge-dependabot)

**Preview deploy + E2E**:
- [Vercel official recipe](https://vercel.com/kb/guide/how-can-i-run-end-to-end-tests-after-my-vercel-preview-deployment)
- [Netlify regression pipeline](https://getautonoma.com/blog/regression-testing-netlify-deploy-previews)
- [wait-for-vercel-preview action](https://github.com/patrickedqvist/wait-for-vercel-preview)
- [Render preview environments](https://render.com/docs/preview-environments)
- [Railway environments](https://docs.railway.com/guides/environments)

**Release automation**:
- [release-please](https://github.com/googleapis/release-please-action) — Conventional Commits → CHANGELOG

**Stacked PRs** (for high-velocity agentic teams):
- [GitHub native gh-stack](https://github.com/github/gh-stack) — private preview Apr 13, 2026
- [Graphite](https://graphite.com/blog/stacked-prs) — stack-aware merge queue
- [Meta ghstack](https://github.com/ezyang/ghstack)

---

## 17. Memory system (`.claude/memory/`)

**Source**: Claude Code memory docs + ecosystem patterns.

- [Memory & CLAUDE.md docs](https://code.claude.com/docs/en/memory)
- [The Complete Guide to CLAUDE.md (Medium)](https://medium.com/@bijit211987/the-complete-guide-to-claude-md-memory-rules-loading-and-cross-tool-compression-97cc12ed037b)
- [Anatomy of the .claude folder](https://codewithmukesh.com/blog/anatomy-of-the-claude-folder/)
- [The complete guide to AI agent memory files (HackerNoon)](https://hackernoon.com/the-complete-guide-to-ai-agent-memory-files-claudemd-agentsmd-and-beyond)

**Resolution order** (broad → specific, all concatenated):
1. Managed policy CLAUDE.md
2. `~/.claude/CLAUDE.md` (user-global)
3. Ancestor `CLAUDE.md` files walked to root
4. `<cwd>/CLAUDE.md` or `<cwd>/.claude/CLAUDE.md`
5. `<cwd>/CLAUDE.local.md`

**`@import` syntax**: recursive, 4-hop depth limit.

**Path-scoped rules**: `.claude/rules/<topic>.md` with `paths: [...]` frontmatter.

**Auto-memory** (v2.1.59+): `~/.claude/projects/<project>/memory/MEMORY.md`, first 200 lines / 25KB loaded each session. Toggle via `autoMemoryEnabled`.

**Persistent memory MCPs**:
- [mem0ai/mem0](https://github.com/mem0ai/mem0) — ~47K stars, hybrid vector+graph+KV
- [letta-ai/letta](https://github.com/letta-ai/letta) (formerly MemGPT) — memory-as-OS tiers
- [getzep/zep](https://github.com/getzep/zep) + [graphiti](https://github.com/getzep/graphiti) — temporal knowledge graph
- [basicmachines-co/basic-memory](https://github.com/basicmachines-co/basic-memory) — markdown + Obsidian-native
- [Anthropic Memory Tool docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)

**Memory taxonomy we adopted** (decisions / patterns / incidents / playbooks) is the 2026 consensus from the HackerNoon guide.

---

## 18. Output styles + statusline

**Source**: Claude Code docs.

- [Output styles docs](https://code.claude.com/docs/en/output-styles)
- [Statusline docs](https://code.claude.com/docs/en/statusline)

**Note**: The standalone `/output-style` command was **removed in v2.1.91** — use `/config` or `outputStyle` setting.

**Built-in styles**: Default, Explanatory, Learning, Proactive. We added two custom: Concise (default), Teaching (for onboarding).

---

## 19. Spec / Plan / Task templates

**Source**: Spec Kit conventions + BMAD-METHOD role taxonomy.

- [github/spec-kit](https://github.com/github/spec-kit) — spec.md, plan.md, tasks.md, data-model.md, research.md, quickstart.md
- [bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) — 9 specialized roles + 15 workflow commands
- [buildermethods/agent-os](https://github.com/buildermethods/agent-os) — spec-driven dev system with Claude Code Skills integration
- [eyaltoledano/claude-task-master](https://github.com/eyaltoledano/claude-task-master) — task-management MCP

**Task format**: from Spec Kit, with `[P]` parallel-safe markers. Tasks sized to 2-5 minutes (consensus across Superpowers `writing-plans`, Spec Kit conventions).

**CCPM** for issue-driven planning:
- [automazeio/ccpm](https://github.com/automazeio/ccpm) — GitHub Issues + Git worktrees for parallel agent execution

---

## 20. Inspirations / repos we studied (full list)

### Awesome lists
- [hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) — ~45k stars
- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents)
- [langgptai/awesome-claude-prompts](https://github.com/langgptai/awesome-claude-prompts)
- [travisvn/awesome-claude-skills](https://github.com/travisvn/awesome-claude-skills)
- [rohitg00/awesome-claude-code-toolkit](https://github.com/rohitg00/awesome-claude-code-toolkit)
- [ComposioHQ/awesome-claude-plugins](https://github.com/ComposioHQ/awesome-claude-plugins)

### Subagent collections
- [wshobson/agents](https://github.com/wshobson/agents)
- [contains-studio/agents](https://github.com/contains-studio/agents)
- [iannuttall/claude-agents](https://github.com/iannuttall/claude-agents)
- [dl-ezo/claude-code-sub-agents](https://github.com/dl-ezo/claude-code-sub-agents)
- [vijaythecoder/awesome-claude-agents](https://github.com/vijaythecoder/awesome-claude-agents)

### Commands / workflows
- [wshobson/commands](https://github.com/wshobson/commands) — workflows/ + tools/ split
- [qdhenry/Claude-Command-Suite](https://github.com/qdhenry/Claude-Command-Suite) — 216+ slash commands
- [brennercruvinel/CCPlugins](https://github.com/brennercruvinel/CCPlugins)
- [disler/infinite-agentic-loop](https://github.com/disler/infinite-agentic-loop)

### Skills
- [anthropics/skills](https://github.com/anthropics/skills) — official Anthropic
- [obra/superpowers](https://github.com/obra/superpowers)
- [obra/superpowers-skills](https://github.com/obra/superpowers-skills)
- [obra/superpowers-lab](https://github.com/obra/superpowers-lab)
- [obra/superpowers-chrome](https://github.com/obra/superpowers-chrome)
- [Hacker0x01/claude-power-user](https://github.com/Hacker0x01/claude-power-user) — HackerOne's internal fork
- [lackeyjb/playwright-skill](https://github.com/lackeyjb/playwright-skill)

### Spec-driven / planning
- [github/spec-kit](https://github.com/github/spec-kit)
- [kirodotdev/Kiro](https://github.com/kirodotdev/Kiro)
- [bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)
- [buildermethods/agent-os](https://github.com/buildermethods/agent-os)
- [eyaltoledano/claude-task-master](https://github.com/eyaltoledano/claude-task-master)
- [ruvnet/claude-flow](https://github.com/ruvnet/claude-flow) (renamed to ruflo)

### Complete `.claude/` folders studied
- [disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery) — hooks structure
- [centminmod/my-claude-code-setup](https://github.com/centminmod/my-claude-code-setup) — memory-bank pattern
- [anthropics/claude-cookbooks](https://github.com/anthropics/claude-cookbooks) — Memory tool patterns
- [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) — "Karpathy CLAUDE.md" (~65 lines)
- [SuperClaude-Org/SuperClaude_Framework](https://github.com/NomenAK/SuperClaude) — 30 commands + 9 personas
- [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice)

### Project management
- [automazeio/ccpm](https://github.com/automazeio/ccpm) — leader for issue-driven AI dev
- [zhsama/claude-sub-agent](https://github.com/zhsama/claude-sub-agent)

---

## 21. Authoritative Anthropic / Claude Code documentation

Always check these for the latest:

- [Claude Code docs root](https://code.claude.com/docs/en/) — moved from docs.anthropic.com in 2025
- [llms.txt index](https://code.claude.com/docs/llms.txt) — every doc URL, machine-readable
- [Settings](https://code.claude.com/docs/en/settings)
- [Memory](https://code.claude.com/docs/en/memory)
- [Sub-agents](https://code.claude.com/docs/en/sub-agents)
- [Skills](https://code.claude.com/docs/en/skills)
- [Hooks](https://code.claude.com/docs/en/hooks)
- [MCP](https://code.claude.com/docs/en/mcp)
- [Plugins](https://code.claude.com/docs/en/plugins)
- [Output styles](https://code.claude.com/docs/en/output-styles)
- [Status line](https://code.claude.com/docs/en/statusline)
- [GitHub Actions](https://code.claude.com/docs/en/github-actions)
- [Worktrees](https://code.claude.com/docs/en/worktrees)
- [Anthropic engineering: effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Anthropic engineering: effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Anthropic engineering: equipping agents with skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- [Anthropic: automate security reviews](https://www.anthropic.com/news/automate-security-reviews-with-claude-code)
- [Anthropic: managing context (memory tool)](https://www.anthropic.com/news/context-management)

---

## 22. Cross-tool standards

- [AGENTS.md cross-tool spec](https://hivetrail.com/blog/agents-md-vs-claude-md-cross-tool-standard)
- [agentskills.io](https://agentskills.io) — open standard for skills
- [Model Context Protocol spec](https://modelcontextprotocol.io)

To dual-purpose `CLAUDE.md` and `AGENTS.md`, either symlink them or place `@AGENTS.md` at the top of `CLAUDE.md`.

---

## Methodology

This research was gathered by running five parallel subagents over ~5 minutes each, scoped to:
1. Claude Code best practices (settings.json, hooks, skills, plugins, MCP)
2. Agentic frameworks (TDD, spec-driven, autonomous loops, multi-agent)
3. Security / CI / browser E2E
4. Curated repos and marketplaces
5. MCP servers and memory systems

Total references: ~150 GitHub repos, ~30 official documentation pages, ~15 academic papers, ~40 blog posts and engineering write-ups. All sources are dated 2024-2026 unless otherwise noted; older sources flagged for re-verification.

Last refreshed: 2026-05-27.
