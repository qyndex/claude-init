---
name: front-end-design
description: Use when designing a new UI, redesigning a screen, building a landing/marketing page, or making something look better. Orchestrates the visual-craft skills (tailwind-discipline, typography, animation-discipline, image-generation, creative-web). Round 9 C.
when_to_use: User asks for "design", "landing page", "redesign", "hero", "layout", "make it look better"; new UI components; any visual surface change.
model: opus
disable-model-invocation: false
last_verified: 2026-05-28
---

# Front-End Design

## Mandate

Force a CONCEPTUAL DIRECTION before styling. The output should look intentional, not "generated default Tailwind." Apply Anthropic's Artifact aesthetic: clean, opinionated, content-forward.

## Procedure

1. **State the concept FIRST** (one paragraph in the spec):
   - Mood: editorial / brutalist / maximalist / retro-futuristic / minimalist / art-deco / playful
   - Voice: serious / friendly / technical / approachable
   - Hero archetype: dashboard / marketing / app / form / data / playground
   - Reference site(s) for inspiration
2. **Read design tokens** from `src/styles/tokens.ts` (or Tailwind config). Add missing tokens to the file FIRST, then use them — no inline arbitrary values.
3. **Sketch with components** before pixels. List the components and their hierarchy.
4. **Required states per screen** (no "lonely success state"):
   - loading
   - empty
   - error
   - partial-data
   - success
5. **Responsive breakpoints**: mobile-first; sm/md/lg/xl/2xl. Design at 375px AND 1440px minimum.
6. **Apply sister skills**:
   - `tailwind-discipline` — utility class hygiene
   - `typography` — type scale + measure
   - `animation-discipline` — motion design
   - `image-generation` — when raster/illustration needed
   - `creative-web` — when "wow factor" justified

## Hard rules

- **Concept BEFORE styling.** "Modern minimal" is not a concept — that's a default.
- **Design tokens from `tokens.ts`.** No magic hex codes, no inline arbitrary values without comment.
- **Required states.** Loading / empty / error / success are non-negotiable.
- **Dark mode is default-on.** Use Tailwind `class` strategy + semantic tokens (`--surface-1`, NOT `gray-900`).
- **a11y is invariant.** Axe-core in CI must pass (Round 8 audit proposed this).
- **No AI-slop placeholders.** Every visual choice ties to the spec's user story or concept.

## Anti-patterns (immediate reject)

- Lorem ipsum in shipped UI
- Default Tailwind blues + grays everywhere
- 1000px-wide text lines (no `max-w-prose`)
- Fixed pixel font sizes everywhere (no responsive scale)
- Hover states without focus states (a11y fail)
- Animations without `prefers-reduced-motion` opt-out

## When to delegate to designer agent

If a spec explicitly says "high-artistic, modern, creative" or "stunning landing page" or similar, hand off to `designer` agent (`.claude/agents/specialists/designer.md`) — they own this skill family and can iterate.

## Done means

- Concept statement documented in spec
- Required states all implemented
- Mobile + desktop both look intentional
- Axe + Lighthouse pass
- Reviewer signs off on visual craft, not just code correctness
