# Awesome-list submission drafts

Copy-paste entries + PR descriptions for submitting `claude-init` to relevant awesome-lists.
Each list has its own format and contribution rules — **read its CONTRIBUTING before submitting**,
match the surrounding entry style exactly, and add your entry alphabetically or in the right
section. Low-effort or mis-placed entries get rejected.

Before submitting: the repo should have the demo GIF, a working CI badge, and a tagged release —
list maintainers check for signs of a maintained project.

---

## awesome-claude-code

**Target:** search GitHub for the most-starred `awesome-claude-code` list.
**Likely section:** "Workflows / Templates / Starter kits".

Entry:

```markdown
- [claude-init](https://github.com/qyndex/claude-init) — One-command harness that turns Claude Code into an autonomous, spec-driven engineering team: a `.claude/` scaffold with a constitution, TDD + verification hooks, security guardrails, and a spec→plan→tasks→ship workflow. Works on greenfield and legacy repos (safe reconcile). MIT.
```

PR title: `Add claude-init (spec-driven, TDD-first Claude Code harness)`

PR body:

> Adds **claude-init**, an MIT-licensed harness that installs a full spec-driven / TDD-first /
> verification-gated Claude Code workflow into any repo with one command. It ships a constitution,
> ~25 hooks (destructive-command + secret-write blocking), specialized subagents, an eight-phase
> workflow (constitute → specify → clarify → plan → tasks → analyze → implement → verify → review
> → ship), and CI gates. Placed in the <section> section, alphabetical order.

---

## awesome-ai-agents

**Target:** e.g. `e2b-dev/awesome-ai-agents` or the most-active `awesome-ai-agents`.
**Likely section:** "Frameworks" or "Open-source agents / tooling".

Entry:

```markdown
- [claude-init](https://github.com/qyndex/claude-init) - Drop-in harness that makes Claude Code operate as a governed, autonomous engineering team — spec-driven workflow, strict TDD with red→green evidence ledgers, security hooks, and an auto-merge-on-green shipping pipeline. One-command install into any repo.
```

PR title: `Add claude-init`

PR body:

> claude-init packages an opinionated, safety-first agentic workflow for Claude Code: it enforces
> spec-before-code, evidence-before-done (every task carries a failing→passing test ledger), and
> hard-blocks destructive commands via hooks that fire before the model acts. Config + shell,
> MIT, no build step. Added alphabetically to the <section> section.

---

## awesome-mcp / awesome-mcp-servers

**Note:** claude-init is not itself an MCP *server* — it *consumes* MCP (filesystem, git, github,
and deferred servers via Tool Search). Only submit to an MCP list if it has a "clients / tooling /
setups" section; do **not** file it under "servers". If unsure, skip — a mis-filed entry hurts more
than it helps.

Entry (for a clients/tooling section only):

```markdown
- [claude-init](https://github.com/qyndex/claude-init) — Claude Code harness with a pre-wired, version-pinned MCP setup (filesystem/git/github always-on; others deferred via Tool Search to save context) plus a full spec-driven agent workflow.
```

---

## General submission etiquette

- One list per PR; don't batch.
- Follow the list's exact entry grammar (some require a trailing period, some a specific dash).
- If the list runs `awesome-lint`, run it locally first.
- Don't argue rejections — fix and resubmit, or move on.
