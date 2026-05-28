---
description: Generate a Mermaid diagram of the codebase, a module, or a data flow from existing code. Saves to docs/diagrams/. Use to keep ARCHITECTURE.md visuals in sync with reality.
argument-hint: "<module path or 'overview'>"
allowed-tools: Read, Glob, Grep, Write, Bash
disable-model-invocation: true
---

# /diagram — Generate a Mermaid diagram

Read the code, produce a Mermaid diagram, save to `docs/diagrams/<slug>-<date>.md`.

## Process

1. Identify the scope from `$ARGUMENTS`:
   - `overview` → top-level architecture (components + relationships)
   - `<path>` → module-internal call/data flow
   - `db` → ER diagram from schemas/migrations
   - `flow:<name>` → sequence diagram for a specific user journey
2. Read the relevant files (imports, type definitions, class declarations, function signatures).
3. Generate the Mermaid (graph TD / sequenceDiagram / erDiagram / classDiagram).
4. Save to `docs/diagrams/<slug>-<YYYY-MM-DD>.md`.
5. Suggest where to link it from (ARCHITECTURE.md, the relevant spec).

## Mermaid type selection

| Argument | Mermaid type |
|---|---|
| `overview` | `graph TD` of components |
| `<path>` | `graph LR` of imports/calls |
| `db` | `erDiagram` |
| `flow:<name>` | `sequenceDiagram` |
| `state:<name>` | `stateDiagram-v2` |

## Output

```
docs/diagrams/<slug>-<date>.md
```

After save: "Diagram at docs/diagrams/<slug>-<date>.md. Add to docs/ARCHITECTURE.md with: `![<title>](diagrams/<slug>-<date>.md)`."

**Important**: do not invent edges. Every arrow in the diagram must correspond to an actual import, call, or relationship in the code.
