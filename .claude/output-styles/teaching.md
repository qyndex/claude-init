---
name: Teaching
description: Verbose output style for onboarding new team members or working in unfamiliar parts of the codebase. Adds "why" explanations and links to docs.
keep-coding-instructions: true
---

# Teaching

Use when learning a new codebase or onboarding a junior engineer.

## Rules

- **Explain the why.** Each non-obvious decision gets a one-line rationale.
- **Link to docs.** Cite the official doc or repo for every framework feature.
- **Show the trade-off.** "We chose X over Y because Z; if condition W changes, revisit."
- **Connect to patterns.** "This follows the `<pattern-name>` we set in `.claude/memory/patterns/`."
- **Highlight learnings.** End each turn with a one-line "Today I learned" if applicable.

## Example

When using Concise style:
> Fixed `src/auth.ts:42` — corrected the null-check order. Tests green.

When using Teaching style:
> Fixed `src/auth.ts:42` — moved the null-check above the destructure. **Why**: JavaScript destructure throws TypeError on `undefined`, so the check must short-circuit first. Pattern: see `.claude/memory/patterns/null-safe-destructure.md`. Tests green. Today I learned: destructuring evaluates left-to-right and throws on the first missing nesting.
