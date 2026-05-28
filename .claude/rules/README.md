# .claude/rules/

Path-scoped rule files. Each file has a `paths:` frontmatter glob; Claude Code loads the body **only when working in matching files**. Different from `.claude/CLAUDE.md` which is always loaded.

## Why path-scoped?

A frontend rule like "every component must use the design tokens from `src/styles/tokens.ts`" is irrelevant when Claude is editing the Postgres migrations. Loading it always would burn ~200 tokens per turn for nothing. Path-scoping means it only enters context when relevant.

## Format

```markdown
---
paths:
  - "src/web/**/*.tsx"
  - "src/web/**/*.css"
---

# Frontend rules

(body — loaded only when Claude touches matching paths)
```

## What's in this folder

- [frontend.md](frontend.md) — UI/component rules (loads on `src/web/**`, `app/**`, `components/**`)
- [backend.md](backend.md) — API/service/DB rules (loads on `src/api/**`, `src/services/**`, `migrations/**`)
- [security.md](security.md) — auth/data-handling rules (loads on `**/auth/**`, `**/login/**`, `**/session/**`, `**/token/**`)
- [tests.md](tests.md) — test-writing rules (loads on `**/*.test.*`, `**/*.spec.*`, `tests/**`)

## Per-project customization

These four files are starter templates. Edit them to your stack. Add new files like `infra.md`, `ml.md`, `mobile.md` as needed — Claude Code globs them automatically.

## Reference

- Claude Code memory & rules: https://code.claude.com/docs/en/memory
