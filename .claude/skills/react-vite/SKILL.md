---
name: react-vite
description: Conventions, pitfalls, and canonical patterns for a React + Vite SPA. Invoke when editing files under a project whose atlas detected `vite.config.{js,ts,mjs}` + React, or when the user explicitly asks for React+Vite advice. Covers component patterns, state-management decisions, Vitest+RTL+Playwright testing, build optimization, and the top hooks pitfalls.
when_to_use: When the project is React + Vite; covers hooks idioms, lazy/Suspense routes, Zustand vs Redux, Vitest+RTL+Playwright triad.
disable-model-invocation: false
---

# React + Vite

## When to invoke
- Atlas `frameworks.web == "Vite-React"` (see `.claude/skills/detect-stack/SKILL.md`).
- Files match `vite.config.*`, `src/**/*.tsx`, `index.html` at repo root.
- User says "React app", "Vite project", or pastes a `vite.config.ts`.

## Key conventions
1. **Vite as the only bundler.** Don't bolt Webpack/Rollup on top. Use `import.meta.env` (not `process.env`) and prefix env vars `VITE_*`.
2. **File-based but explicit routing.** Pick one router (`react-router-dom` v6 or `@tanstack/router`) and stick to it. No mixing.
3. **State ladder** (start low, climb only on evidence):
   - `useState` / `useReducer` for local
   - URL + `useSearchParams` for shareable
   - React Query (`@tanstack/react-query`) for server state — never `useEffect` + `fetch`
   - Zustand for cross-cutting client state (auth, theme, toasts). Prefer Zustand over Redux Toolkit for new projects unless time-travel debugging is required. Jotai if your model is atom-graph-shaped.
4. **Component shape.** Function components only. Composition over inheritance. No `React.FC` (cuts off `children` typing). Co-locate `Component/{Component.tsx, Component.test.tsx, Component.module.css, index.ts}`.
5. **`useEffect` is an escape hatch, not a default.** If you're using it for derived state, transformation, or fetching — you're holding it wrong. Read https://react.dev/learn/you-might-not-need-an-effect.
6. **Tests: Vitest + Testing Library + Playwright.** Vitest unit, RTL component, Playwright user journey. No Enzyme. No `act()` warnings ignored.
7. **Build optimization on by default.** Vite tree-shakes ESM automatically. Use `React.lazy` + `Suspense` for routes; `manualChunks` only when you've measured.
8. **TypeScript strict.** `strict: true`, `noUncheckedIndexedAccess: true`. Use `satisfies` for config objects.

## Canonical structure
```
src/
  main.tsx               # ReactDOM.createRoot + <App />
  App.tsx                # router + providers
  routes/                # one file per route
    index.tsx
    dashboard.tsx
  components/            # shared, presentational
    Button/Button.tsx
  features/              # feature folders (vertical slice)
    auth/{api,hooks,components,types}
    todos/{api,hooks,components,types}
  lib/                   # framework-agnostic helpers
  hooks/                 # cross-feature custom hooks
  styles/tokens.ts       # design tokens (see rules/frontend.md)
  test/setup.ts          # vitest setup, jest-dom matchers
vite.config.ts
vitest.config.ts
playwright.config.ts
```

## Common pitfalls
1. **Stale closures in event handlers.** `useEffect(() => { socket.on('msg', () => setX(x+1)) }, [])` — `x` is frozen. Fix with functional updater `setX(p => p+1)` or include `x` in deps.
2. **Setting state after unmount.** Async fetch resolving on an unmounted component. Use `AbortController` in the effect cleanup or migrate to React Query (handles it).
3. **`useEffect` dependency lies.** Exhaustive-deps is not optional — install `eslint-plugin-react-hooks` and treat warnings as errors.
4. **Re-render storms from new object/array identity.** `<Child config={{a:1}} />` makes a new object every render. Hoist or `useMemo`.
5. **Mixing Vite env with `process.env`.** Vite injects `import.meta.env` at build. `process.env` is undefined → silent `undefined`. Wrap in a typed module: `src/lib/env.ts` reading `import.meta.env.VITE_*` with Zod.

## References
- Vite: https://vitejs.dev
- React (you might not need useEffect): https://react.dev/learn/you-might-not-need-an-effect
- React Query: https://tanstack.com/query/latest
- Zustand: https://github.com/pmndrs/zustand
- Vitest: https://vitest.dev
- Testing Library: https://testing-library.com/docs/react-testing-library/intro/

## Hello world (TDD)
```tsx
// src/features/counter/Counter.test.tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Counter } from './Counter'
test('increments on click', async () => {
  render(<Counter />)
  await userEvent.click(screen.getByRole('button', { name: /increment/i }))
  expect(screen.getByText(/count: 1/i)).toBeInTheDocument()
})

// src/features/counter/Counter.tsx
import { useState } from 'react'
export function Counter() {
  const [c, setC] = useState(0)
  return <button onClick={() => setC(p => p + 1)}>Increment — count: {c}</button>
}
```
