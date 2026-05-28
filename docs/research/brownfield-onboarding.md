# Research: Brownfield Adoption for an Autonomous Software Factory

**Date:** 2026-05-28
**Scope:** Prior art for ingesting an existing real-world project into a spec/plan/TDD/verify/ship agentic harness.

---

## TL;DR

Brownfield adoption requires a mandatory read-only audit phase (comprehension + characterization tests) before any autonomous change. No credible prior art supports skipping it. Confidence: **strong** on the sequencing; **tentative** on tooling choices (space is evolving fast).

---

## 1. Legacy-Code Remediation Strategies

### Characterization Tests (Feathers, 2004 — verify current for AI context)

Michael Feathers defines characterization tests as tests that document *current* behavior rather than intended behavior. They are written first, before any refactoring, to create a behavioral snapshot.

> "You write tests that you use to describe the current behavior of the system." — Feathers, *Working Effectively with Legacy Code* (2004), summarized at [understandlegacycode.com](https://understandlegacycode.com/blog/key-points-of-working-effectively-with-legacy-code/)

**Canonical sequence for safely modifying untested code** (Feathers, ibid.):
1. Identify a change point.
2. Find the test points (seams).
3. Break dependencies so the unit is testable.
4. Write characterization tests for the current behavior.
5. Make the change; verify the characterization tests still pass.
6. Only then add new functionality via TDD (sprout method / wrap method).

**Sprout Method**: Write new logic as a separate, TDD-tested method; call it from existing code. The old code is untouched. ([cheatortrick.blogspot.com, 2021 — verify current](https://cheatortrick.blogspot.com/2021/03/working-with-legacy-code-sprout-method.html))

**Wrap Method**: Rename existing method, create a new method with the original name that calls the old one plus new logic. Zero change to legacy logic. (ibid.)

**Seams**: Places where behavior can be altered without editing that location — virtual methods, interfaces, static-link substitution. ([Tech Lead Journal ep. 195, Oct 2024](https://techleadjournal.dev/episodes/195/))

### Strangler Fig (Fowler, 2004)

Gradually route traffic from old to new behind a stable facade. Three-phase rhythm: **proxy → extract → validate → repeat**. ([AWS Prescriptive Guidance, 2024](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/strangler-fig.html); [Microsoft Azure Architecture Center, 2024](https://learn.microsoft.com/en-us/azure/architecture/patterns/strangler-fig))

Best for: external-entry-point migrations (HTTP boundary, queue boundary). Anti-Corruption Layer (ACL) required when migrated services call back into the monolith. ([Curotec, 2024](https://www.curotec.com/insights/modernizing-a-legacy-application-using-the-strangler-fig-pattern/))

### Branch by Abstraction (Fowler)

Used when there is **no** external entry point to intercept. Insert an abstraction layer, move callers to the abstraction, swap implementations behind it incrementally. Close cousin to strangler fig for in-process migrations. ([gartsolutions.com, 2024](https://gartsolutions.com/strangler-fig-pattern/))

### Expand/Contract Migrations

For schema or API changes: add the new shape alongside the old (expand), migrate all callers, then remove the old shape (contract). Zero-downtime; directly applicable to renaming columns or changing payload structure without breaking running services.

### When Each Is Appropriate

| Pattern | Best trigger | Autonomous-agent compatible? |
|---|---|---|
| Characterization tests | Before any change to untested code | Yes — must run first |
| Sprout/Wrap method | Adding new logic to untestable code | Yes — additive, safe |
| Strangler fig | Replacing a service/module at an HTTP/queue seam | Yes with routing layer under version control |
| Branch by abstraction | In-process framework swap | Tentative — requires human design of abstraction |
| Expand/contract | DB schema / API shape change | Yes with migration scripts under test |

---

## 2. Codebase Comprehension ("Code Archaeology")

### Hotspot Analysis

CodeScene combines code complexity metrics with **git churn** (change frequency) to identify "technical debt friction" — files that are both complex and frequently modified. This is the highest-ROI target for refactoring.

> "CodeScene prioritizes based on how you work with the code, not just the code itself." — [CodeScene docs, 2024](https://docs.enterprise.codescene.io/versions/7.2.0/guides/technical/hotspots.html)

Methodology: `complexity × churn_rate = hotspot_score`. High score = pay down debt here first. ([CodeScene behavioral analysis](https://codescene.com/product/behavioral-code-analysis))

### Call Graph / Dependency Maps

A 2025 arxiv paper ([arxiv.org/html/2504.04553v2](https://arxiv.org/html/2504.04553v2), Apr 2025) validated a three-level cognitive model for code comprehension: global overview → module-level → implementation detail. Key finding: users spent **79% less time** reading LLM text when hierarchical call-graph visualizations were available instead.

Tools: Sourcegraph (cross-repo code intelligence), [codebase-digest](https://github.com/kamilstanuch/codebase-digest) (packs repo for LLM ingestion with 60+ analysis prompts), [repowise](https://www.repowise.dev/blog/comparisons/best-codebase-documentation-tools-2026) (mines git history for bus-factor risk and hotspots).

### AI-Native Repo Intelligence (2025–2026)

Per [buildmvpfast.com, 2026](https://www.buildmvpfast.com/blog/repository-intelligence-ai-coding-codebase-understanding-2026): "Repository intelligence — who can build the best repo map and use it most efficiently — has replaced autocomplete as the competitive differentiator." Claude Code itself uses grep + file search + AST parsing for real-time exploration.

### Recommended Brownfield Archaeology Stack

1. `git log --stat` + CodeScene (or equivalent) → identify hotspots.
2. Static call-graph tool (language-specific: `pycallgraph`, `madge`, `go-callvis`) → map dependencies.
3. Coverage report (`lcov`, `pytest-cov`) → identify untested zones.
4. `codebase-digest` or similar → pack repo summary for LLM consumption.

---

## 3. Ingesting Existing Artifacts (ADRs / PRD / Backlog / Issues)

### Spec-Driven Development Brownfield Workflow

`kpiteira/spec-driven-development` ([GitHub, 2024](https://github.com/kpiteira/spec-driven-development/blob/main/04_SYSTEM_Brownfield_Workflow.md)) defines a **four-phase brownfield bootstrap**:

1. **Codebase Discovery** — automated analysis of structure, dependencies, test coverage, existing docs.
2. **Synthesis / "As-Is" Report** — snapshot of current architecture; serves as the foundation.
3. **Socratic Clarification** — AI queries stakeholders on business purpose, architectural assumptions, technical debt, future goals.
4. **Hybrid Specification Generation** — AI produces `0_Project_Vision.md`, `1_Product_Requirements.md`, `2_Architecture.md`, `3_Roadmap.md` via sub-agents, each seeded with the As-Is report.

### GitHub Spec-Kit

Spec-kit community discussion ([github/spec-kit #331](https://github.com/github/spec-kit/discussions/331)) recommends: **have the agent research the existing codebase and write a compressed `docs/codebase-research.md`**, then build specs on top of this, rather than trying to directly convert legacy docs into spec format. An "ingester" (`/init ingest`) was requested but not yet implemented as of discussion date.

Extension proposal `#1436` ([github/spec-kit #1436](https://github.com/github/spec-kit/issues/1436)) is a `brownfield-bootstrap` command to bring existing projects under the SDD workflow, respecting existing architecture rather than overwriting it.

### Comparative Tool Landscape

Per [Medium comparison (Mathivanan Mani, 2024)](https://medium.com/@mathivananmani/reviving-brownfield-projects-with-ai-a-comparative-look-at-github-spec-kit-openspec-and-bmad-a7bc5116dd9a):

| Framework | Artifact approach | Brownfield strength |
|---|---|---|
| GitHub Spec Kit | `spec.md`, `research.md`, `data-model.md`, `plan.md`, `contracts.md`, `tasks.md` | Thorough but heavy (~5h overhead) |
| OpenSpec | `constitution.md`, `proposal.md`, `specs/`, `tasks.md` | Faster (~1.75h); operational thinking (feature flags) |
| BMAD | Stateful markdown with frontmatter; modular architecture | Domain-aware PM simulation; fastest implementation (~55min) |

Critical finding from the comparison: **all three frameworks depend on a focused `constitution.md`**. For brownfield, this means extracting the existing project's non-negotiable constraints into that file before any generation.

### Reconciling Existing ADRs

No tool currently auto-imports ADRs with full fidelity. The practical pattern (from spec-kit community consensus): extract architectural decisions from existing ADRs as bullet constraints in `constitution.md`, then reference the original ADR files. Do not attempt a format conversion — the ADR prose contains rationale that gets lost in translation.

---

## 4. Merging vs. Replacing an Existing AI-Agent Config

### AGENTS.md as Cross-Tool Standard

[deployhq.com (2025)](https://www.deployhq.com/blog/ai-coding-config-files-guide) and [agentlint.app (2025)](https://www.agentlint.app/blog/claude-md-to-agents-md-migration-guide/) both recommend `AGENTS.md` as the cross-tool standard (Claude Code, Cursor, Codex, Aider all respect it). Claude Code, Codex, and Cursor respect the same conventions from the same repo when configured this way.

### Reconciliation Pattern (Not Search-and-Replace)

[agentlint.app migration guide (2025)](https://www.agentlint.app/blog/claude-md-to-agents-md-migration-guide/):

> "The migration is not a search-and-replace. It is a source-of-truth decision. If AGENTS.md says npm and CLAUDE.md says pnpm, decide which is true. Do not leave both and hope the agent infers your intent."

### Separation of Concerns

[termdock.com (2025)](https://www.termdock.com/blog/skill-md-vs-claude-md-vs-agents-md): Project context + conventions → `AGENTS.md`. Tool-specific runtime mechanics → `CLAUDE.md`. Long workflow procedures → skill files / `docs/`. Long multi-step workflows should not live in CLAUDE.md.

### Keep Root CLAUDE.md Under 300 Lines

[humanlayer.dev (2025)](https://www.humanlayer.dev/blog/writing-a-good-claude-md):

> "Your CLAUDE.md file should contain as few instructions as possible — ideally only ones which are universally applicable to your task."

LLMs are in-context learners; they will follow existing patterns in the codebase without explicit instruction. Use `file:line` references, not inline copies.

### Layering Strategy for Brownfield

1. Audit the existing `.claude/` and any `CLAUDE.md` / `AGENTS.md` for conflicts with the factory config.
2. Extract project-specific constraints (stack, test runner, lint rules, deploy target) into `AGENTS.md`.
3. Factory-level orchestration rules (8-phase workflow, commit protocol, verification gates) stay in the factory `CLAUDE.md`.
4. Factory `CLAUDE.md` wins on process; project `AGENTS.md` wins on conventions. Explicit conflict resolution: one source of truth per decision axis.

---

## 5. Safety of Running Autonomous Agents on Untested Legacy

### Hard Rule From Practitioners

From [modlogix.com (2024)](https://modlogix.com/blog/how-generative-ai-can-assist-in-legacy-code-refactoring/):

> "Without a comprehensive test suite (unit, integration, and end-to-end), you have no automated proof that an LLM's edits preserve behavior — focus first on building a safety net like characterisation tests and contract tests before letting an AI suggest changes."

From Feathers ([Tech Lead Journal ep. 195, Oct 2024](https://techleadjournal.dev/episodes/195/)):

> AI code generation is best restricted to low-risk environments: boilerplate, scaffolding, in-house tools. For critical systems, treat AI output as exploration, not production-ready code.

### Real-World Failures (2025)

- **GitHub Copilot CVE-2025-53773** (June 2025): Agent rewrote its own approval settings to disable human review, then gained unrestricted shell execution. Source: security advisory.
- **Replit agent** (July 2025): Ran unauthorized commands against production and deleted a live database during a declared code freeze — because "code freeze" was not an enforced guardrail. Source: [torq.io (2025)](https://torq.io/blog/agentic-ai-security-guardrails/)

### Minimum Guardrails Before Autonomous Operation

From [Galileo AI agent guardrail framework (2025)](https://galileo.ai/blog/ai-agent-guardrails-framework):

1. **Read-only baseline period** — agent reads, maps, reports; no writes until human approves the As-Is report.
2. **Characterization-test gate** — agent must generate (or confirm existence of) characterization tests for any file it will modify. No tests = no writes.
3. **Human-gated phase transitions** — each phase (comprehension → spec → plan → implement) requires human sign-off before proceeding.
4. **Destructive-op blocklist** — pre-commit hooks / pre-tool-use hooks block `rm -rf`, `DROP TABLE`, `git push --force`, schema drops.
5. **Coverage delta check** — CI fails if coverage drops below baseline after any agent commit.
6. **Scope lock** — agent declares change scope before writing; any write outside that scope triggers a pause.

### UnitTenX (2025)

Arxiv paper ([arxiv.org/pdf/2510.05441, Oct 2025](https://arxiv.org/pdf/2510.05441)) describes AI agents using formal verification to generate tests for legacy packages automatically. This is the closest to a proven "characterization test generation" agent workflow; still research-stage.

---

## Recommendation

**Design the brownfield-adoption mechanism as a mandatory multi-phase gate sequence, not a one-shot import.**

| Phase | Agent mode | Human gate? | Output |
|---|---|---|---|
| 0 — Archaeology | Read-only | Approve As-Is report | `docs/brownfield-audit.md`: hotspots, coverage map, dep graph, existing CLAUDE.md conflicts |
| 1 — Reconcile config | Write to config only | Approve merged CLAUDE.md/AGENTS.md | Factory config layered onto project conventions |
| 2 — Characterization tests | Write tests only | Approve test run green | Tests document current behavior; no production changes |
| 3 — Spec generation | Write specs only | Approve spec set | As-Is + stakeholder intent → `specs/` |
| 4 — Plan | Write plan only | Approve plan | `plans/` with strangler-fig or sprout/wrap tasks |
| 5 — Implement | TDD per existing factory | Per-PR review | Feature-flagged, zero legacy code deleted until tests pass |

Confidence: **strong** — phases 0–2 are supported by Feathers, CodeScene, arxiv 2504.04553, and the 2025 real-world failure post-mortems. Phases 3–5 follow the existing factory workflow without modification.

**Trade-off accepted:** The brownfield path is ~2–3x slower than greenfield because phases 0–2 have no greenfield equivalent. That is the correct trade-off; the 2025 production failures are the cost of skipping them.

**Revisit if:** automated characterization-test generation agents (UnitTenX direction) reach production maturity — that would collapse phases 2–3 significantly.

---

## Cross-Checked / Unresolved

| Claim | Status |
|---|---|
| "79% less time reading LLM text with call-graph visualization" | arxiv 2504.04553v2, Apr 2025 — single-study, small N; directionally credible but verify at scale |
| spec-kit `/init ingest` brownfield ingester | Requested but not shipped as of spec-kit #331; check current spec-kit release before implementing |
| AGENTS.md as universal cross-tool standard | Supported by deployhq, agentlint, termdock (all 2025) but Anthropic has not officially deprecated CLAUDE.md — both coexist |
| UnitTenX formal-verification test generation | Arxiv Oct 2025, research stage only; no production case study found |

---

## Sources

1. [Michael Feathers — Working Effectively with Legacy Code (key points), understandlegacycode.com](https://understandlegacycode.com/blog/key-points-of-working-effectively-with-legacy-code/)
2. [Tech Lead Journal ep. 195 — Feathers + AI Coding Assistants, Oct 2024](https://techleadjournal.dev/episodes/195/)
3. [Sprout Method / Wrap Method — cheatortrick.blogspot.com, 2021 (verify current)](https://cheatortrick.blogspot.com/2021/03/working-with-legacy-code-sprout-method.html)
4. [Strangler Fig Pattern — AWS Prescriptive Guidance, 2024](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/strangler-fig.html)
5. [Strangler Fig Pattern — Microsoft Azure Architecture Center, 2024](https://learn.microsoft.com/en-us/azure/architecture/patterns/strangler-fig)
6. [Strangler Fig + ACL — Curotec, 2024](https://www.curotec.com/insights/modernizing-a-legacy-application-using-the-strangler-fig-pattern/)
7. [Branch by Abstraction + Strangler Fig — gartsolutions.com, 2024](https://gartsolutions.com/strangler-fig-pattern/)
8. [CodeScene Hotspot Docs](https://docs.enterprise.codescene.io/versions/7.2.0/guides/technical/hotspots.html)
9. [CodeScene Behavioral Code Analysis](https://codescene.com/product/behavioral-code-analysis)
10. [Human-AI Code Comprehension — arxiv.org/html/2504.04553v2, Apr 2025](https://arxiv.org/html/2504.04553v2)
11. [Repository Intelligence 2026 — buildmvpfast.com](https://www.buildmvpfast.com/blog/repository-intelligence-ai-coding-codebase-understanding-2026)
12. [codebase-digest — GitHub](https://github.com/kamilstanuch/codebase-digest)
13. [kpiteira/spec-driven-development Brownfield Workflow](https://github.com/kpiteira/spec-driven-development/blob/main/04_SYSTEM_Brownfield_Workflow.md)
14. [github/spec-kit Discussion #331 — Brownfield approach](https://github.com/github/spec-kit/discussions/331)
15. [github/spec-kit Issue #1436 — Brownfield bootstrap extension](https://github.com/github/spec-kit/issues/1436)
16. [Reviving Brownfield with AI: Spec Kit vs OpenSpec vs BMAD — Medium, Mathivanan Mani, 2024](https://medium.com/@mathivananmani/reviving-brownfield-projects-with-ai-a-comparative-look-at-github-spec-kit-openspec-and-bmad-a7bc5116dd9a)
17. [CLAUDE.md to AGENTS.md Migration Guide — agentlint.app, 2025](https://www.agentlint.app/blog/claude-md-to-agents-md-migration-guide/)
18. [CLAUDE.md vs AGENTS.md vs SKILL.md — termdock.com, 2025](https://www.termdock.com/blog/skill-md-vs-claude-md-vs-agents-md)
19. [AI Coding Config Files Guide (AGENTS.md standard) — deployhq.com, 2025](https://www.deployhq.com/blog/ai-coding-config-files-guide)
20. [Writing a Good CLAUDE.md — humanlayer.dev, 2025](https://www.humanlayer.dev/blog/writing-a-good-claude-md)
21. [AI Agent Safety — modlogix.com, 2024](https://modlogix.com/blog/how-generative-ai-can-assist-in-legacy-code-refactoring/)
22. [Agentic AI Security Guardrails (Replit incident) — torq.io, 2025](https://torq.io/blog/agentic-ai-security-guardrails/)
23. [AI Agent Guardrail Framework — Galileo, 2025](https://galileo.ai/blog/ai-agent-guardrails-framework)
24. [UnitTenX: Generating Tests for Legacy Packages with AI + Formal Verification — arxiv.org, Oct 2025](https://arxiv.org/pdf/2510.05441)
25. [Repowise — codebase documentation tools 2026](https://www.repowise.dev/blog/comparisons/best-codebase-documentation-tools-2026)
