---
name: react-node
description: Conventions for a React frontend talking to a Node.js backend (Express / Fastify / Hono). Invoke when the atlas shows both a React web framework AND a Node API in the same repo or sibling repos, or when designing the frontend↔backend contract, auth flow, file upload, or WebSocket upgrade. Covers REST-vs-tRPC, JWT-in-httpOnly-cookie rotation, multipart upload, ws handshake, SSR-vs-CSR decision.
when_to_use: When the project is React + Node.js (Express/Fastify/Hono); covers tRPC vs REST decision, JWT-in-httpOnly cookies, WS upgrade from REST.
disable-model-invocation: false
---

# React + Node.js

## When to invoke
- Atlas `frameworks.web` in {Next.js, Vite-React, Remix} AND `frameworks.api` in {Express, Fastify, Hono, NestJS, tRPC}.
- User asks about "frontend talks to backend", "auth flow", "session cookies", "ws upgrade", "file upload", or "SSR vs CSR".

## Key conventions
1. **Contract choice — pick once, document in an ADR.**
   - **tRPC** when both ends are TS and shipped together (monorepo) → end-to-end types, no codegen.
   - **REST + OpenAPI** when the backend has non-TS clients, or you want CDN cache + standard tooling. Generate the TS client from the spec.
   - **GraphQL** only when the client genuinely composes multiple resources per view (rare) — otherwise it's overhead.
2. **Auth: JWT (short access) + rotating refresh, both in `httpOnly; Secure; SameSite=Lax` cookies.** Never store tokens in localStorage. Refresh rotation: server invalidates the old refresh token on use; reuse → revoke all sessions for that family.
3. **CSRF: SameSite=Lax covers most.** Add a double-submit token if you allow `SameSite=None` (cross-site SPA → API). Use the framework's CSRF middleware (`@fastify/csrf-protection`, `csurf` is unmaintained — use `csrf-csrf`).
4. **File uploads: stream, don't buffer.** Use `multer` (Express) / `@fastify/multipart` with `attachFieldsToBody: false` → stream to S3/disk. Reject > N MB at the proxy (nginx/CloudFront), not in app. Validate MIME by reading magic bytes (`file-type`), not the `Content-Type` header.
5. **REST → WebSocket upgrade**: keep the HTTP server, attach `ws` (or `socket.io`) on the same port via the `upgrade` event. Authenticate the WS handshake by reading the same session cookie — never put the JWT in the query string (it ends up in access logs).
6. **SSR vs CSR**: SSR (Next.js / Remix) by default for content-heavy / SEO-sensitive pages. CSR (Vite-React SPA) when it's an internal tool or fully gated app. Don't bolt SSR onto a finished Vite SPA — migrate to a framework that has it.
7. **Backend framework choice**:
   - **Hono** for edge runtimes (Cloudflare Workers, Bun, Deno) — Web-standard `Request`/`Response`.
   - **Fastify** for high-throughput Node — schema-first, faster than Express, plugin model.
   - **Express** when there's an existing ecosystem you must reuse. New code: prefer Hono or Fastify.
   - **NestJS** only if your team genuinely wants Angular-style DI/decorators on the server.
8. **Shared types**: a `packages/shared/` (or `apps/api/contracts/`) folder exports types consumed by both ends. With tRPC, this is free. With REST, generate from OpenAPI.

## Canonical structure (monorepo, pnpm + turbo)
```
apps/
  web/             # React (Vite or Next.js)
  api/             # Node (Fastify or Hono)
    src/
      routes/      # one file per resource
      plugins/     # auth, cors, rate-limit
      lib/db.ts    # Prisma / Drizzle client
      lib/auth.ts  # JWT signing, cookie helpers
      ws/          # socket handlers
      server.ts    # entrypoint
packages/
  shared/          # zod schemas, types, error codes
  ui/              # if shared components
turbo.json
pnpm-workspace.yaml
```

## Common pitfalls
1. **JWT in `localStorage`** — exfiltrated by any XSS. Always `httpOnly` cookie.
2. **No refresh rotation** — refresh tokens long-lived + non-rotating → one leak = forever access. Rotate on every use, detect reuse, revoke the family.
3. **CORS too permissive in dev leaks to prod.** `Access-Control-Allow-Origin: *` with credentials is rejected by browsers — but devs often set both to silence the error. Explicit allowlist, env-driven.
4. **Multipart body parser on every route.** Mount it only on the upload route. Otherwise every POST allocates buffers.
5. **WS auth race**: client connects before the cookie is set. Solve by gating the WS connection on a successful `/me` REST call, not on app boot.

## References
- tRPC: https://trpc.io
- OWASP JWT cheat sheet: https://cheatsheetseries.owasp.org/cheatsheets/JSON_Web_Token_for_Java_Cheat_Sheet.html
- Refresh-token rotation: https://auth0.com/docs/secure/tokens/refresh-tokens/refresh-token-rotation
- Fastify: https://fastify.dev
- Hono: https://hono.dev
- ws upgrade: https://github.com/websockets/ws#external-https-server

## Hello world (login → ws upgrade)
```ts
// apps/api/src/routes/auth.ts (Fastify)
app.post('/login', { schema: { body: LoginSchema } }, async (req, reply) => {
  const user = await verify(req.body)
  const access = signAccess({ sub: user.id }, '15m')
  const refresh = await issueRefresh(user.id)   // rotates a family id
  reply
    .setCookie('access',  access,  { httpOnly: true, secure: true, sameSite: 'lax', path: '/' })
    .setCookie('refresh', refresh, { httpOnly: true, secure: true, sameSite: 'lax', path: '/auth/refresh' })
    .send({ ok: true })
})

// apps/api/src/ws/index.ts
server.on('upgrade', async (req, sock, head) => {
  const user = await userFromCookie(req.headers.cookie)
  if (!user) return sock.destroy()
  wss.handleUpgrade(req, sock, head, ws => wss.emit('connection', ws, user))
})
```
