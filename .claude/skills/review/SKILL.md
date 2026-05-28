---
name: review
description: Run code review and (optionally) security review on the current diff. Phase 7 of the eight-phase workflow. Delegates to reviewer + security agents. Multi-pass — each finding is re-verified to filter false positives (Anthropic pattern).
when_to_use: Implementation + verification complete; about to /ship. User says "review", "code review", "security review", "audit", "lgtm?".
argument-hint: "[--security] [--diff <ref>]"
model: opus
allowed-tools: Read, Glob, Grep, Bash, TodoWrite
---

# Review

Two-pass review on the current diff: code-quality first, security second.

## Process

1. **Determine the diff** — default to `git diff main...HEAD`. Override with `--diff <ref>`.
2. **Delegate to `reviewer` agent** for code-quality review.
3. **Delegate to `security` agent** for security review (always if `--security`, automatic if the diff touches auth/data/network/secrets/deps).
4. **Collate findings** into a single severity-sorted list.
5. **Re-verify each finding** before reporting (anti-false-positive pass).
6. **Post results** as a structured comment (PR or chat).
7. **Block /ship** if any blocker or high remains.

## Trigger conditions for automatic security pass

- Diff touches `**/auth/**`, `**/login/**`, `**/session/**`, `**/token/**`
- Diff touches database queries (SQL files, ORM definitions, migrations)
- Diff touches network code (fetch, axios, requests, http handlers)
- Diff modifies `package.json`, `requirements.txt`, `Cargo.toml`, `go.mod`
- Diff includes new env var reads
- Diff includes user-input handlers (forms, parsing, deserialization)

## Output

```
# Review — <feature> — <date>

## Code review
### Blockers (0)
### Highs (1)
- [H-1] login.ts:42 — race condition between session lookup and update; use SELECT FOR UPDATE.

### Mediums (2) / Lows (3) / Nits (5)
- ...

## Security review
### Critical (0)
### High (0)
### Medium (1)
- [M-1] User-controlled `redirect_uri` not allowlisted (open redirect). Fix: validate against config.

## Verdict
PASS-WITH-CHANGES — address H-1 and M-1 before /ship.
```

After save: "Review complete — <blocker> blockers, <high> highs. /ship blocked." OR "Review clean. Ready for /ship."
