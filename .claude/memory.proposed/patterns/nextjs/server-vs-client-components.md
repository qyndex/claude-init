---
name: server-vs-client-components
description: Default to RSC; mark 'use client' only at leaf interactivity
metadata:
  type: pattern
  stack: nextjs
slug: server-vs-client-components
status: established
Owner: "@Shravan Jha"
written_by: seed-patterns
written_at: 2026-05-28
last_verified: 2026-05-28
verified_in_commits: []
recurred_anti: 0
---

# Server vs Client Components

## When to use
Every new Next.js (App Router) component starts as a Server Component. Only mark `"use client"` at leaf nodes that need browser APIs or hooks (forms, event handlers, useState/useEffect).

## Why
- Smaller client bundle
- Direct DB/API access without intermediate route
- Better SEO via streamed HTML

## Canonical example
```tsx
// app/(app)/dashboard/page.tsx — Server Component (no "use client")
import { getUser } from "@/lib/db";
import { UserMenu } from "./UserMenu";  // imported Client Component

export default async function Dashboard() {
  const user = await getUser();
  return <UserMenu user={user} />;
}
```

## Anti-pattern
`"use client"` on the root layout — kills the entire RSC tree.

## When NOT to use
Pages Router projects; libraries pre-React-18.
