---
name: animation-discipline
description: Use when adding transitions, hover states, scroll triggers, motion. Enforces easing/duration discipline, prefers-reduced-motion, GPU-friendly properties only, View Transitions API for routes. Round 9 C.
when_to_use: User asks for "animation", "transition", "motion", "framer-motion", "animate"; new interactive component; scroll-triggered behavior.
model: sonnet
disable-model-invocation: false
last_verified: 2026-05-28
---

# Animation Discipline

## Mandate

Motion should clarify, not distract. Discipline beats vibes.

## Decisions encoded

### Easing

| Context | Easing |
|---|---|
| Element entrance | `easeOut` (decelerate; feels arriving) |
| Element exit | `easeIn` (accelerate; feels leaving) |
| State transition | `easeInOut` |
| Spring (interactive) | `useSpring` with stiff/damp values |
| Never | `linear` for UI motion |

### Duration

| Type | Duration |
|---|---|
| Hover, focus, tooltip | 100-200ms |
| Modal open, dropdown | 200-300ms |
| Page/route transition | 400-600ms |
| Hero or showcase animation | 800ms-1.5s |
| Never | >2s for non-decorative |

### GPU-friendly only

Animate ONLY:
- `transform` (translate, scale, rotate)
- `opacity`
- `filter` (sparingly — blur is expensive on mobile)

NEVER animate:
- `width` / `height` / `top` / `left` / `padding` / `margin` (layout thrash)
- `box-shadow` directly (use a pseudo-element with opacity)
- `background-color` on large surfaces (paint cost)

### Reduced motion

Wrap or short-circuit every animation:

```tsx
import { useReducedMotion } from 'framer-motion';

const prefersReduced = useReducedMotion();
<motion.div animate={prefersReduced ? {} : { opacity: 1, y: 0 }} />
```

CSS equivalent:
```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; }
}
```

### Library choice

- **Framer Motion** for stateful component motion (modals, layouts, gestures)
- **CSS transitions** for hover/focus (no JS overhead)
- **View Transitions API** for cross-route transitions (when browser supports)
- **GSAP / ScrollTrigger** only when scroll-driven storytelling justified
- **three.js / r3f** for 3D — separate skill (`creative-web`)

## Hard rules

- Respect `prefers-reduced-motion`
- GPU-only properties
- Easing per the table; never `linear` for entrance/exit
- Duration per the table; never >2s for non-decorative
- One library per animation domain (don't mix framer-motion + react-spring)

## Common pitfalls

1. **Animating `height: auto`** — physically impossible without measurement; use `max-height` trick or framer-motion's `layout` prop
2. **Forgetting `will-change`** for transform-heavy elements (rare, but useful for paint promotion)
3. **Animations triggered before mount** — wrap in `useEffect` or use `initial` prop properly
4. **Easing chosen by name only** — `easeIn` for entrance feels WRONG; verify direction matters
5. **Not testing on slow mobile** — what looks smooth on M1 Mac may jank on $200 Android

## Done means

- `prefers-reduced-motion` respected
- All durations within table
- All animated properties GPU-friendly
- Mobile tested at 4x CPU throttle (Chrome DevTools)
