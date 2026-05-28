---
name: creative-web
description: Use when a spec EXPLICITLY warrants "wow factor" beyond default Tailwind — parallax, 3D, generative art, scroll-triggered storytelling. Hard-guardrailed by Lighthouse perf ≥ 90, a11y = 100. Round 9 C.
when_to_use: Spec asks for "stunning", "interactive", "creative", "3D", "parallax", "scroll-triggered", "playground", "art-directed"; landing pages where visual impact is the ask.
model: opus
disable-model-invocation: false
last_verified: 2026-05-28
---

# Creative Web

## Mandate

When the spec calls for visual ambition — interactive surfaces, 3D scenes, scroll storytelling, generative art — execute with discipline. The wow must NEVER come at the cost of accessibility, performance, or core UX.

## Tools allowed

- **framer-motion** — stateful component motion (with `useReducedMotion`)
- **three.js / @react-three/fiber + drei** — 3D scenes
- **GSAP + ScrollTrigger** — scroll-driven storytelling
- **p5.js** / canvas / WebGL fragment shaders — generative art
- **spline-react** — designer-imported 3D scenes
- **lottie-react** — vector animation playback

## Hard guardrails (CI-enforced)

| Metric | Target | Enforced by |
|---|---|---|
| Lighthouse perf | ≥ 90 | lighthouse.yml |
| Lighthouse a11y | 100 | lighthouse.yml |
| LCP | ≤ 2.5s | perf-budget.yml |
| FID/INP | ≤ 200ms | perf-budget.yml |
| Bundle | < 500KB above-the-fold | bundle-budget script |

If creative payload breaks these — REJECT. Either downsize or move below-the-fold.

## Discipline rules

- **Lazy-load all heavy payloads.** `dynamic(() => import('./Scene'), { ssr: false })` for client-only 3D.
- **Static fallback above the fold.** Hero image + headline render INSTANTLY; interactive scene loads after.
- **Keyboard-operable.** All interactive surfaces respond to Tab + Enter/Space, not just mouse.
- **ARIA descriptions on non-decorative canvas.** Tell screen readers what they're missing.
- **`prefers-reduced-motion` respected.** Static alternative for the whole creative payload.
- **Document the CONCEPT.** Sibling `CONCEPT.md` next to the component: one paragraph on what it is and why.

## Procedure

1. Read spec; confirm creative ambition is the ASK, not a wish
2. Sketch concept in `CONCEPT.md`
3. Decide tech: framer-motion / r3f / GSAP / p5 / spline
4. Static fallback FIRST — ship without interactivity
5. Add creative layer behind `dynamic(() => …, { ssr: false })`
6. Add `prefers-reduced-motion` short-circuit
7. Add keyboard handlers + ARIA descriptions
8. Run Lighthouse + axe locally; iterate until thresholds met
9. Commit with CONCEPT.md + visual diff (Playwright screenshot in verify/)

## Anti-patterns (immediate reject)

- 3D scene in initial bundle (LCP killer)
- Canvas without ARIA description
- No `prefers-reduced-motion` opt-out
- Scroll-jacking that fights browser scroll
- Particle systems on low-end mobile (no LOD or quality switch)
- Lottie files >100KB (use SVG + framer-motion instead)

## References

- React Three Fiber: https://r3f.docs.pmnd.rs/
- GSAP ScrollTrigger: https://gsap.com/scrolltrigger/
- Spline: https://spline.design/
- p5.js: https://p5js.org/

## Done means

- Lighthouse perf ≥ 90, a11y = 100
- LCP ≤ 2.5s on 4G
- `prefers-reduced-motion` works
- Keyboard-operable
- `CONCEPT.md` documents the artistic intent
