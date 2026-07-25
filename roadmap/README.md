# roadmap/

Machine-readable roadmap with **traceable spec references** (spec-005 AC-5a, gap G5a).

The prose Now/Next/Later board lives at the repo-root [`roadmap.md`](../roadmap.md). This
folder holds the *checkable* companion: [`ROADMAP.md`](ROADMAP.md) carries one row per
roadmap item in a fixed grammar so `validate.sh` can prove every `spec:` reference resolves.

## Row schema

Each roadmap item is a single Markdown list row:

```
- [ ] <title> | spec:NNN | quarter:YYYY-Qn | status: planned|active|shipped
```

| Field        | Required | Meaning                                                        |
|--------------|----------|----------------------------------------------------------------|
| `<title>`    | yes      | Short human label for the item                                 |
| `spec:NNN`   | when known | Numeric id of the spec that realizes this item. Must resolve to `specs/active/NNN-*.md` or `specs/archive/NNN-*.md`. Omit for items not yet specified. |
| `quarter:`   | optional | Planning bucket, e.g. `2026-Q3`                                |
| `status:`    | optional | `planned` \| `active` \| `shipped`                             |

The checkbox (`[ ]` / `[x]`) is free — use it however you track delivery.

## The trace gate

`validate.sh` runs a `[roadmap-trace]` block: for every `spec:NNN` token in the roadmap
file, it **warns** (advisory, never a hard fail — consistent with `[spec-plan-trace]`) if
no `specs/{active,archive}/NNN-*.md` resolves. An item without any `spec:` token is fine —
not every roadmap entry has a spec yet. The gate only catches *dangling* references: a
`spec:NNN` that points nowhere, which is a traceability hole.

The file it scans is overridable via `ROADMAP_FILE` (used by the hermetic test
`.claude/scripts/test/roadmap-trace.sh`); it defaults to `roadmap/ROADMAP.md`.

## Also here

- [`changelog.md`](changelog.md) — append-only audit trail of Now/Next/Later changes,
  written by `.claude/hooks/post-write-roadmap.sh` on edits to the root `roadmap.md`.
