---
name: clarify
description: Walk through every open question in a spec and resolve it with the user. Phase 2.5 of the eight-phase workflow. Modeled on github/spec-kit's /speckit.clarify. Run after /specify if any [OQ] tags remain.
when_to_use: A spec has open `[OQ]` items, or user says "clarify the spec", "what's still ambiguous", "let's nail down".
argument-hint: "<spec id or 'latest'>"
model: sonnet
allowed-tools: Read, Write, Edit, Glob, Grep
---

# Clarify

Walk every `[OQ]` line in a spec and resolve it with the user. Update the spec, log decisions in memory if they're project-shaping.

## Process

1. Read `specs/active/<id>-<slug>.md`.
2. Extract every `[OQ]` line into a list.
3. **Decide mode** — Round 5 A2:
   - If `[OQ]` count ≥ 3 AND they cluster around one subsystem (interdependent) → invoke `grill-me` skill (one-at-a-time depth-first interrogation).
   - If `[OQ]` items are orthogonal (different subsystems) → batched mode below.
   - User passed `--grill` → force grill mode regardless.
4. **Batched mode**: present up to 4 questions at a time via `AskUserQuestion`. Format: question + your proposed default + alternatives.
5. **Grill mode**: hand off to `grill-me` skill which walks the dependency graph one question at a time.
6. Update the spec with answers; remove `[OQ]` tags.
7. If an answer is project-shaping (touches the constitution), log it in `.claude/memory/decisions/<date>-<slug>.md`.
8. Update spec status to `approved` if no `[OQ]` remain.

## Hard rules

- **Batch orthogonal; grill interdependent.** A spec with 5 interdependent auth questions deserves grill-me, not 5 batched cards.
- **Provide a default.** Never just ask — propose, then ask "ok or other?".
- **Record decisions.** Anything non-obvious goes into the memory log.
- **Don't invent answers.** If a question requires user input, ask. Don't paper over.
- **AUTOPILOT** — both modes degrade to "use recommendations as defaults, surface as `[OQ-pending-operator-review]` in handoff" when no human is present.
