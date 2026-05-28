---
name: plan
description: Author the technical plan for a spec. Phase 3 of the eight-phase workflow. Produces plans/active/<id>-<slug>.md with architecture, data model, API contracts, dependencies, phasing, risks. Delegate to the architect agent. Modeled on github/spec-kit /speckit.plan.
when_to_use: A spec is approved and code work is about to begin. User says "plan it", "design the implementation", "how would you build X".
argument-hint: "<spec id>"
model: sonnet
allowed-tools: Read, Write, Edit, Glob, Grep, WebFetch, WebSearch, TodoWrite
---

# Plan

Turn an approved spec into an actionable technical plan.

## Process

1. **Read the spec** (`specs/active/<id>-<slug>.md`). Confirm `status: approved`.
2. **Delegate to the architect** agent. They produce `plans/active/<id>-<slug>.md`.
3. **Review the plan** for completeness against the template at `plans/templates/plan.md`.
4. **Validate against the spec** — every acceptance criterion must map to plan elements.
5. **Mark `status: approved`** when complete.

## Plan must contain

- Reference to the spec (`spec: specs/active/<id>-<slug>.md`)
- **Architecture** — components, data flow, sequence diagrams (mermaid if non-trivial)
- **Data model** — entities, schemas, migrations, indexes
- **API contracts** — endpoints, request/response shapes, error codes, auth
- **Dependencies** — new packages (with version + justification), new services, new MCP servers
- **Phasing** — Phase 1, 2, 3 with exit criteria per phase; each phase must be independently shippable
- **Risks** — known unknowns + mitigations
- **Rollback** — how do we revert if Phase N is bad?
- **Observability** — metrics, logs, traces this change adds
- **References** — every non-obvious decision cites a doc/RFC/file/repo

## Hard rules

- **Smallest viable design.** Don't add abstractions for hypothetical needs.
- **Cite evidence.** Every "we chose X because Y" must reference a doc, benchmark, or precedent.
- **Phases ship.** Phase 1 alone should deliver value, not be "scaffolding".
- **Surface risks.** A risk hidden is a risk multiplied.

## Output

```
plans/active/<id>-<slug>.md   (status: draft → approved)
```

After save: "Plan plans/active/<id>-<slug>.md ready. <N> phases, <M> dependencies. Ready for /tasks."
