---
paths:
  - "src/web/**/*"
  - "src/frontend/**/*"
  - "app/**/*.tsx"
  - "app/**/*.jsx"
  - "components/**/*.tsx"
  - "components/**/*.jsx"
  - "pages/**/*"
  - "**/*.module.css"
  - "**/*.module.scss"
  - "tailwind.config.*"
---

# Frontend rules

> Loaded only when Claude is editing UI code. Customize per project — these are starter defaults.

## Design system

- **No bespoke colors / spacing / typography in components.** Use design tokens from your tokens file (e.g., `src/styles/tokens.ts`, `src/theme/`, Tailwind config). If a token doesn't exist for what you need, add it to the tokens file first, then use it.
- **No `style={{...}}` inline styles.** Use CSS modules, Tailwind classes, or a styled-system. Inline styles bypass design tokens and dark-mode handling.
- **No magic numbers** for spacing, sizing, or breakpoints. Reference design tokens or the system's scale (e.g., `space-4`, `text-lg`).

## Accessibility

- **Every interactive element** has a discernible name (`aria-label`, visible text, or `aria-labelledby`).
- **Forms** have `<label>` elements (or `aria-label`) associated with each input.
- **Color is never the sole signal** — pair color with text, icon, or pattern.
- **Focus visible** is never disabled. If you suppress the default outline, replace with a high-contrast custom focus ring.
- Run `axe-core` or `playwright a11y` against new components before completion.

## Performance budget

- Initial JS payload: ≤ 200 KB gzipped (Lighthouse target). Code-split anything heavier.
- LCP ≤ 2.5s on a 4G connection. Use `next/image` or equivalent for image optimization.
- No `useEffect` with empty deps that fetches data — use the framework's data layer (RSC, loaders, react-query).

## Component conventions

- **Server components by default** (Next.js App Router, Remix). Mark client with `"use client"` only when interactivity is needed.
- **Co-locate** component + styles + test in the same folder: `Button/{Button.tsx, Button.module.css, Button.test.tsx, index.ts}`.
- **No prop drilling beyond 2 levels.** Use Context or a state manager.
- **No `any` in component props.** Define an interface or use existing types.

## Anti-AI-slop (from anthropic frontend-design skill)

- No purple-on-white gradient hero. No "Modern, Clean, Minimal" copy. No `Inter` font by default — pick something distinctive.
- Force a conceptual direction before styling: brutal-minimal / maximalist / retro-futuristic / editorial / art-deco. State it in the spec.
- Pair distinctive display fonts with refined body fonts. Use Motion library for animations, not raw CSS keyframes for non-trivial motion.

## Visual regression

- Storybook stories required for any new shared component.
- Chromatic / Percy / Argos diff at PR time (configured in `.github/workflows/`).

## Browser support matrix

State your support range in `package.json browserslist` and follow it. Don't ship features that break on listed targets.
