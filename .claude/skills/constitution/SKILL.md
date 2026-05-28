---
name: constitution
description: Author or amend the project constitution at .claude/CLAUDE.md. Use when starting a brand-new project, when a major architectural principle shifts, or when the team wants to lock in non-negotiables. Modeled on github/spec-kit's /speckit.constitution.
when_to_use: User says "set up the constitution", "init the project rules", "what are our principles", or starts a fresh repo and asks for Claude Code scaffolding.
argument-hint: "[topic to amend, optional]"
model: opus
allowed-tools: Read, Write, Edit, Glob, Grep, WebFetch
---

# Constitution

You are about to write or amend the project constitution at `.claude/CLAUDE.md`. This file is the single source of truth for every agent in this repo. It overrides defaults; the user overrides it.

## Process

1. **Read the existing constitution** if any. Identify what's working and what's drift.
2. **Interview the user** (max 4 questions) on:
   - Primary tech stack and runtime
   - Non-negotiable quality bars (test coverage, security gates, performance targets)
   - Deployment cadence and environment topology
   - Any incident-driven rules ("never X again because Y")
3. **Draft the constitution** with the sections in this template (see `.claude/CLAUDE.md` for the canonical structure).
4. **Validate** — under 200 lines, no fluff, every rule has a why.
5. **Save** to `.claude/CLAUDE.md` and stage for commit.

## Sections required

1. North star (1 paragraph)
2. Non-negotiables (5-10 hard rules)
3. Workflow / phases
4. Agent team roster
5. Memory system
6. Token discipline
7. Security guardrails
8. Quality bar (the shipping checklist)
9. Auto-mode rules
10. Decision-making defaults
11. House style
12. Bootstrap + maintenance pointers

## Hard rules for the constitution itself

- **Under 200 lines.** Link out for details.
- **Every rule explains why.** A rule with no rationale gets ignored.
- **No platitudes.** "Write good code" is not a rule. "Functions ≤ 50 LOC" is.
- **Linkable.** Use anchors so other files can deep-link.
