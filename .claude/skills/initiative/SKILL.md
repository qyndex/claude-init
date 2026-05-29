---
name: initiative
description: "Author or amend a multi-quarter initiative — the program-level artifact above per-feature specs. Use for 3+ month efforts spanning multiple specs, multiple teams, or multiple quarters. An 18-month migration is one initiative; a 2-day feature is not. Spec template's `complexity: XL` should split into an initiative + multiple specs."
when_to_use: User says "this is a multi-quarter program", "initiative", "epic", "18-month migration", "set up the program for", "we need a roadmap for X". Architect agent encounters work that exceeds XL.
argument-hint: "[create|update|status|close|supersede] <id-or-slug>"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite, WebFetch
model: opus
disable-model-invocation: true
---

# Initiative

The artifact above the spec. Bind multi-quarter programs into a coherent thread.

## When to create an initiative vs. a spec

| Signal | Spec | Initiative |
|---|---|---|
| Effort | days–weeks | quarter–year+ |
| Owners | 1-2 engineers | 3+ engineers, sometimes multiple teams |
| Phases | maybe (in plan.md) | required (multiple specs, gated) |
| KR alignment | 1 KR | 1+ KRs |
| Code reach | bounded feature | platform-wide |
| External dependencies | rare | common (legal, vendor, regulatory) |
| Decision cadence | once | monthly review |

**Rule of thumb:** if the spec template's `complexity: XL` feels right *and* the work spans 2+ quarters, that's an initiative. Split it.

## Process

**ALL initiatives use the [[grill-me]] skill for discovery — the decisions cascade. Picking a KR shapes phase breakdown shapes flag namespace shapes spec catalog. Batched questions force premature commitment. Round 5 A2.**

1. **Invoke `grill-me`** with branch order: KR alignment → success metric → phase 0 → phase 1+ → flag namespace → risk register. One question at a time, recommendation + reasoning per question.
2. **Define phases** — each phase ships independently. P0/P1/P2/...; each phase has an exit criterion. Output: filled `## Phases` table.
3. **Catalog specs** — list specs that already exist + specs needed. Output: filled `## Spec catalog`.
4. **Risk register** — top 5 risks, mitigation, owner. Output: filled `## Risks`.
5. **Flag policy** — flag namespace, owner, default cleanup window. Output: filled `## Feature flag policy`.
6. **Save** — `initiatives/active/<id>-<slug>.md` from `initiatives/templates/initiative.md`.
7. **Cross-link** — update `roadmap.md`, link KRs in `OKRs.md`.

In AUTOPILOT context (Cloud Routine / `--bg`): grill-me uses recommendations as defaults and surfaces `[OQ-pending-operator-review]` in the handoff. Initiative status becomes `draft-autopilot-needs-review`, not `approved`.

## Commands

- `/initiative create <slug>` — **grill-me-driven** authoring (one-at-a-time, recommendation per question)
- `/initiative status <id>` — phase progress, % done, risk health
- `/initiative close <id>` — mark shipped/abandoned, archive
- `/initiative supersede <id> --by <new-id>` — link supersession

## Hard rules

- **Every initiative links a KR.** No KR? Either you don't need this initiative or your OKRs are wrong. Don't paper over.
- **Phases must ship independently.** "Phase 1: scaffolding" is not shippable. Rewrite.
- **Risks have owners.** A risk without an owner is a wish.
- **Flag namespace is declared.** Without it, flags collide across initiatives.
- **Spec catalog stays current.** Architect agent updates it when authoring/closing a spec under the initiative.

## When an initiative closes

1. Mark `status: shipped` (or `abandoned` / `superseded`).
2. Move `initiatives/active/<file>` → `initiatives/archive/`.
3. Update `roadmap.md` to reflect.
4. Write a `.claude/memory/decisions/` entry capturing the program-level lessons.
5. Update `OKRs.md` — close out KR if applicable.

## References

- Spec Kit (per-feature spec): https://github.com/github/spec-kit
- Shape Up (cycles): https://basecamp.com/shapeup
- Now/Next/Later roadmaps: https://www.romanpichler.com/blog/the-goal-oriented-product-roadmap/
