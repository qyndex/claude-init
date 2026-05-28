---
name: lazy-suspense-route-split
description: Split routes via React.lazy + Suspense; never at leaves
metadata:
  type: pattern
  stack: react-vite
slug: lazy-suspense-route-split
status: established
Owner: "@Shravan Jha"
written_by: seed-patterns
written_at: 2026-05-28
last_verified: 2026-05-28
verified_in_commits: []
recurred_anti: 0
---

# Lazy + Suspense at Route Boundaries

## When to use
Code-split at route boundaries to reduce initial bundle. NEVER at component-tree leaves (causes layout shift).

## Canonical example
```tsx
const Dashboard = React.lazy(() => import("./Dashboard"));
const Settings = React.lazy(() => import("./Settings"));

<Routes>
  <Route path="/dashboard" element={
    <Suspense fallback={<DashboardSkeleton />}>
      <Dashboard />
    </Suspense>
  } />
</Routes>
```

## Anti-pattern
```tsx
// ✗ DO NOT lazy-load every component
const Button = React.lazy(() => import("./Button"));  // causes layout shift
```

## When NOT to use
Components above-the-fold or those rendered hundreds of times — eager-load.
