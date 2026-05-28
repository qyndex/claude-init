---
name: nextjs
description: Use when project is Next.js (App Router or Pages Router). Covers Server vs Client Components, Server Actions, Suspense boundaries, route handlers, middleware, next/image discipline, revalidation. Round 9 B.
when_to_use: Atlas detects Next.js; user edits app/, pages/, next.config.*, middleware.ts; user mentions RSC, server actions, App Router, Pages Router.
model: sonnet
disable-model-invocation: false
last_verified: 2026-05-28
---

# Next.js

## Mandate

When working in a Next.js codebase, enforce App Router idioms (RSC by default), Suspense + error boundary co-location, `next/image` for all raster, Server Actions for mutations, and pinned framework version.

## Decisions encoded

- **App Router default.** Pages Router only if the project is already there and a migration is out of scope.
- **Server Components by default.** Add `"use client"` ONLY at leaf interactivity (form, hook, event handler).
- **Server Actions for mutations.** No client-side `fetch` to `/api/route` for form posts; use action functions + `revalidatePath`/`revalidateTag`.
- **`next/image` always.** Raw `<img>` is an anti-pattern (no LCP optimization, no AVIF/WebP).
- **Suspense boundaries co-located.** Every route segment ships `loading.tsx` + `error.tsx` next to `page.tsx`.
- **Middleware sparingly.** Only for auth gating, header injection, redirects. NOT for data transforms (use route handlers).
- **Pinned Next version.** No "latest" in package.json; bump deliberately via `/upgrade nextjs --to <ver>`.

## Project structure (App Router)

```
src/app/
├── layout.tsx              # root layout (must export metadata, fonts)
├── page.tsx                # /
├── loading.tsx + error.tsx # global Suspense + error boundaries
├── (marketing)/            # route group (no URL segment)
│   ├── about/page.tsx
│   └── pricing/page.tsx
├── (app)/                  # authed
│   ├── dashboard/
│   │   ├── page.tsx
│   │   ├── loading.tsx
│   │   ├── error.tsx
│   │   └── actions.ts      # Server Actions
│   └── settings/page.tsx
├── api/
│   └── webhooks/route.ts   # route handlers (NOT for app-internal data)
└── middleware.ts           # auth/redirect gating only
```

## Procedure (new feature)

1. Determine route segment + group (`(marketing)`, `(app)`, etc.)
2. Create `page.tsx` (RSC by default) — fetch data with `async`/`await`, no `useEffect`
3. Co-locate `loading.tsx` + `error.tsx`
4. If interactivity needed → split into Client Component leaf, mark `"use client"`
5. Mutations → Server Action in `actions.ts`, return revalidation tag
6. Images → `next/image` with explicit width/height; `priority` for above-fold
7. Test: Playwright covers user journey; Vitest covers Server Action logic

## Hard rules

- Use `next/image` for raster; never `<img>`
- Use `next/font` for fonts; never link to Google Fonts CDN (privacy + perf)
- Use Server Actions for mutations; not `fetch('/api/...')` from forms
- Match React 19's `use()` hook for promise unwrapping in Client Components
- Run `next build` locally before merging — production-only optimizations catch issues `next dev` doesn't
- Pin `next` exact version in package.json; bumps require `/upgrade nextjs`

## Common pitfalls

1. **Adding `"use client"` to the root layout** — kills the whole RSC tree. Apply at leaves only.
2. **`useEffect` in RSC** — won't even compile. Symptom: "useEffect is not defined in server components."
3. **Mutating in route handlers when Server Action would do** — splits the surface area; Server Actions also auto-revalidate.
4. **`<img>` slipping through** — set ESLint rule `@next/next/no-img-element` to error.
5. **Forgetting `revalidatePath`/`revalidateTag` after mutation** — UI stays stale.
6. **Edge runtime for data-heavy work** — Edge has no Node APIs; use `runtime: 'nodejs'` for DB queries.

## References

- Official docs: https://nextjs.org/docs/app
- App Router migration: https://nextjs.org/docs/app/building-your-application/upgrading/app-router-migration
- Server Actions: https://nextjs.org/docs/app/building-your-application/data-fetching/server-actions-and-mutations

## Done means

- All new routes use App Router unless explicitly migrating from Pages
- `next/image` everywhere; no `<img>`
- Suspense + error boundaries co-located with every page
- `next build` passes locally before push
