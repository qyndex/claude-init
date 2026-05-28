---
name: api-versioning
description: Manage public API version transitions — v2-alongside-v1, Deprecation/Sunset headers, client migration tracker. Use when a breaking API change is needed but cannot ship as a wire-break.
when_to_use: A spec requires changing the API contract (request/response shape, error codes, auth scheme). User says "breaking change to API", "v2 endpoint", "deprecate API".
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, WebFetch
model: opus
---

# API Versioning

Public APIs can't break clients. This skill encodes the v2-alongside-v1 dance with explicit sunset.

## When to version

| Change | Requires version bump |
|---|---|
| Add a new field (response) | No — additive, no bump |
| Add a new optional request param | No |
| Remove a field | YES — breaking |
| Change a field type | YES |
| Change a field's semantic meaning | YES |
| Tighten validation | Usually YES (may reject previously-valid input) |
| Change error code | YES |
| Change auth scheme | YES |
| Rename endpoint | YES |

## Process

1. **Decide cut-line** — what changes go into v2 (don't drip; one v2 per logical theme).
2. **Build v2 alongside v1.** Both endpoints live. v1 stays as-is.
3. **Announce deprecation** — v1 endpoints emit `Deprecation: <ISO-date>` and `Sunset: <ISO-date>` HTTP headers ([RFC 8594](https://datatracker.ietf.org/doc/html/rfc8594)).
4. **Track client migration** — query analytics for v1 usage; identify top callers; reach out.
5. **Reduce v1 traffic** — month-by-month migration; report % migrated weekly.
6. **Final warning** — 30 days before sunset, emit louder warnings (log + status page).
7. **Sunset** — v1 returns `410 Gone` with migration guide URL. Keep `410` for ≥ 90 days.
8. **Remove** — delete v1 code, schema, tests. Update SDK / docs / OpenAPI spec.

## Per-endpoint deprecation header

```http
HTTP/1.1 200 OK
Content-Type: application/json
Deprecation: Sat, 28 May 2027 00:00:00 GMT
Sunset: Wed, 28 Nov 2027 00:00:00 GMT
Link: <https://api.example.com/v2/users>; rel="successor-version"
Link: <https://docs.example.com/migrate/v1-to-v2>; rel="deprecation"
```

## Tracking artifact

```yaml
# .claude/memory/deprecations/api-v1.yaml
api: v1
announced: 2026-05-28
sunset: 2027-11-28
successor: v2

endpoints:
  - path: GET /v1/users
    successor: GET /v2/users
    callers:
      total: 247
      migrated: 198
      remaining:
        - { client: "mobile-ios v3.4", contact: "@mobile" }
        - { client: "internal-cron", contact: "@platform" }
        - { client: "partner XYZ", contact: "partners@example.com" }

  - path: GET /v1/orders
    successor: GET /v2/orders
    callers:
      total: 89
      migrated: 89
      remaining: []   # safe to sunset early
```

## Hard rules

- **6-month minimum sunset window** for external APIs. 90-day minimum for internal.
- **Both versions must be tested**. Don't let v1 rot during the transition.
- **Sunset day is announced once and held**. Don't extend repeatedly — credibility erodes.
- **`410 Gone` for ≥ 90 days post-sunset** before deleting endpoints. Some clients are slow.
- **Migration guide is required**. Link from the deprecation header.

## CI gates

- New endpoint adds `Deprecation`/`Sunset` headers if `/deprecate-api` was run on it
- E2E tests cover both v1 and v2 until v1 is removed
- Spec lists v2's `supersedes:` referring to v1's spec

## References

- RFC 8594 — Sunset HTTP header
- IETF draft — Deprecation header field
- See also: `.claude/memory/deprecations/REGISTRY.md`
- `/deprecate-api` command
