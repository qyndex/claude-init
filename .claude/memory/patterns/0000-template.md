---
name: 0000-pattern-template
description: Codebase pattern template — copy to a new file and fill in.
metadata:
  type: pattern
  status: template
---

# Pattern: <Name>

- **When to use**: <one line>
- **When NOT to use**: <one line>
- **Status**: established | emerging | deprecated
- **Owner**: @<human>     # who can answer questions about this pattern
- **written_by**: human | reviewer | dream    # Round 5 C2 — provenance; "dream" = consolidated by auto-dream
- **source_session**: <session-id>  # if written by an agent
- **last_verified**: YYYY-MM-DD    # bumped by reviewer when the pattern is observed again in a clean diff
- **verified_in_commits**: [<sha>, <sha>]   # commits where this pattern was applied and reviewed clean (rotate: keep last 20)
- **recurred_anti**: 0    # incremented when the anti-pattern was caught in review; >2 → /codify-rule auto-drafts semgrep rule

## Problem

What recurring problem does this pattern solve?

## Solution

The structure of the solution, with a canonical example.

```ts
// canonical example
```

## Variations

- Variation A — when ...
- Variation B — when ...

## Anti-patterns

- Don't ... because ...

## Examples in the codebase

- `src/foo/bar.ts:42` — canonical usage
- `src/baz/qux.ts:88` — variation A

## Promotion criteria

A pattern is promoted from `emerging → established` when:
- Used ≥3 times across ≥2 different modules
- No anti-pattern violations caught in 90 days
- An owner is named

A pattern is demoted to `deprecated` when:
- A new ADR supersedes the approach
- The framework or language idiom this is built on becomes legacy
- An incident demonstrates a flaw

## Related

- ADR-XXXX
- Pattern: `<other-pattern>`
- Lint rule: `<eslint-rule-name>` (if codified)
