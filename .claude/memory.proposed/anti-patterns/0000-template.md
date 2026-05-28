---
name: 0000-anti-pattern-template
description: Anti-pattern — "we tried this; it produced this problem; don't retry unless these conditions change". Inverted pattern template. Round 7 D.
metadata:
  type: anti-pattern
  status: template
slug: <kebab-case>
written_at: YYYY-MM-DD
written_by: human | extractor
origin_initiative: <id>    # which initiative discovered this anti-pattern
status: active             # active | superseded (don't-retry rule relaxed because conditions changed)
severity: blocker | high | medium    # how bad is the problem if you retry?
---

# Anti-pattern: <Name>

> Distinct from a [pattern](../patterns/0000-template.md) (something to do) — this is something **not** to do, and the why.

## Problem we were trying to solve

What seemed reasonable at the time? Don't hindsight-bias this — describe the actual reasoning. The next engineer who arrives at the same fork in the road needs to understand the appeal.

## What we tried

The concrete approach. Include enough code/architecture detail that someone can recognize "oh, I'm about to try the same thing."

```ts
// The shape of the failed attempt
```

## How it failed

The disconfirming evidence. Specific outcomes, not opinions:

- Performance: <metric>
- Correctness: <bug class>
- Maintainability: <complexity score>
- Operational cost: <incidents, on-call burden>
- Customer impact: <churn, NPS, support volume>

## Why it failed (root cause)

The mechanism. Not "it just didn't work" but the actual cause.

## Don't retry unless

What conditions would need to change to make this approach viable again? Be specific:

- [ ] The underlying framework gains feature X (cite roadmap if external)
- [ ] We hit scale milestone Y (where the prior bottleneck dissolves)
- [ ] Customer expectation Z shifts (e.g., async UX becomes acceptable)

If none of these can ever change, mark `status: permanent`.

## What to do instead

Link to the pattern that replaced it (or note "open problem"):

- See: [`.claude/memory/patterns/<better-approach>.md`]

## Detection

How does code review catch a retry? Ideally codified as a lint rule:

```yaml
# .semgrep/learned/<slug>.yml (auto-drafted by /codify-rule on recurrence)
- id: anti-pattern-<slug>
  pattern: <the offending shape>
  message: |
    This matches the anti-pattern from initiative <origin>.
    See: .claude/memory/anti-patterns/<slug>.md
  severity: WARNING
```

## Examples in commit history (don't repeat)

- `<sha>` — `<file>:<line>` — initial introduction
- `<sha>` — revert
- `<sha>` — second attempt (also failed)

## Related

- Pattern that replaces this: [name](../patterns/...)
- Origin initiative: [link](../../../initiatives/archive/...)
- Post-mortem: [link](../post-mortems/...)
